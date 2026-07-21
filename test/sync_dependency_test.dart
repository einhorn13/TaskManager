import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/core/db/database.dart';
import 'package:task_manager/core/providers.dart';
import 'package:task_manager/core/sync/sync_engine.dart';
import 'package:task_manager/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late SyncEngine engine;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    engine = container.read(syncEngineProvider);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('task push includes its folder before the task', () async {
    await database.into(database.folders).insert(FoldersCompanion.insert(
        id: 'folder-1', userId: 'user-1', name: 'Work'));
    await database.into(database.tasks).insert(TasksCompanion.insert(
        id: 'task-1',
        userId: 'user-1',
        folderId: const Value('folder-1'),
        title: 'Report'));

    final taskOutbox = await (database.select(database.syncOperations)
          ..where((row) => row.entityType.equals('task')))
        .getSingle();
    final plan = await engine.buildPushPlan([taskOutbox]);

    expect(
        plan.map((operation) => operation.entityType.name), ['folder', 'task']);
    expect(plan.last.payload['folder_id'], 'folder-1');
  });

  test('nested task and attachment dependencies are topologically ordered',
      () async {
    await database.into(database.tasks).insert(
        TasksCompanion.insert(id: 'parent', userId: 'user-1', title: 'Parent'));
    await database.into(database.tasks).insert(TasksCompanion.insert(
        id: 'child',
        userId: 'user-1',
        parentTaskId: const Value('parent'),
        title: 'Child'));
    await database.into(database.taskAttachments).insert(
        TaskAttachmentsCompanion.insert(
            id: 'attachment',
            taskId: 'child',
            type: 'link',
            url: 'https://example.com'));

    final outbox = await (database.select(database.syncOperations)
          ..where((row) => row.entityType.equals('attachment')))
        .getSingle();
    final plan = await engine.buildPushPlan([outbox]);

    expect(plan.map((operation) => operation.entityId),
        ['parent', 'child', 'attachment']);
  });

  test('cross-account optional references are not uploaded', () async {
    await database.into(database.folders).insert(FoldersCompanion.insert(
        id: 'foreign-folder', userId: 'user-a', name: 'Private'));
    await database.into(database.tasks).insert(TasksCompanion.insert(
        id: 'task-b',
        userId: 'user-b',
        folderId: const Value('foreign-folder'),
        title: 'Task'));
    final outbox = await (database.select(database.syncOperations)
          ..where((row) => row.entityType.equals('task')))
        .getSingle();

    final plan = await engine.buildPushPlan([outbox]);

    expect(plan.map((operation) => operation.entityId), ['task-b']);
    expect(plan.single.payload['folder_id'], equals(null));
  });

  test('shared folder owned by another user remains a task dependency',
      () async {
    await database.into(database.folders).insert(FoldersCompanion.insert(
        id: 'shared-folder',
        userId: 'owner',
        name: 'Shared',
        spaceId: const Value('space-1')));
    await database.into(database.tasks).insert(TasksCompanion.insert(
        id: 'member-task',
        userId: 'member',
        spaceId: const Value('space-1'),
        folderId: const Value('shared-folder'),
        title: 'Member task'));
    final outbox = await (database.select(database.syncOperations)
          ..where((row) => row.entityType.equals('task')))
        .getSingle();

    final plan = await engine.buildPushPlan([outbox]);

    expect(plan.map((operation) => operation.entityId),
        ['shared-folder', 'member-task']);
    expect(plan.last.payload['space_id'], 'space-1');
    expect(plan.last.payload['folder_id'], 'shared-folder');
  });

  test('completing another users shared task preserves shared fields',
      () async {
    await database.into(database.tags).insert(TagsCompanion.insert(
        id: 'owner-tag',
        userId: 'owner',
        name: 'Shared tag',
        syncState: const Value('synced')));
    await database.into(database.tasks).insert(TasksCompanion.insert(
        id: 'shared-task',
        userId: 'owner',
        spaceId: const Value('space-1'),
        title: 'Shared task',
        syncState: const Value('synced')));
    await database.into(database.taskTags).insert(
        TaskTagsCompanion.insert(taskId: 'shared-task', tagId: 'owner-tag'));

    await TaskRepository(database).toggleDone('shared-task', true);

    final outbox = await (database.select(database.syncOperations)
          ..where((row) => row.entityId.equals('shared-task')))
        .getSingle();
    final plan = await engine.buildPushPlan([outbox]);
    final task = plan.single;

    expect(task.payload['user_id'], 'owner');
    expect(task.payload['space_id'], 'space-1');
    expect(task.payload['status'], 'done');
    expect(task.payload['completed_at'], isNot(equals(null)));
    expect(task.payload['tag_ids'], ['owner-tag']);
  });

  test('pulled child tasks are applied after their parents', () {
    final ordered = engine.orderPulledChanges([
      {'_entity_type': 'task', 'id': 'child', 'parent_task_id': 'parent'},
      {'_entity_type': 'task', 'id': 'parent', 'parent_task_id': null},
      {'_entity_type': 'folder', 'id': 'folder'},
    ]);

    expect(ordered.map((row) => row['id']), ['folder', 'parent', 'child']);
  });
}
