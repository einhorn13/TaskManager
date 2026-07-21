import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers.dart';
import '../../../shared/data/folder_repository.dart';
import '../../filters/domain/filter_state.dart';
import '../data/task_repository.dart';
import '../data/task_extras_repository.dart';
import '../domain/task_priority.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(databaseProvider));
});

final taskExtrasRepositoryProvider = Provider<TaskExtrasRepository>(
    (ref) => TaskExtrasRepository(ref.watch(databaseProvider)));
final tagsProvider = StreamProvider<List<Tag>>(
    (ref) => ref.watch(taskExtrasRepositoryProvider).watchTags());
final taskTagIdsProvider = StreamProvider.family<List<String>, String>(
    (ref, id) => ref.watch(taskExtrasRepositoryProvider).watchTaskTagIds(id));
final taskAttachmentsProvider =
    StreamProvider.family<List<TaskAttachment>, String>((ref, id) =>
        ref.watch(taskExtrasRepositoryProvider).watchAttachments(id));
final tagIdsByTaskProvider = StreamProvider<Map<String, Set<String>>>(
    (ref) => ref.watch(taskExtrasRepositoryProvider).watchTagIdsByTask());
final searchExtrasByTaskProvider = StreamProvider<Map<String, String>>(
    (ref) => ref.watch(taskExtrasRepositoryProvider).watchSearchExtrasByTask());

final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  return FolderRepository(ref.watch(databaseProvider));
});

final foldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).watchAll();
});

final priorityEngineProvider = Provider<TaskPriorityEngine>((ref) {
  return const TaskPriorityEngine();
});

final taskFilterProvider = StateProvider<TaskFilter>((ref) {
  return const TaskFilter();
});

/// id задачи, открытой в панели деталей. null — панель закрыта.
final selectedTaskIdProvider = StateProvider<String?>((ref) => null);

final allTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllTasks();
});

/// Производный провайдер: сама задача, открытая в панели (или null).
/// Реагирует на изменения allTasksProvider, поэтому правки в панели сразу видно.
final taskByIdProvider = StreamProvider.family<Task?, String>(
    (ref, id) => ref.watch(taskRepositoryProvider).watchTask(id));

final selectedTaskProvider = Provider<Task?>((ref) {
  final id = ref.watch(selectedTaskIdProvider);
  if (id == null) return null;
  return ref.watch(taskByIdProvider(id)).value;
});

/// Подзадачи конкретной задачи — family по id родителя.
final subtasksForTaskProvider =
    StreamProvider.family<List<Task>, String>((ref, parentTaskId) {
  return ref.watch(taskRepositoryProvider).watchSubtasks(parentTaskId);
});

/// Один агрегированный поток для всех карточек вместо отдельной SQL-подписки
/// на каждую задачу.
final subtaskProgressByParentProvider =
    StreamProvider<Map<String, (int done, int total)>>((ref) {
  return ref.watch(taskRepositoryProvider).watchSubtaskProgress();
});

final subtaskDurationsByParentProvider =
    StreamProvider<Map<String, (int minutes, int count)>>((ref) {
  return ref.watch(taskRepositoryProvider).watchSubtaskDurations();
});

/// Применяет TaskFilter + сортирует по effective_priority.
/// Один провайдер отвечает и за фильтрацию, и за сортировку — добавление
/// нового смарт-фильтра не требует правок в других местах.
final filteredSortedTasksProvider = Provider<List<Task>>((ref) {
  final tasksAsync = ref.watch(allTasksProvider);
  final filter = ref.watch(taskFilterProvider);
  final engine = ref.watch(priorityEngineProvider);
  final tagIdsByTask = ref.watch(tagIdsByTaskProvider).value ?? const {};
  final searchExtras = ref.watch(searchExtrasByTaskProvider).value ?? const {};

  final tasks = tasksAsync.value ?? const [];
  final now = DateTime.now();

  bool matchesSmartFilter(Task t) {
    final effective = engine.effectivePriority(
      basePriority: t.basePriority,
      dueDate: t.dueDate,
      createdAt: t.createdAt,
      expiringThresholdOverrideDays: t.expiringThresholdDaysOverride,
      now: now,
    );

    switch (filter.smartFilter) {
      case SmartFilter.current:
        return true;
      case SmartFilter.today:
        return t.dueDate != null &&
            t.dueDate!.year == now.year &&
            t.dueDate!.month == now.month &&
            t.dueDate!.day == now.day;
      case SmartFilter.expiring:
        return effective == EffectivePriority.overdue ||
            (t.dueDate != null &&
                effective.index >= EffectivePriority.high.index);
      case SmartFilter.important:
        return effective == EffectivePriority.high ||
            effective == EffectivePriority.overdue;
      case SmartFilter.someday:
        return engine.isSomedayCandidate(
          basePriority: t.basePriority,
          dueDate: t.dueDate,
        );
      case SmartFilter.all:
        return true;
    }
  }

  bool matchesFolder(Task t) =>
      filter.folderId == null || t.folderId == filter.folderId;

  bool matchesTags(Task t) {
    if (filter.tagIds.isEmpty) return true;
    final assigned = tagIdsByTask[t.id] ?? const <String>{};
    return filter.tagIds.every(assigned.contains);
  }

  bool matchesSearch(Task t) {
    if (filter.searchText.isEmpty) return true;
    final needle = filter.searchText.toLowerCase();
    return t.title.toLowerCase().contains(needle) ||
        (t.description?.toLowerCase().contains(needle) ?? false) ||
        (searchExtras[t.id]?.toLowerCase().contains(needle) ?? false);
  }

  final filtered = tasks
      .where(matchesSmartFilter)
      .where(matchesFolder)
      .where(matchesTags)
      .where(matchesSearch)
      .toList();

  filtered.sort((a, b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    final pa = engine.effectivePriority(
      basePriority: a.basePriority,
      dueDate: a.dueDate,
      createdAt: a.createdAt,
      expiringThresholdOverrideDays: a.expiringThresholdDaysOverride,
      now: now,
    );
    final pb = engine.effectivePriority(
      basePriority: b.basePriority,
      dueDate: b.dueDate,
      createdAt: b.createdAt,
      expiringThresholdOverrideDays: b.expiringThresholdDaysOverride,
      now: now,
    );

    final priorityCompare = pb.index.compareTo(pa.index); // убывание важности
    if (priorityCompare != 0) return priorityCompare;

    if (a.dueDate == null && b.dueDate == null) return 0;
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!); // по возрастанию даты
  });

  return filtered;
});
