import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/database.dart';
import '../../../core/notifications/task_notification_service.dart';
import '../../../core/sync/supabase_config.dart';
import '../domain/recurrence.dart';

const _uuid = Uuid();

class TaskRepository {
  final AppDatabase db;

  TaskRepository(this.db);

  Future<void> _refreshNotification(String taskId) async {
    final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    if (task == null || task.deletedAt != null || task.status == 'done') {
      await TaskNotificationService.instance.cancel(taskId);
    } else {
      await TaskNotificationService.instance.schedule(task);
    }
  }

  /// Живой поток задач верхнего уровня (без подзадач — те показываются только
  /// внутри панели деталей родителя, см. watchSubtasks).
  Stream<List<Task>> watchAllTasks() {
    return (db.select(db.tasks)
          ..where((t) =>
              t.parentTaskId.isNull() &
              t.deletedAt.isNull() &
              (t.status.equals('todo') | t.completedAt.isNotNull())))
        .watch();
  }

  Stream<Task?> watchTask(String taskId) {
    return (db.select(db.tasks)
          ..where((t) => t.id.equals(taskId) & t.deletedAt.isNull()))
        .watchSingleOrNull();
  }

  /// Подзадачи конкретной задачи — плоские (без вложенности второго уровня по
  /// конвенции, хотя схема технически это не запрещает).
  Stream<List<Task>> watchSubtasks(String parentTaskId) {
    return (db.select(db.tasks)
          ..where(
              (t) => t.parentTaskId.equals(parentTaskId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Stream<Map<String, (int done, int total)>> watchSubtaskProgress() {
    final query = db.customSelect('''
      SELECT parent_task_id,
             SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) AS done_count,
             COUNT(*) AS total_count
      FROM tasks
      WHERE parent_task_id IS NOT NULL AND deleted_at IS NULL
      GROUP BY parent_task_id
    ''', readsFrom: {db.tasks});
    return query.watch().map((rows) => {
          for (final row in rows)
            row.read<String>('parent_task_id'): (
              row.read<int>('done_count'),
              row.read<int>('total_count'),
            ),
        });
  }

  Stream<Map<String, (int minutes, int count)>> watchSubtaskDurations() {
    final query = db.customSelect('''
      SELECT parent_task_id,
             SUM(duration_minutes) AS total_minutes,
             COUNT(duration_minutes) AS estimated_count
      FROM tasks
      WHERE parent_task_id IS NOT NULL
        AND deleted_at IS NULL
        AND duration_minutes IS NOT NULL
      GROUP BY parent_task_id
    ''', readsFrom: {db.tasks});
    return query.watch().map((rows) => {
          for (final row in rows)
            row.read<String>('parent_task_id'): (
              row.read<int>('total_minutes'),
              row.read<int>('estimated_count'),
            ),
        });
  }

  Future<void> addSubtask(String parentTaskId, String title) async {
    final parent = await (db.select(db.tasks)
          ..where((t) => t.id.equals(parentTaskId)))
        .getSingle();
    final existing = await (db.select(db.tasks)
          ..where((t) =>
              t.parentTaskId.equals(parentTaskId) & t.deletedAt.isNull()))
        .get();
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: _uuid.v4(),
            userId: SupabaseConfig.activeUserId,
            parentTaskId: Value(parentTaskId),
            spaceId: Value(parent.spaceId),
            title: title,
            position: Value(existing.length.toDouble()),
          ),
        );
  }

  Future<void> moveSubtask(
      String parentTaskId, String taskId, int delta) async {
    final items = await (db.select(db.tasks)
          ..where(
              (t) => t.parentTaskId.equals(parentTaskId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.createdAt)
          ]))
        .get();
    final index = items.indexWhere((item) => item.id == taskId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= items.length) return;
    await db.transaction(() async {
      await (db.update(db.tasks)..where((t) => t.id.equals(items[index].id)))
          .write(TasksCompanion(
              position: Value(target.toDouble()),
              syncState: const Value('pending')));
      await (db.update(db.tasks)..where((t) => t.id.equals(items[target].id)))
          .write(TasksCompanion(
              position: Value(index.toDouble()),
              syncState: const Value('pending')));
    });
  }

  Future<String> addTask({
    required String title,
    DateTime? dueDate,
    int basePriority = 1,
    String? folderId,
    int? durationMinutes,
    String? recurrenceRule,
  }) async {
    final id = _uuid.v4();
    final folder = folderId == null
        ? null
        : await (db.select(db.folders)..where((f) => f.id.equals(folderId)))
            .getSingleOrNull();
    await db.into(db.tasks).insert(
          TasksCompanion.insert(
            id: id,
            userId: SupabaseConfig.activeUserId,
            title: title,
            dueDate: Value(dueDate),
            basePriority: Value(basePriority),
            folderId: Value(folderId),
            spaceId: Value(folder?.spaceId),
            durationMinutes: Value(durationMinutes),
            recurrenceRule: Value(recurrenceRule),
          ),
        );
    await _refreshNotification(id);
    return id;
  }

  /// При отметке "выполнено" у повторяющейся задачи (recurrenceRule заполнен)
  /// автоматически создаётся следующий экземпляр с новым сроком — сама задача
  /// при этом тоже помечается выполненной (история не теряется, см. план,
  /// раздел "Заложено в архитектуру" — повторяющиеся задачи).
  Future<void> toggleDone(String taskId, bool done) async {
    String? createdRecurringId;
    await db.transaction(() async {
      final task = await (db.select(db.tasks)
            ..where((t) => t.id.equals(taskId)))
          .getSingle();
      if ((task.status == 'done') == done) return;
      await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(
          status: Value(done ? 'done' : 'todo'),
          completedAt: Value(done ? DateTime.now() : null),
          updatedAt: Value(DateTime.now()),
          syncState: const Value('pending'),
        ),
      );
      if (!done || task.recurrenceRule == null) return;
      final nextDue = RecurrenceRule.nextDueDate(
          rule: task.recurrenceRule, anchor: task.dueDate);
      createdRecurringId = _uuid.v4();
      await db.into(db.tasks).insert(
            TasksCompanion.insert(
              id: createdRecurringId!,
              userId: task.userId,
              folderId: Value(task.folderId),
              spaceId: Value(task.spaceId),
              title: task.title,
              description: Value(task.description),
              dueDate: Value(nextDue),
              basePriority: Value(task.basePriority),
              recurrenceRule: Value(task.recurrenceRule),
              durationMinutes: Value(task.durationMinutes),
            ),
          );
    });
    await _refreshNotification(taskId);
    if (createdRecurringId != null) {
      await _refreshNotification(createdRecurringId!);
    }
  }

  /// Полное редактирование задачи из панели деталей. Используются drift Value<>,
  /// чтобы явно различать "поле не трогаем" (Value.absent()) и "ставим null"
  /// (Value(null)) — например, чтобы можно было очистить срок или папку.
  Future<void> updateTask(
    String taskId, {
    Value<String> title = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    Value<int> basePriority = const Value.absent(),
    Value<String?> folderId = const Value.absent(),
    Value<int?> expiringThresholdOverrideDays = const Value.absent(),
    Value<int?> durationMinutes = const Value.absent(),
    Value<String?> recurrenceRule = const Value.absent(),
  }) async {
    Value<String?> spaceId = const Value.absent();
    if (folderId.present) {
      final targetFolder = folderId.value == null
          ? null
          : await (db.select(db.folders)
                ..where((folder) => folder.id.equals(folderId.value!)))
              .getSingleOrNull();
      spaceId = Value(targetFolder?.spaceId);
    }
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        title: title,
        description: description,
        dueDate: dueDate,
        basePriority: basePriority,
        folderId: folderId,
        spaceId: spaceId,
        expiringThresholdDaysOverride: expiringThresholdOverrideDays,
        durationMinutes: durationMinutes,
        recurrenceRule: recurrenceRule,
        updatedAt: Value(DateTime.now()),
        syncState: const Value('pending'),
      ),
    );
    await _refreshNotification(taskId);
  }

  Future<void> deleteTask(String taskId) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
          deletedAt: Value(DateTime.now()), syncState: const Value('pending')),
    );
    await TaskNotificationService.instance.cancel(taskId);
  }

  Future<void> restoreTask(String taskId) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      const TasksCompanion(deletedAt: Value(null), syncState: Value('pending')),
    );
    await _refreshNotification(taskId);
  }

  Future<void> setPinned(String taskId, bool pinned) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
          isPinned: Value(pinned),
          updatedAt: Value(DateTime.now()),
          syncState: const Value('pending')),
    );
  }

  Future<String> duplicateTask(String taskId) async {
    final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingle();
    final id = _uuid.v4();
    await db.into(db.tasks).insert(TasksCompanion.insert(
          id: id,
          userId: SupabaseConfig.activeUserId,
          folderId: Value(task.folderId),
          spaceId: Value(task.spaceId),
          title: '${task.title} — копия',
          description: Value(task.description),
          dueDate: Value(task.dueDate),
          basePriority: Value(task.basePriority),
          durationMinutes: Value(task.durationMinutes),
          recurrenceRule: Value(task.recurrenceRule),
        ));
    await _refreshNotification(id);
    return id;
  }

  Future<String> convertToChecklist(String taskId) async {
    final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingle();
    final checklistId = _uuid.v4();
    await db.transaction(() async {
      await db.into(db.checklists).insert(ChecklistsCompanion.insert(
          id: checklistId,
          userId: SupabaseConfig.activeUserId,
          title: task.title));
      final subtasks = await (db.select(db.tasks)
            ..where(
                (t) => t.parentTaskId.equals(taskId) & t.deletedAt.isNull()))
          .get();
      for (var i = 0; i < subtasks.length; i++) {
        await db.into(db.checklistItems).insert(ChecklistItemsCompanion.insert(
              id: _uuid.v4(),
              checklistId: checklistId,
              text_: subtasks[i].title,
              isDone: Value(subtasks[i].status == 'done'),
              position: Value(i.toDouble()),
            ));
      }
    });
    return checklistId;
  }

  /// "Отложить на 1 клик" — сдвигает срок на следующий день, не трогая остальные
  /// поля. Не требует новых колонок, snoozeCount инкрементируется для статистики.
  Future<void> postponeToTomorrow(String taskId) async {
    final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId)))
        .getSingle();
    final base = task.dueDate ?? DateTime.now();
    final nextDay =
        DateTime(base.year, base.month, base.day + 1, base.hour, base.minute);

    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        dueDate: Value(nextDay),
        snoozeCount: Value(task.snoozeCount + 1),
        updatedAt: Value(DateTime.now()),
        syncState: const Value('pending'),
      ),
    );
    await _refreshNotification(taskId);
  }
}
