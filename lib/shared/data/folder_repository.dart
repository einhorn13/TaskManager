import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../core/notifications/task_notification_service.dart';
import '../../core/sync/supabase_config.dart';

const _uuid = Uuid();

enum FolderDeletionMode { keepTasks, deleteTasks }

/// Папки — общая таксономия (см. task_manager_plan.md, раздел 3), поэтому лежит
/// в shared/, а не внутри features/tasks — later checklists смогут переиспользовать.
class FolderRepository {
  final AppDatabase db;

  FolderRepository(this.db);

  Stream<List<Folder>> watchAll() {
    return (db.select(db.folders)..where((f) => f.deletedAt.isNull())).watch();
  }

  Future<void> updateFolder(String id, {String? name, String? color}) async {
    await (db.update(db.folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        color: color == null ? const Value.absent() : Value(color),
        syncState: const Value('pending'),
      ),
    );
  }

  Future<void> deleteFolder(
    String id, {
    FolderDeletionMode mode = FolderDeletionMode.keepTasks,
  }) async {
    final deletedTaskIds = <String>[];
    await db.transaction(() async {
      if (mode == FolderDeletionMode.keepTasks) {
        await (db.update(db.tasks)..where((t) => t.folderId.equals(id))).write(
            const TasksCompanion(
                folderId: Value(null), syncState: Value('pending')));
      } else {
        final tasks = await (db.select(db.tasks)
              ..where((task) => task.deletedAt.isNull()))
            .get();
        final ids = tasks
            .where((task) => task.folderId == id)
            .map((task) => task.id)
            .toSet();
        var foundDescendant = true;
        while (foundDescendant) {
          foundDescendant = false;
          for (final task in tasks) {
            if (task.parentTaskId != null &&
                ids.contains(task.parentTaskId) &&
                ids.add(task.id)) {
              foundDescendant = true;
            }
          }
        }
        deletedTaskIds.addAll(ids);
        if (ids.isNotEmpty) {
          await (db.update(db.tasks)..where((task) => task.id.isIn(ids))).write(
            TasksCompanion(
              deletedAt: Value(DateTime.now()),
              syncState: const Value('pending'),
            ),
          );
        }
      }
      await (db.update(db.folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
            deletedAt: Value(DateTime.now()),
            syncState: const Value('pending')),
      );
    });
    for (final taskId in deletedTaskIds) {
      await TaskNotificationService.instance.cancel(taskId);
    }
  }

  Future<String> createFolder(String name, {String? color}) async {
    final id = _uuid.v4();
    await db.into(db.folders).insert(
          FoldersCompanion.insert(
            id: id,
            userId: SupabaseConfig.activeUserId,
            name: name,
            color: color == null ? const Value.absent() : Value(color),
          ),
        );
    return id;
  }
}
