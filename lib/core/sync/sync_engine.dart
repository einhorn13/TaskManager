import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database.dart';
import '../notifications/task_notification_service.dart';
import '../providers.dart';
import 'supabase_config.dart';
import 'supabase_sync_gateway.dart';
import 'sync_contract.dart';

enum SyncActivity { disabled, idle, syncing, success, error }

class SyncStatus {
  final SyncActivity activity;
  final DateTime? lastSuccess;
  final String? error;
  const SyncStatus(this.activity, {this.lastSuccess, this.error});
}

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus(
    SupabaseConfig.enabled ? SyncActivity.idle : SyncActivity.disabled));

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.watch(databaseProvider), ref);
  ref.onDispose(engine.stop);
  return engine;
});

class SyncEngine {
  final AppDatabase db;
  final Ref ref;
  Timer? _timer;
  Timer? _outboxDebounce;
  StreamSubscription<List<SyncOperation>>? _outboxSubscription;
  RealtimeChannel? _realtimeChannel;
  bool _running = false;
  bool _syncRequested = false;
  String? _userId;

  SyncEngine(this.db, this.ref);

  Future<void> startForUser(String userId) async {
    if (_userId == userId && (_timer != null || _outboxSubscription != null)) {
      await syncNow();
      return;
    }
    stop();
    _userId = userId;
    await _claimLocalData(userId);
    await syncNow();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    _outboxSubscription = db.select(db.syncOperations).watch().listen((rows) {
      final now = DateTime.now();
      if (!rows.any((row) =>
          row.nextAttemptAt == null || !row.nextAttemptAt!.isAfter(now))) {
        return;
      }
      _outboxDebounce?.cancel();
      _outboxDebounce = Timer(const Duration(milliseconds: 350), syncNow);
    });
    _realtimeChannel = Supabase.instance.client
        .channel('task-manager-sync-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (_) => syncNow(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'folders',
          callback: (_) => syncNow(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'checklists',
          callback: (_) => syncNow(),
        )
        .subscribe();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _outboxDebounce?.cancel();
    _outboxDebounce = null;
    _outboxSubscription?.cancel();
    _outboxSubscription = null;
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null && SupabaseConfig.enabled) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    _userId = null;
  }

  Future<void> syncNow() async {
    if (_userId == null || !SupabaseConfig.enabled) return;
    if (_running) {
      _syncRequested = true;
      return;
    }
    _running = true;
    _syncRequested = false;
    var pendingRows = <SyncOperation>[];
    ref.read(syncStatusProvider.notifier).state =
        const SyncStatus(SyncActivity.syncing);
    try {
      final gateway = SupabaseSyncRemoteGateway(Supabase.instance.client);
      final now = DateTime.now();
      final rows = await (db.select(db.syncOperations)
            ..where((row) =>
                row.nextAttemptAt.isNull() |
                row.nextAttemptAt.isSmallerOrEqualValue(now))
            ..orderBy([(row) => OrderingTerm.asc(row.id)]))
          .get();
      pendingRows = rows;
      final latest = <String, SyncOperation>{};
      for (final row in rows) {
        latest['${row.entityType}:${row.entityId}'] = row;
      }
      final operations = await buildPushPlan(latest.values);
      await gateway.push(operations);
      await db.transaction(() async {
        for (final row in rows) {
          await (db.delete(db.syncOperations)
                ..where((x) => x.id.equals(row.id)))
              .go();
        }
        for (final operation in operations) {
          await _markSynced(operation.entityType, operation.entityId);
        }
      });

      final checkpoint = await (db.select(db.syncMetadata)
            ..where((row) => row.key.equals('last_pull')))
          .getSingleOrNull();
      final pulled = await gateway.pull(
          changedAfter:
              checkpoint == null ? null : DateTime.tryParse(checkpoint.value));
      await db.transaction(() async {
        for (final row in orderPulledChanges(pulled.changes)) {
          await _applyRemote(row);
        }
        await db.into(db.syncMetadata).insertOnConflictUpdate(
            SyncMetadataCompanion.insert(
                key: 'last_pull',
                value: pulled.serverTimestamp.toIso8601String()));
      });
      final tasksForNotifications = await (db.select(db.tasks)
            ..where((task) => task.deletedAt.isNull()))
          .get();
      await TaskNotificationService.instance
          .rescheduleAll(tasksForNotifications);
      ref.read(syncStatusProvider.notifier).state =
          SyncStatus(SyncActivity.success, lastSuccess: DateTime.now());
    } catch (error) {
      final retryAt = DateTime.now().add(const Duration(minutes: 2));
      for (final row in pendingRows) {
        await (db.update(db.syncOperations)..where((x) => x.id.equals(row.id)))
            .write(SyncOperationsCompanion(
          attempts: Value(row.attempts + 1),
          lastError: Value(error.toString()),
          nextAttemptAt: Value(retryAt),
        ));
      }
      ref.read(syncStatusProvider.notifier).state =
          SyncStatus(SyncActivity.error, error: error.toString());
    } finally {
      _running = false;
      if (_syncRequested && _userId != null) {
        _syncRequested = false;
        unawaited(syncNow());
      }
    }
  }

  Future<void> _claimLocalData(String userId) async {
    await db.transaction(() async {
      await (db.update(db.folders)..where((x) => x.userId.equals('local')))
          .write(FoldersCompanion(
              userId: Value(userId), syncState: const Value('pending')));
      await (db.update(db.tags)..where((x) => x.userId.equals('local'))).write(
          TagsCompanion(
              userId: Value(userId), syncState: const Value('pending')));
      await (db.update(db.tasks)..where((x) => x.userId.equals('local'))).write(
          TasksCompanion(
              userId: Value(userId), syncState: const Value('pending')));
      await (db.update(db.checklistTemplates)
            ..where((x) => x.userId.equals('local')))
          .write(ChecklistTemplatesCompanion(
              userId: Value(userId), syncState: const Value('pending')));
      await (db.update(db.checklists)..where((x) => x.userId.equals('local')))
          .write(ChecklistsCompanion(
              userId: Value(userId), syncState: const Value('pending')));
      await _enqueuePendingForUser(userId);
    });
  }

  Future<void> _enqueuePendingForUser(String userId) async {
    const direct = {
      'folders': 'folder',
      'tags': 'tag',
      'tasks': 'task',
      'checklist_templates': 'checklistTemplate',
      'checklists': 'checklist',
    };
    for (final entry in direct.entries) {
      await db.customStatement('''
        INSERT INTO sync_operations(entity_type, entity_id, operation, created_at)
        SELECT ?, source.id, 'upsert', unixepoch()
        FROM ${entry.key} source
        WHERE source.user_id = ? AND source.sync_state = 'pending'
          AND NOT EXISTS (
            SELECT 1 FROM sync_operations pending
            WHERE pending.entity_type = ? AND pending.entity_id = source.id)
      ''', [entry.value, userId, entry.value]);
    }
    await db.customStatement('''
      INSERT INTO sync_operations(entity_type, entity_id, operation, created_at)
      SELECT 'attachment', attachment.id, 'upsert', unixepoch()
      FROM task_attachments attachment
      JOIN tasks task ON task.id = attachment.task_id
      WHERE task.user_id = ? AND attachment.sync_state = 'pending'
        AND NOT EXISTS (SELECT 1 FROM sync_operations pending
          WHERE pending.entity_type = 'attachment'
            AND pending.entity_id = attachment.id)
    ''', [userId]);
    await db.customStatement('''
      INSERT INTO sync_operations(entity_type, entity_id, operation, created_at)
      SELECT 'checklistItem', item.id, 'upsert', unixepoch()
      FROM checklist_items item
      JOIN checklists list ON list.id = item.checklist_id
      WHERE list.user_id = ? AND item.sync_state = 'pending'
        AND NOT EXISTS (SELECT 1 FROM sync_operations pending
          WHERE pending.entity_type = 'checklistItem'
            AND pending.entity_id = item.id)
    ''', [userId]);
  }

  String? _date(DateTime? value) => value?.toUtc().toIso8601String();
  DateTime? _parse(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

  Future<List<SyncPushOperation>> buildPushPlan(
      Iterable<SyncOperation> rows) async {
    final planned = <String, SyncPushOperation>{};
    final visiting = <String>{};

    Future<void> add(SyncEntityType entity, String id) async {
      final key = '${entity.name}:$id';
      if (planned.containsKey(key) || !visiting.add(key)) return;
      try {
        for (final dependency in await _dependencies(entity, id)) {
          await add(dependency.$1, dependency.$2);
        }
        final payload = await _serialize(entity, id);
        if (payload != null) {
          planned[key] = SyncPushOperation(entity, id, payload);
        }
      } finally {
        visiting.remove(key);
      }
    }

    for (final row in rows) {
      final entity = SyncEntityType.fromName(row.entityType);
      if (entity != null) await add(entity, row.entityId);
    }
    return planned.values.toList();
  }

  Future<List<(SyncEntityType, String)>> _dependencies(
      SyncEntityType entity, String id) async {
    switch (entity) {
      case SyncEntityType.folder:
      case SyncEntityType.tag:
      case SyncEntityType.checklistTemplate:
        return const [];
      case SyncEntityType.task:
        final task = await (db.select(db.tasks)..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        if (task == null) return const [];
        final result = <(SyncEntityType, String)>[];
        if (task.folderId != null) {
          final folder = await (db.select(db.folders)
                ..where((x) => x.id.equals(task.folderId!)))
              .getSingleOrNull();
          if (folder != null &&
              (folder.userId == task.userId ||
                  (task.spaceId != null && folder.spaceId == task.spaceId))) {
            result.add((SyncEntityType.folder, folder.id));
          }
        }
        if (task.parentTaskId != null) {
          final parent = await (db.select(db.tasks)
                ..where((x) => x.id.equals(task.parentTaskId!)))
              .getSingleOrNull();
          if (parent != null &&
              (parent.userId == task.userId ||
                  (task.spaceId != null && parent.spaceId == task.spaceId))) {
            result.add((SyncEntityType.task, parent.id));
          }
        }
        final links = await (db.select(db.taskTags)
              ..where((link) => link.taskId.equals(id)))
            .get();
        for (final link in links) {
          final tag = await (db.select(db.tags)
                ..where((x) => x.id.equals(link.tagId)))
              .getSingleOrNull();
          // A collaborator may read the owner's tags through RLS, but must not
          // upsert those tag rows. They already exist before sharing.
          if (tag?.userId == SupabaseConfig.activeUserId) {
            result.add((SyncEntityType.tag, tag!.id));
          }
        }
        return result;
      case SyncEntityType.attachment:
        final attachment = await (db.select(db.taskAttachments)
              ..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        return attachment == null
            ? const []
            : [(SyncEntityType.task, attachment.taskId)];
      case SyncEntityType.checklist:
        final checklist = await (db.select(db.checklists)
              ..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        if (checklist == null || checklist.templateId == null) return const [];
        final template = await (db.select(db.checklistTemplates)
              ..where((x) => x.id.equals(checklist.templateId!)))
            .getSingleOrNull();
        return template?.userId == checklist.userId
            ? [(SyncEntityType.checklistTemplate, template!.id)]
            : const [];
      case SyncEntityType.checklistItem:
        final item = await (db.select(db.checklistItems)
              ..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        return item == null
            ? const []
            : [(SyncEntityType.checklist, item.checklistId)];
    }
  }

  List<Map<String, Object?>> orderPulledChanges(
      List<Map<String, Object?>> changes) {
    const rank = {
      'folder': 0,
      'tag': 0,
      'checklistTemplate': 0,
      'task': 1,
      'checklist': 1,
      'attachment': 2,
      'checklistItem': 2,
    };
    final remaining = [...changes]..sort((a, b) =>
        (rank[a['_entity_type']] ?? 99)
            .compareTo(rank[b['_entity_type']] ?? 99));
    final result = <Map<String, Object?>>[];
    final remoteTaskIds = remaining
        .where((row) => row['_entity_type'] == 'task')
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();
    final emittedTaskIds = <String>{};
    while (remaining.isNotEmpty) {
      final index = remaining.indexWhere((row) {
        if (row['_entity_type'] != 'task') return true;
        final parent = row['parent_task_id']?.toString();
        return parent == null ||
            !remoteTaskIds.contains(parent) ||
            emittedTaskIds.contains(parent);
      });
      final next = remaining.removeAt(index < 0 ? 0 : index);
      result.add(next);
      if (next['_entity_type'] == 'task') {
        emittedTaskIds.add(next['id'].toString());
      }
    }
    return result;
  }

  Future<Map<String, Object?>?> _serialize(
      SyncEntityType entity, String id) async {
    switch (entity) {
      case SyncEntityType.folder:
        final x = await (db.select(db.folders)..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        return x == null
            ? null
            : {
                'id': x.id,
                'user_id': x.userId,
                'space_id': x.spaceId,
                'name': x.name,
                'color': x.color,
                'created_at': _date(x.createdAt),
                'updated_at': DateTime.now().toUtc().toIso8601String(),
                'deleted_at': _date(x.deletedAt)
              };
      case SyncEntityType.tag:
        final x = await (db.select(db.tags)..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        return x == null
            ? null
            : {
                'id': x.id,
                'user_id': x.userId,
                'name': x.name,
                'created_at': _date(x.createdAt),
                'updated_at': DateTime.now().toUtc().toIso8601String(),
                'deleted_at': _date(x.deletedAt)
              };
      case SyncEntityType.task:
        final x = await (db.select(db.tasks)..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        if (x == null) return null;
        final links = await (db.select(db.taskTags)
              ..where((l) => l.taskId.equals(id)))
            .get();
        String? folderId;
        if (x.folderId != null) {
          final folder = await (db.select(db.folders)
                ..where((folder) => folder.id.equals(x.folderId!)))
              .getSingleOrNull();
          if (folder != null &&
              (folder.userId == x.userId ||
                  (x.spaceId != null && folder.spaceId == x.spaceId))) {
            folderId = folder.id;
          }
        }
        String? parentTaskId;
        if (x.parentTaskId != null) {
          final parent = await (db.select(db.tasks)
                ..where((task) => task.id.equals(x.parentTaskId!)))
              .getSingleOrNull();
          if (parent != null &&
              (parent.userId == x.userId ||
                  (x.spaceId != null && parent.spaceId == x.spaceId))) {
            parentTaskId = parent.id;
          }
        }
        final tagIds = <String>[];
        for (final link in links) {
          final tag = await (db.select(db.tags)
                ..where((tag) => tag.id.equals(link.tagId)))
              .getSingleOrNull();
          if (tag?.userId == x.userId) tagIds.add(link.tagId);
        }
        return {
          'id': x.id,
          'user_id': x.userId,
          'space_id': x.spaceId,
          'folder_id': folderId,
          'parent_task_id': parentTaskId,
          'title': x.title,
          'description': x.description,
          'due_date': _date(x.dueDate),
          'duration_minutes': x.durationMinutes,
          'base_priority': x.basePriority,
          'status': x.status,
          'completed_at': _date(x.completedAt),
          'position': x.position,
          'expiring_threshold_days_override': x.expiringThresholdDaysOverride,
          'recurrence_rule': x.recurrenceRule,
          'snooze_count': x.snoozeCount,
          'is_pinned': x.isPinned,
          'tag_ids': tagIds,
          'created_at': _date(x.createdAt),
          'updated_at': _date(x.updatedAt),
          'deleted_at': _date(x.deletedAt)
        };
      case SyncEntityType.attachment:
        final x = await (db.select(db.taskAttachments)
              ..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        if (x == null) return null;
        final task = await (db.select(db.tasks)
              ..where((t) => t.id.equals(x.taskId)))
            .getSingleOrNull();
        if (task == null) return null;
        return {
          'id': x.id,
          'user_id': task.userId,
          'task_id': x.taskId,
          'type': x.type,
          'url': x.url,
          'created_at': _date(x.createdAt),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_at': _date(x.deletedAt)
        };
      case SyncEntityType.checklistTemplate:
        final x = await (db.select(db.checklistTemplates)
              ..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        if (x == null) return null;
        final items = await (db.select(db.checklistTemplateItems)
              ..where((i) => i.templateId.equals(id))
              ..orderBy([(i) => OrderingTerm.asc(i.position)]))
            .get();
        return {
          'id': x.id,
          'user_id': x.userId,
          'title': x.title,
          'items': items
              .map((i) => {'id': i.id, 'text': i.text_, 'position': i.position})
              .toList(),
          'created_at': _date(x.createdAt),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_at': _date(x.deletedAt)
        };
      case SyncEntityType.checklist:
        final x = await (db.select(db.checklists)
              ..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        if (x == null) return null;
        String? templateId;
        if (x.templateId != null) {
          final template = await (db.select(db.checklistTemplates)
                ..where((template) => template.id.equals(x.templateId!)))
              .getSingleOrNull();
          if (template?.userId == x.userId) templateId = template!.id;
        }
        return {
          'id': x.id,
          'user_id': x.userId,
          'space_id': x.spaceId,
          'title': x.title,
          'template_id': templateId,
          'created_at': _date(x.createdAt),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_at': _date(x.deletedAt)
        };
      case SyncEntityType.checklistItem:
        final x = await (db.select(db.checklistItems)
              ..where((x) => x.id.equals(id)))
            .getSingleOrNull();
        if (x == null) return null;
        final list = await (db.select(db.checklists)
              ..where((c) => c.id.equals(x.checklistId)))
            .getSingleOrNull();
        if (list == null) return null;
        return {
          'id': x.id,
          'user_id': list.userId,
          'checklist_id': x.checklistId,
          'text': x.text_,
          'is_done': x.isDone,
          'position': x.position,
          'created_at': _date(x.createdAt),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_at': _date(x.deletedAt)
        };
    }
  }

  Future<void> _markSynced(SyncEntityType entity, String id) async {
    switch (entity) {
      case SyncEntityType.folder:
        await (db.update(db.folders)..where((x) => x.id.equals(id)))
            .write(const FoldersCompanion(syncState: Value('synced')));
      case SyncEntityType.tag:
        await (db.update(db.tags)..where((x) => x.id.equals(id)))
            .write(const TagsCompanion(syncState: Value('synced')));
      case SyncEntityType.task:
        await (db.update(db.tasks)..where((x) => x.id.equals(id)))
            .write(const TasksCompanion(syncState: Value('synced')));
      case SyncEntityType.attachment:
        await (db.update(db.taskAttachments)..where((x) => x.id.equals(id)))
            .write(const TaskAttachmentsCompanion(syncState: Value('synced')));
      case SyncEntityType.checklistTemplate:
        await (db.update(db.checklistTemplates)..where((x) => x.id.equals(id)))
            .write(
                const ChecklistTemplatesCompanion(syncState: Value('synced')));
      case SyncEntityType.checklist:
        await (db.update(db.checklists)..where((x) => x.id.equals(id)))
            .write(const ChecklistsCompanion(syncState: Value('synced')));
      case SyncEntityType.checklistItem:
        await (db.update(db.checklistItems)..where((x) => x.id.equals(id)))
            .write(const ChecklistItemsCompanion(syncState: Value('synced')));
    }
  }

  Future<void> _applyRemote(Map<String, Object?> row) async {
    final entity = SyncEntityType.fromName(row['_entity_type'].toString());
    if (entity == null) return;
    final id = row['id'].toString();
    switch (entity) {
      case SyncEntityType.folder:
        await db.into(db.folders).insertOnConflictUpdate(
            FoldersCompanion.insert(
                id: id,
                userId: row['user_id'].toString(),
                spaceId: Value(row['space_id'] as String?),
                name: row['name'].toString(),
                color: Value(row['color'] as String?),
                createdAt: Value(_parse(row['created_at'])!),
                syncState: const Value('synced'),
                deletedAt: Value(_parse(row['deleted_at']))));
      case SyncEntityType.tag:
        await db.into(db.tags).insertOnConflictUpdate(TagsCompanion.insert(
            id: id,
            userId: row['user_id'].toString(),
            name: row['name'].toString(),
            createdAt: Value(_parse(row['created_at'])!),
            syncState: const Value('synced'),
            deletedAt: Value(_parse(row['deleted_at']))));
      case SyncEntityType.task:
        await db.into(db.tasks).insertOnConflictUpdate(TasksCompanion.insert(
            id: id,
            userId: row['user_id'].toString(),
            spaceId: Value(row['space_id'] as String?),
            title: row['title'].toString(),
            folderId: Value(row['folder_id'] as String?),
            parentTaskId: Value(row['parent_task_id'] as String?),
            description: Value(row['description'] as String?),
            dueDate: Value(_parse(row['due_date'])),
            durationMinutes: Value(row['duration_minutes'] as int?),
            basePriority: Value((row['base_priority'] as num?)?.toInt() ?? 1),
            status: Value(row['status']?.toString() ?? 'todo'),
            completedAt: Value(_parse(row['completed_at'])),
            position: Value((row['position'] as num?)?.toDouble()),
            expiringThresholdDaysOverride: Value(
                (row['expiring_threshold_days_override'] as num?)?.toInt()),
            recurrenceRule: Value(row['recurrence_rule'] as String?),
            snoozeCount: Value((row['snooze_count'] as num?)?.toInt() ?? 0),
            isPinned: Value(row['is_pinned'] as bool? ?? false),
            createdAt: Value(_parse(row['created_at'])!),
            updatedAt: Value(_parse(row['updated_at'])!),
            syncState: const Value('synced'),
            deletedAt: Value(_parse(row['deleted_at']))));
        await (db.delete(db.taskTags)..where((x) => x.taskId.equals(id))).go();
        for (final tagId in (row['tag_ids'] as List? ?? const [])) {
          await db.into(db.taskTags).insert(
              TaskTagsCompanion.insert(taskId: id, tagId: tagId.toString()),
              mode: InsertMode.insertOrIgnore);
        }
      case SyncEntityType.attachment:
        await db.into(db.taskAttachments).insertOnConflictUpdate(
            TaskAttachmentsCompanion.insert(
                id: id,
                taskId: row['task_id'].toString(),
                type: row['type'].toString(),
                url: row['url'].toString(),
                createdAt: Value(_parse(row['created_at'])!),
                syncState: const Value('synced'),
                deletedAt: Value(_parse(row['deleted_at']))));
      case SyncEntityType.checklistTemplate:
        await db.into(db.checklistTemplates).insertOnConflictUpdate(
            ChecklistTemplatesCompanion.insert(
                id: id,
                userId: row['user_id'].toString(),
                title: row['title'].toString(),
                createdAt: Value(_parse(row['created_at'])!),
                syncState: const Value('synced'),
                deletedAt: Value(_parse(row['deleted_at']))));
        await (db.delete(db.checklistTemplateItems)
              ..where((x) => x.templateId.equals(id)))
            .go();
        for (final raw in (row['items'] as List? ?? const [])) {
          final item = Map<String, Object?>.from(raw as Map);
          await db.into(db.checklistTemplateItems).insert(
              ChecklistTemplateItemsCompanion.insert(
                  id: item['id'].toString(),
                  templateId: id,
                  text_: item['text'].toString(),
                  position: Value((item['position'] as num?)?.toDouble())));
        }
      case SyncEntityType.checklist:
        await db.into(db.checklists).insertOnConflictUpdate(
            ChecklistsCompanion.insert(
                id: id,
                userId: row['user_id'].toString(),
                spaceId: Value(row['space_id'] as String?),
                title: row['title'].toString(),
                templateId: Value(row['template_id'] as String?),
                createdAt: Value(_parse(row['created_at'])!),
                syncState: const Value('synced'),
                deletedAt: Value(_parse(row['deleted_at']))));
      case SyncEntityType.checklistItem:
        await db.into(db.checklistItems).insertOnConflictUpdate(
            ChecklistItemsCompanion.insert(
                id: id,
                checklistId: row['checklist_id'].toString(),
                text_: row['text'].toString(),
                isDone: Value(row['is_done'] as bool? ?? false),
                position: Value((row['position'] as num?)?.toDouble()),
                createdAt: Value(_parse(row['created_at'])!),
                syncState: const Value('synced'),
                deletedAt: Value(_parse(row['deleted_at']))));
    }
  }
}
