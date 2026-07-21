import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// Локальная SQLite БД — источник истины на клиенте (offline-first).
/// Синхронизация с Supabase реализуется отдельным слоем (features/sync, этап 1),
/// эта база работает независимо от наличия сети.
@DriftDatabase(
  tables: [
    Folders,
    Tags,
    TaskTags,
    Tasks,
    TaskAttachments,
    ChecklistTemplates,
    ChecklistTemplateItems,
    Checklists,
    ChecklistItems,
    SyncOperations,
    SyncMetadata,
  ],
)
class AppDatabase extends _$AppDatabase {
  static const currentSchemaVersion = 6;
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createOutboxTriggers();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(folders, folders.syncState);
            await m.addColumn(folders, folders.deletedAt);
            await m.addColumn(tags, tags.syncState);
            await m.addColumn(tags, tags.deletedAt);
            await m.addColumn(tasks, tasks.syncState);
            await m.addColumn(tasks, tasks.deletedAt);
            await m.addColumn(taskAttachments, taskAttachments.syncState);
            await m.addColumn(taskAttachments, taskAttachments.deletedAt);
            await m.addColumn(checklistTemplates, checklistTemplates.syncState);
            await m.addColumn(checklistTemplates, checklistTemplates.deletedAt);
            await m.addColumn(checklists, checklists.syncState);
            await m.addColumn(checklists, checklists.deletedAt);
            await m.addColumn(checklistItems, checklistItems.syncState);
            await m.addColumn(checklistItems, checklistItems.deletedAt);
            await m.createTable(syncOperations);
          }
          if (from < 3) {
            await m.addColumn(tasks, tasks.isPinned);
          }
          if (from < 4) {
            await m.createTable(syncMetadata);
          }
          if (from < 5) {
            await _createOutboxTriggers();
          }
          if (from < 6) {
            await m.addColumn(folders, folders.spaceId);
            await m.addColumn(tasks, tasks.spaceId);
            await m.addColumn(checklists, checklists.spaceId);
          }
        },
      );

  Future<void> _createOutboxTriggers() async {
    const entities = {
      'folders': 'folder',
      'tags': 'tag',
      'tasks': 'task',
      'task_attachments': 'attachment',
      'checklist_templates': 'checklistTemplate',
      'checklists': 'checklist',
      'checklist_items': 'checklistItem',
    };
    for (final entry in entities.entries) {
      await customStatement('DROP TRIGGER IF EXISTS ${entry.key}_sync_insert');
      await customStatement('DROP TRIGGER IF EXISTS ${entry.key}_sync_update');
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS ${entry.key}_sync_insert
        AFTER INSERT ON ${entry.key}
        WHEN NEW.sync_state = 'pending'
        BEGIN
          INSERT INTO sync_operations(entity_type, entity_id, operation, created_at)
          VALUES ('${entry.value}', NEW.id, 'upsert', unixepoch());
        END;
      ''');
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS ${entry.key}_sync_update
        AFTER UPDATE ON ${entry.key}
        WHEN NEW.sync_state = 'pending' AND OLD.sync_state <> 'pending'
        BEGIN
          INSERT INTO sync_operations(entity_type, entity_id, operation, created_at)
          VALUES ('${entry.value}', NEW.id, 'upsert', unixepoch());
        END;
      ''');
    }
  }

  /// Полностью очищает пользовательские данные и служебное состояние sync.
  /// Порядок учитывает внешние ключи: сначала дочерние таблицы.
  Future<void> clearAllLocalData() async {
    await transaction(() async {
      await delete(taskTags).go();
      await delete(taskAttachments).go();
      await delete(checklistItems).go();
      await delete(checklistTemplateItems).go();
      await delete(checklists).go();
      await delete(checklistTemplates).go();
      await delete(tasks).go();
      await delete(tags).go();
      await delete(folders).go();
      await delete(syncOperations).go();
      await delete(syncMetadata).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'task_manager.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
