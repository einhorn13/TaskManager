import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/core/db/database.dart';
import 'package:task_manager/features/tasks/data/task_repository.dart';
import 'package:task_manager/shared/data/folder_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(db);
  });

  tearDown(() => db.close());

  test('local task creation is persisted and added to durable outbox',
      () async {
    final taskId = await repository.addTask(title: 'Offline task');

    final task = await (db.select(db.tasks)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    final operations = await (db.select(db.syncOperations)
          ..where((row) => row.entityId.equals(taskId)))
        .get();

    expect(task.userId, 'local');
    expect(task.syncState, 'pending');
    expect(operations, hasLength(1));
    expect(operations.single.entityType, 'task');
    expect(operations.single.operation, 'upsert');
  });

  test('quick-create parameters are persisted together', () async {
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'folder-1', userId: 'local', name: 'Project'));
    final taskId = await repository.addTask(
      title: 'Planned task',
      folderId: 'folder-1',
      durationMinutes: 180,
      recurrenceRule: 'FREQ=WEEKLY',
      basePriority: 2,
      dueDate: DateTime(2026, 7, 20),
    );

    final task = await (db.select(db.tasks)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    expect(task.folderId, 'folder-1');
    expect(task.durationMinutes, 180);
    expect(task.recurrenceRule, 'FREQ=WEEKLY');
    expect(task.basePriority, 2);
  });

  test('new task inherits collaboration space from selected folder', () async {
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'shared-folder',
        userId: 'owner',
        name: 'Shared',
        spaceId: const Value('space-1')));

    final taskId = await repository.addTask(
        title: 'Collaborative task', folderId: 'shared-folder');
    final task = await (db.select(db.tasks)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();

    expect(task.folderId, 'shared-folder');
    expect(task.spaceId, 'space-1');
  });

  test('deleting a folder can keep and unlink its tasks', () async {
    final folders = FolderRepository(db);
    final folderId = await folders.createFolder('Keep tasks');
    final taskId =
        await repository.addTask(title: 'Survivor', folderId: folderId);

    await folders.deleteFolder(folderId);

    final task = await (db.select(db.tasks)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    final folder = await (db.select(db.folders)
          ..where((row) => row.id.equals(folderId)))
        .getSingle();
    expect(task.folderId, isNull);
    expect(task.deletedAt, isNull);
    expect(folder.deletedAt, isNotNull);
  });

  test('deleting a folder with tasks also deletes nested subtasks', () async {
    final folders = FolderRepository(db);
    final folderId = await folders.createFolder('Delete all');
    final parentId =
        await repository.addTask(title: 'Parent', folderId: folderId);
    await repository.addSubtask(parentId, 'Child');

    await folders.deleteFolder(folderId, mode: FolderDeletionMode.deleteTasks);

    final tasks = await db.select(db.tasks).get();
    expect(tasks, hasLength(2));
    expect(tasks.every((task) => task.deletedAt != null), isTrue);
  });

  test('moving a task updates its collaboration space from target folder',
      () async {
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'shared-folder',
        userId: 'owner',
        name: 'Shared',
        spaceId: const Value('space-1')));
    final taskId = await repository.addTask(title: 'Move me');

    await repository.updateTask(taskId, folderId: const Value('shared-folder'));
    expect((await repository.watchTask(taskId).first)?.spaceId, 'space-1');

    await repository.updateTask(taskId, folderId: const Value(null));
    expect((await repository.watchTask(taskId).first)?.spaceId, isNull);
  });

  test('subtask durations are aggregated separately from parent estimate',
      () async {
    final parentId =
        await repository.addTask(title: 'Parent', durationMinutes: 30);
    await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 'child-1',
        userId: 'local',
        parentTaskId: Value(parentId),
        title: 'Child one',
        durationMinutes: const Value(60)));
    await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 'child-2',
        userId: 'local',
        parentTaskId: Value(parentId),
        title: 'Child two',
        durationMinutes: const Value(90)));

    final totals = await repository.watchSubtaskDurations().first;
    expect(totals[parentId], (150, 2));
  });

  test('task deletion is soft and repository streams can restore it', () async {
    final taskId = await repository.addTask(title: 'Keep history');

    await repository.deleteTask(taskId);
    final deleted = await (db.select(db.tasks)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    expect(deleted.deletedAt, isNotNull);
    expect(await repository.watchTask(taskId).first, isNull);

    await repository.restoreTask(taskId);
    expect((await repository.watchTask(taskId).first)?.title, 'Keep history');
  });

  test('completing recurring task twice creates only one next task', () async {
    final taskId = await repository.addTask(
      title: 'Monthly report',
      dueDate: DateTime(2026, 1, 31, 18),
    );
    await repository.updateTask(
      taskId,
      recurrenceRule: const Value('FREQ=MONTHLY'),
    );

    await repository.toggleDone(taskId, true);
    await repository.toggleDone(taskId, true);

    final tasks = await db.select(db.tasks).get();
    final completed = tasks.singleWhere((task) => task.id == taskId);
    final next = tasks.singleWhere((task) => task.id != taskId);
    expect(completed.status, 'done');
    expect(next.status, 'todo');
    expect(next.dueDate, DateTime(2026, 2, 28, 18));
    expect(tasks, hasLength(2));
  });
}
