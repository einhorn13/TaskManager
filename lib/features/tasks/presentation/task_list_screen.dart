import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../../core/db/database.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/window/app_window_controller.dart';
import '../../../shared/widgets/quick_add_bar.dart';
import '../../../shared/widgets/dismissible_snack_bar.dart';
import '../../filters/domain/filter_state.dart';
import '../application/task_providers.dart';
import '../data/task_repository.dart';
import '../domain/task_priority.dart';
import 'widgets/task_detail_panel.dart';
import 'widgets/task_tile.dart';
import 'widgets/task_calendar_view.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  bool _mobileSheetScheduled = false;
  bool _completedExpanded = false;
  bool _calendarView = false;

  Future<void> _addTask(QuickAddParseResult parsed) async {
    final id = await ref.read(taskRepositoryProvider).addTask(
        title: parsed.title,
        dueDate: parsed.dueDate,
        basePriority: parsed.basePriority,
        folderId: parsed.folderId ?? ref.read(taskFilterProvider).folderId,
        durationMinutes: parsed.durationMinutes,
        recurrenceRule: parsed.recurrenceRule);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      showCloseIcon: true,
      content: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: messenger.hideCurrentSnackBar,
        child: Text(context.l10n.text('Task added', 'Задача добавлена')),
      ),
      action: SnackBarAction(
          label: context.l10n.text('Open', 'Открыть'),
          onPressed: () {
            messenger.hideCurrentSnackBar();
            ref.read(selectedTaskIdProvider.notifier).state = id;
          }),
    ));
  }

  Future<void> _deleteTask(Task task) async {
    await ref.read(taskRepositoryProvider).deleteTask(task.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      showCloseIcon: true,
      content: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: messenger.hideCurrentSnackBar,
        child: Text(context.l10n.text('Task deleted', 'Задача удалена')),
      ),
      action: SnackBarAction(
          label: context.l10n.text('Undo', 'Отменить'),
          onPressed: () {
            messenger.hideCurrentSnackBar();
            ref.read(taskRepositoryProvider).restoreTask(task.id);
          }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(taskFilterProvider);
    final tasks = ref.watch(filteredSortedTasksProvider);
    final calendarTasks = ref.watch(allTasksProvider).value ?? const <Task>[];
    final engine = ref.watch(priorityEngineProvider);
    final repo = ref.watch(taskRepositoryProvider);
    final selectedTask = ref.watch(selectedTaskProvider);
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];

    final listColumn = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    context.l10n.text(
                        '${MaterialLocalizations.of(context).formatMediumDate(DateTime.now())} · ${tasks.where((task) => task.status != 'done').length} active',
                        '${MaterialLocalizations.of(context).formatMediumDate(DateTime.now())} · ${tasks.where((task) => task.status != 'done').length} активных'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
              DynamicTaskBar(
                searchText: filter.searchText,
                folders: folders,
                initialFolderId: filter.folderId,
                onSubmit: _addTask,
                onSearch: (value) => ref
                    .read(taskFilterProvider.notifier)
                    .update((s) => s.copyWith(searchText: value.trim())),
              ),
              Consumer(builder: (context, ref, _) {
                final tags = ref.watch(tagsProvider).value ?? const [];
                if (tags.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    children: tags
                        .map((tag) => FilterChip(
                              label: Text('#${tag.name}'),
                              selected: filter.tagIds.contains(tag.id),
                              onSelected: (selected) {
                                final ids = {...filter.tagIds};
                                selected ? ids.add(tag.id) : ids.remove(tag.id);
                                ref
                                    .read(taskFilterProvider.notifier)
                                    .update((s) => s.copyWith(tagIds: ids));
                              },
                            ))
                        .toList(),
                  ),
                );
              }),
              Consumer(builder: (context, ref, _) {
                final folders = ref.watch(foldersProvider).value ?? const [];
                final tags = ref.watch(tagsProvider).value ?? const [];
                final activeTags =
                    tags.where((tag) => filter.tagIds.contains(tag.id));
                final folder =
                    folders.where((item) => item.id == filter.folderId);
                if (filter.folderId == null &&
                    filter.tagIds.isEmpty &&
                    filter.searchText.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (folder.isNotEmpty)
                            InputChip(
                                avatar:
                                    const Icon(Icons.folder_outlined, size: 16),
                                label: Text(folder.first.name),
                                onDeleted: () => ref
                                    .read(taskFilterProvider.notifier)
                                    .update((state) =>
                                        state.copyWith(folderId: null))),
                          ...activeTags.map((tag) => InputChip(
                              avatar: const Icon(Icons.tag, size: 16),
                              label: Text(tag.name),
                              onDeleted: () {
                                final ids = {...filter.tagIds}..remove(tag.id);
                                ref.read(taskFilterProvider.notifier).update(
                                    (state) => state.copyWith(tagIds: ids));
                              })),
                          if (filter.searchText.isNotEmpty)
                            InputChip(
                                avatar: const Icon(Icons.search, size: 16),
                                label: Text('«${filter.searchText}»'),
                                onDeleted: () => ref
                                    .read(taskFilterProvider.notifier)
                                    .update((state) =>
                                        state.copyWith(searchText: ''))),
                          TextButton.icon(
                              icon: const Icon(Icons.filter_alt_off, size: 17),
                              label: Text(context.l10n
                                  .text('Clear all', 'Сбросить всё')),
                              onPressed: () => ref
                                      .read(taskFilterProvider.notifier)
                                      .state =
                                  TaskFilter(smartFilter: filter.smartFilter)),
                        ],
                      )),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: _calendarView
              ? TaskCalendarView(
                  tasks: calendarTasks,
                  onTaskTap: (task) =>
                      ref.read(selectedTaskIdProvider.notifier).state = task.id,
                )
              : _buildTaskList(context, tasks, engine, repo, filter),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_viewTitle(filter)),
        actions: [
          if (AppWindowController.instance.isSupported)
            IconButton(
              tooltip: context.l10n.text('Compact view', 'Компактный вид'),
              icon: const Icon(Icons.view_compact_alt_outlined),
              onPressed: AppWindowController.instance.enterCompactMode,
            ),
          IconButton(
            tooltip: _calendarView
                ? context.l10n.text('Show list', 'Показать списком')
                : context.l10n.text('Show calendar', 'Показать календарём'),
            icon: Icon(_calendarView ? Icons.view_list : Icons.calendar_month),
            onPressed: () => setState(() => _calendarView = !_calendarView),
          ),
          PopupMenuButton<SmartFilter>(
            tooltip: context.l10n.text('View', 'Представление'),
            icon: const Icon(Icons.filter_list),
            onSelected: (value) => ref.read(taskFilterProvider.notifier).update(
                (state) => state.copyWith(smartFilter: value, folderId: null)),
            itemBuilder: (_) => SmartFilter.values
                .map((value) => PopupMenuItem(
                    value: value, child: Text(_filterLabel(value))))
                .toList(),
          )
        ],
      ),
      // На узких экранах (Android) панель деталей открывается поверх списка
      // модальным bottom sheet — см. ветку else. Порог 700px — грубая эвристика,
      // при необходимости вынесем в константу/тему.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;

          if (selectedTask != null && isWide) {
            return Row(
              children: [
                Expanded(child: listColumn),
                TaskDetailPanel(
                  key: ValueKey(selectedTask.id),
                  task: selectedTask,
                ),
              ],
            );
          }

          if (selectedTask != null && !isWide && !_mobileSheetScheduled) {
            _mobileSheetScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.of(context).size.height * 0.85,
                  child: TaskDetailPanel(
                    key: ValueKey(selectedTask.id),
                    task: selectedTask,
                  ),
                ),
              ).then((_) {
                _mobileSheetScheduled = false;
                ref.read(selectedTaskIdProvider.notifier).state = null;
              });
            });
          }

          return listColumn;
        },
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, List<Task> tasks,
      TaskPriorityEngine engine, TaskRepository repo, TaskFilter filter) {
    final active = tasks.where((t) => t.status != 'done').toList();
    final completed = tasks.where((t) => t.status == 'done').toList();
    if (active.isEmpty && completed.isEmpty) {
      final text = filter.smartFilter == SmartFilter.today
          ? context.l10n.text('Nothing due today — take a breath',
              'Задач на сегодня нет — можно выдохнуть')
          : context.l10n.text('No tasks match the selected filters',
              'По выбранным фильтрам задач нет');
      return Center(child: Text(text));
    }
    final children = <Widget>[];
    if (filter.smartFilter == SmartFilter.current) {
      final now = DateTime.now();
      final sections = <String, List<Task>>{
        context.l10n.text('Overdue', 'Просрочено'): [],
        context.l10n.text('Today', 'Сегодня'): [],
        context.l10n.text('Upcoming', 'Скоро'): [],
        context.l10n.text('Important', 'Важное'): [],
        context.l10n.text('Other', 'Остальные'): [],
      };
      for (final task in active) {
        final due = task.dueDate;
        final priority = engine.effectivePriority(
            basePriority: task.basePriority,
            dueDate: due,
            createdAt: task.createdAt,
            expiringThresholdOverrideDays: task.expiringThresholdDaysOverride);
        if (due != null && due.isBefore(now)) {
          sections[context.l10n.text('Overdue', 'Просрочено')]!.add(task);
        } else if (due != null && _sameDay(due, now)) {
          sections[context.l10n.text('Today', 'Сегодня')]!.add(task);
        } else if (due != null &&
            due.isBefore(now.add(const Duration(days: 4)))) {
          sections[context.l10n.text('Upcoming', 'Скоро')]!.add(task);
        } else if (priority == EffectivePriority.high || task.isPinned) {
          sections[context.l10n.text('Important', 'Важное')]!.add(task);
        } else {
          sections[context.l10n.text('Other', 'Остальные')]!.add(task);
        }
      }
      for (final entry in sections.entries) {
        if (entry.value.isEmpty) continue;
        children.add(Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('task-section-${entry.key}'),
            initiallyExpanded: true,
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            tilePadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            childrenPadding: EdgeInsets.zero,
            title: Text('${entry.key} · ${entry.value.length}',
                style: Theme.of(context).textTheme.titleSmall),
            children:
                entry.value.map((t) => _taskTile(t, engine, repo)).toList(),
          ),
        ));
      }
    } else {
      children.addAll(active.map((t) => _taskTile(t, engine, repo)));
    }
    if (completed.isNotEmpty) {
      children.add(ExpansionTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        initiallyExpanded: _completedExpanded,
        onExpansionChanged: (value) => _completedExpanded = value,
        title: Text(context.l10n.text('Completed (${completed.length})',
            'Выполненные (${completed.length})')),
        children: completed.map((t) => _taskTile(t, engine, repo)).toList(),
      ));
    }
    return ListView(children: children);
  }

  Widget _taskTile(Task task, TaskPriorityEngine engine, TaskRepository repo) {
    final effective = engine.effectivePriority(
        basePriority: task.basePriority,
        dueDate: task.dueDate,
        createdAt: task.createdAt,
        expiringThresholdOverrideDays: task.expiringThresholdDaysOverride);
    return TaskTile(
      task: task,
      effectivePriority: effective,
      onToggleDone: (done) => repo.toggleDone(task.id, done),
      onTap: () => ref.read(selectedTaskIdProvider.notifier).state = task.id,
      onPostpone: () => repo.postponeToTomorrow(task.id),
      onDelete: () => _deleteTask(task),
      onPin: () => repo.setPinned(task.id, !task.isPinned),
      onDuplicate: () async {
        await repo.duplicateTask(task.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
              context,
              content: Text(context.l10n
                  .text('Task copy created', 'Копия задачи создана'))));
        }
      },
      onConvertToChecklist: () async {
        await repo.convertToChecklist(task.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
              context,
              content: Text(context.l10n
                  .text('List created from task', 'Список создан из задачи'))));
        }
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _viewTitle(TaskFilter filter) {
    if (filter.folderId != null) {
      final folders = ref.watch(foldersProvider).value ?? const [];
      for (final folder in folders) {
        if (folder.id == filter.folderId) return folder.name;
      }
    }
    return _filterLabel(filter.smartFilter);
  }

  String _filterLabel(SmartFilter value) => switch (value) {
        SmartFilter.current => context.l10n.text('Current', 'Актуальные'),
        SmartFilter.today => context.l10n.text('Today', 'Сегодня'),
        SmartFilter.expiring => context.l10n.text('Expiring', 'Истекающие'),
        SmartFilter.important => context.l10n.text('Important', 'Важные'),
        SmartFilter.someday => context.l10n.text('Someday', 'Когда-нибудь'),
        SmartFilter.all => context.l10n.text('All tasks', 'Все задачи'),
      };
}
