import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/database.dart';
import '../../../core/sync/supabase_config.dart';

const _uuid = Uuid();

class TaskExtrasRepository {
  final AppDatabase db;
  TaskExtrasRepository(this.db);

  Stream<List<Tag>> watchTags() =>
      (db.select(db.tags)..where((t) => t.deletedAt.isNull())).watch();

  Stream<List<String>> watchTaskTagIds(String taskId) =>
      (db.select(db.taskTags)..where((x) => x.taskId.equals(taskId)))
          .watch()
          .map((rows) => rows.map((x) => x.tagId).toList());

  Stream<List<TaskAttachment>> watchAttachments(String taskId) =>
      (db.select(db.taskAttachments)
            ..where((x) => x.taskId.equals(taskId) & x.deletedAt.isNull())
            ..orderBy([(x) => OrderingTerm.desc(x.createdAt)]))
          .watch();

  Stream<Map<String, Set<String>>> watchTagIdsByTask() {
    return db.select(db.taskTags).watch().map((rows) {
      final result = <String, Set<String>>{};
      for (final row in rows) {
        result.putIfAbsent(row.taskId, () => <String>{}).add(row.tagId);
      }
      return result;
    });
  }

  Stream<Map<String, String>> watchSearchExtrasByTask() {
    final query = db.customSelect('''
      SELECT task_id, group_concat(value, ' ') AS searchable
      FROM (
        SELECT tt.task_id, tags.name AS value FROM task_tags tt
          JOIN tags ON tags.id = tt.tag_id WHERE tags.deleted_at IS NULL
        UNION ALL
        SELECT task_id, url AS value FROM task_attachments
          WHERE deleted_at IS NULL
      ) GROUP BY task_id
    ''', readsFrom: {db.taskTags, db.tags, db.taskAttachments});
    return query.watch().map((rows) => {
          for (final row in rows)
            row.read<String>('task_id'): row.read<String>('searchable'),
        });
  }

  Future<String> createTag(String name) async {
    final normalized = name.trim();
    final existing = await (db.select(db.tags)
          ..where((t) => t.name.lower().equals(normalized.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = _uuid.v4();
    await db.into(db.tags).insert(TagsCompanion.insert(
        id: id, userId: SupabaseConfig.activeUserId, name: normalized));
    return id;
  }

  Future<void> setTaskTag(String taskId, String tagId, bool selected) async {
    await db.transaction(() async {
      if (selected) {
        await db.into(db.taskTags).insert(
              TaskTagsCompanion.insert(taskId: taskId, tagId: tagId),
              mode: InsertMode.insertOrIgnore,
            );
      } else {
        await (db.delete(db.taskTags)
              ..where((x) => x.taskId.equals(taskId) & x.tagId.equals(tagId)))
            .go();
      }
      await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
        const TasksCompanion(syncState: Value('pending')),
      );
    });
  }

  Future<void> addAttachment(String taskId, String type, String url) async {
    await db.into(db.taskAttachments).insert(TaskAttachmentsCompanion.insert(
        id: _uuid.v4(), taskId: taskId, type: type, url: url.trim()));
  }

  Future<void> deleteAttachment(String id) async {
    await (db.update(db.taskAttachments)..where((x) => x.id.equals(id))).write(
      TaskAttachmentsCompanion(
        deletedAt: Value(DateTime.now()),
        syncState: const Value('pending'),
      ),
    );
  }

  Future<void> renameTag(String id, String name) async {
    await (db.update(db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(
          name: Value(name.trim()), syncState: const Value('pending')),
    );
  }

  Future<void> deleteTag(String id) async {
    await db.transaction(() async {
      await (db.delete(db.taskTags)..where((x) => x.tagId.equals(id))).go();
      await (db.update(db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
            deletedAt: Value(DateTime.now()),
            syncState: const Value('pending')),
      );
    });
  }
}
