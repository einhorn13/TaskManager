import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Value;

import '../../../../core/db/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/settings/ui_settings.dart';
import '../../../../shared/widgets/duration_input_dialog.dart';
import '../../application/task_providers.dart';
import '../../domain/task_priority.dart';

class TaskTile extends ConsumerWidget {
  final Task task;
  final EffectivePriority effectivePriority;
  final ValueChanged<bool> onToggleDone;
  final VoidCallback onTap;
  final VoidCallback onPostpone;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onDuplicate;
  final VoidCallback onConvertToChecklist;

  const TaskTile({
    super.key,
    required this.task,
    required this.effectivePriority,
    required this.onToggleDone,
    required this.onTap,
    required this.onPostpone,
    required this.onDelete,
    required this.onPin,
    required this.onDuplicate,
    required this.onConvertToChecklist,
  });

  Color get _color {
    switch (effectivePriority) {
      case EffectivePriority.low:
        return PriorityColors.low;
      case EffectivePriority.medium:
        return PriorityColors.medium;
      case EffectivePriority.high:
        return PriorityColors.high;
      case EffectivePriority.overdue:
        return PriorityColors.overdue;
    }
  }

  String? get _dueLabel {
    if (task.dueDate == null) return null;
    return DateFormat('d MMM, HH:mm', 'ru').format(task.dueDate!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = task.status == 'done';
    final progress =
        ref.watch(subtaskProgressByParentProvider).value?[task.id] ?? (0, 0);
    final subtaskDuration =
        ref.watch(subtaskDurationsByParentProvider).value?[task.id] ?? (0, 0);
    final selected = ref.watch(selectedTaskIdProvider) == task.id;
    final density = ref.watch(uiSettingsProvider).listDensity;
    final verticalPadding = switch (density) {
      ListDensity.compact => 0.0,
      ListDensity.normal => 0.0,
      ListDensity.comfortable => 5.0,
    };

    return Dismissible(
      key: ValueKey(task.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Icon(Icons.schedule),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          onPostpone();
          return false; // не удаляем, просто отложили
        }
        return true;
      },
      onDismissed: (_) => onDelete(),
      child: _HoverSurface(
        selected: selected,
        accent: _color,
        onOpen: onTap,
        onPin: onPin,
        onPostpone: onPostpone,
        onDuplicate: onDuplicate,
        onConvert: onConvertToChecklist,
        onDelete: onDelete,
        density: density,
        hoverActions: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: 'Отложить на завтра',
              icon: const Icon(Icons.schedule, size: 18),
              onPressed: onPostpone),
          IconButton(
              tooltip: task.isPinned ? 'Открепить' : 'Закрепить',
              icon: Icon(
                  task.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18),
              onPressed: onPin),
          IconButton(
              tooltip: 'Изменить подзадачи',
              icon: const Icon(Icons.checklist, size: 18),
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _SubtaskQuickEditor(parent: task))),
          PopupMenuButton<String>(
            tooltip: 'Другие действия',
            onSelected: (value) {
              switch (value) {
                case 'duplicate':
                  onDuplicate();
                case 'convert':
                  onConvertToChecklist();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
              PopupMenuItem(
                  value: 'convert', child: Text('Преобразовать в список')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
          Tooltip(
            message: 'Перетащить задачу',
            child: Draggable<Task>(
              data: task,
              feedback: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                    padding: const EdgeInsets.all(12), child: Text(task.title)),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_indicator, size: 18),
              ),
            ),
          ),
        ]),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            minVerticalPadding: verticalPadding,
            visualDensity: switch (density) {
              ListDensity.compact => const VisualDensity(vertical: -3),
              ListDensity.normal => const VisualDensity(vertical: -1),
              ListDensity.comfortable => VisualDensity.standard,
            },
            contentPadding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
            onTap: onTap,
            leading: Tooltip(
              message:
                  done ? 'Вернуть задачу в работу' : 'Отметить выполненной',
              child: Checkbox(
                value: done,
                onChanged: (v) => onToggleDone(v ?? false),
              ),
            ),
            title: Text(
              task.title,
              style: done
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            subtitle: Row(
              children: [
                if (task.spaceId != null) ...[
                  const Tooltip(
                    message: 'Общая задача',
                    child: Icon(Icons.group_outlined, size: 13),
                  ),
                  const SizedBox(width: 4),
                ],
                if (task.recurrenceRule != null) ...[
                  const Tooltip(
                    message: 'Повторяющаяся задача',
                    child: Icon(Icons.repeat, size: 13),
                  ),
                  const SizedBox(width: 4),
                ],
                if (task.durationMinutes != null) ...[
                  Tooltip(
                    message: 'Оценка длительности',
                    child: Text('~${task.durationMinutes} мин',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const SizedBox(width: 8),
                ],
                if (subtaskDuration.$2 > 0) ...[
                  Tooltip(
                    message: 'Суммарная длительность подзадач',
                    child: Text(
                      'Σ ${formatTaskDuration(context, subtaskDuration.$1)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (progress.$2 > 0)
                  Tooltip(
                    message: 'Нажмите, чтобы быстро изменить подзадачи',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => _SubtaskQuickEditor(parent: task),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.checklist, size: 13),
                          const SizedBox(width: 4),
                          Text('${progress.$1}/${progress.$2}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_dueLabel != null) ...[
                  Tooltip(
                    message: 'Срок выполнения',
                    child: Text(_dueLabel!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const SizedBox(width: 8),
                ],
                if (task.isPinned) ...[
                  Tooltip(
                    message: 'Задача закреплена',
                    child: Icon(Icons.push_pin_outlined,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 6),
                ],
                PopupMenuButton<int>(
                  tooltip:
                      'Приоритет задачи (${_basePriorityLabel(task.basePriority)})',
                  padding: const EdgeInsets.all(8),
                  onSelected: (value) => ref
                      .read(taskRepositoryProvider)
                      .updateTask(task.id, basePriority: Value(value)),
                  itemBuilder: (_) => [
                    for (final value in [0, 1, 2])
                      PopupMenuItem(
                        value: value,
                        child: Row(children: [
                          SizedBox(
                              width: 24,
                              child: value == task.basePriority
                                  ? const Icon(Icons.check, size: 18)
                                  : null),
                          Text('${_basePriorityLabel(value)} приоритет'),
                        ]),
                      ),
                  ],
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: _color, shape: BoxShape.circle),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Действия',
                  onSelected: (value) {
                    switch (value) {
                      case 'subtasks':
                        showDialog<void>(
                          context: context,
                          builder: (_) => _SubtaskQuickEditor(parent: task),
                        );
                      case 'pin':
                        onPin();
                      case 'postpone':
                        onPostpone();
                      case 'duplicate':
                        onDuplicate();
                      case 'convert':
                        onConvertToChecklist();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'subtasks', child: Text('Изменить подзадачи')),
                    PopupMenuItem(
                        value: 'pin',
                        child: Text(task.isPinned ? 'Открепить' : 'Закрепить')),
                    const PopupMenuItem(
                        value: 'postpone', child: Text('Отложить на завтра')),
                    const PopupMenuItem(
                        value: 'duplicate', child: Text('Дублировать')),
                    const PopupMenuItem(
                        value: 'convert',
                        child: Text('Преобразовать в список')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                        value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _basePriorityLabel(int value) => switch (value) {
        0 => 'низкий',
        2 => 'высокий',
        _ => 'средний',
      };
}

class _SubtaskQuickEditor extends ConsumerStatefulWidget {
  final Task parent;
  const _SubtaskQuickEditor({required this.parent});

  @override
  ConsumerState<_SubtaskQuickEditor> createState() =>
      _SubtaskQuickEditorState();
}

class _SubtaskQuickEditorState extends ConsumerState<_SubtaskQuickEditor> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  final Map<String, Timer> _saveTimers = {};
  final Map<String, String> _pendingTitles = {};

  void _scheduleTitleSave(Task subtask, String raw) {
    final title = raw.trim();
    _saveTimers[subtask.id]?.cancel();
    if (title.isEmpty || title == subtask.title) {
      _pendingTitles.remove(subtask.id);
      return;
    }
    _pendingTitles[subtask.id] = title;
    _saveTimers[subtask.id] = Timer(const Duration(milliseconds: 500), () {
      ref
          .read(taskRepositoryProvider)
          .updateTask(subtask.id, title: Value(title));
      _pendingTitles.remove(subtask.id);
    });
  }

  Future<void> _add() async {
    final title = _addController.text.trim();
    if (title.isEmpty) return;
    await ref.read(taskRepositoryProvider).addSubtask(widget.parent.id, title);
    _addController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final subtasks =
        ref.watch(subtasksForTaskProvider(widget.parent.id)).value ?? const [];
    final repo = ref.watch(taskRepositoryProvider);
    final done = subtasks.where((task) => task.status == 'done').length;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Подзадачи'),
          Text('${widget.parent.title} · $done/${subtasks.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: subtasks.length,
                itemBuilder: (context, index) {
                  final subtask = subtasks[index];
                  return Row(
                    children: [
                      Tooltip(
                        message: subtask.status == 'done'
                            ? 'Вернуть в работу'
                            : 'Отметить выполненной',
                        child: Checkbox(
                          value: subtask.status == 'done',
                          onChanged: (value) =>
                              repo.toggleDone(subtask.id, value ?? false),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(subtask.id),
                          initialValue: subtask.title,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onFieldSubmitted: (value) {
                            final title = value.trim();
                            _saveTimers[subtask.id]?.cancel();
                            _pendingTitles.remove(subtask.id);
                            if (title.isNotEmpty && title != subtask.title) {
                              repo.updateTask(subtask.id, title: Value(title));
                            }
                            if (index == subtasks.length - 1) {
                              _addFocus.requestFocus();
                            }
                          },
                          onChanged: (value) {
                            _scheduleTitleSave(subtask, value);
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Переместить выше',
                        icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                        onPressed: index == 0
                            ? null
                            : () => repo.moveSubtask(
                                widget.parent.id, subtask.id, -1),
                      ),
                      IconButton(
                        tooltip: 'Переместить ниже',
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        onPressed: index == subtasks.length - 1
                            ? null
                            : () => repo.moveSubtask(
                                widget.parent.id, subtask.id, 1),
                      ),
                      IconButton(
                        tooltip: 'Удалить подзадачу',
                        icon: const Icon(Icons.delete_outline, size: 19),
                        onPressed: () async {
                          await repo.deleteTask(subtask.id);
                          if (!context.mounted) return;
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.hideCurrentSnackBar();
                          messenger.showSnackBar(SnackBar(
                            duration: const Duration(seconds: 5),
                            showCloseIcon: true,
                            content: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: messenger.hideCurrentSnackBar,
                              child: const Text('Подзадача удалена'),
                            ),
                            action: SnackBarAction(
                                label: 'Отменить',
                                onPressed: () {
                                  messenger.hideCurrentSnackBar();
                                  repo.restoreTask(subtask.id);
                                }),
                          ));
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addController,
              focusNode: _addFocus,
              autofocus: subtasks.isEmpty,
              decoration: const InputDecoration(
                hintText: 'Добавить подзадачу',
                prefixIcon: Icon(Icons.add),
                isDense: true,
              ),
              onSubmitted: (_) => _add(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    final repo = ref.read(taskRepositoryProvider);
    for (final entry in _pendingTitles.entries) {
      repo.updateTask(entry.key, title: Value(entry.value));
    }
    _addController.dispose();
    _addFocus.dispose();
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

class _HoverSurface extends StatefulWidget {
  final Widget child;
  final bool selected;
  final Color accent;
  final ListDensity density;
  final Widget hoverActions;
  final VoidCallback onOpen,
      onPin,
      onPostpone,
      onDuplicate,
      onConvert,
      onDelete;
  const _HoverSurface(
      {required this.child,
      required this.selected,
      required this.accent,
      required this.density,
      required this.hoverActions,
      required this.onOpen,
      required this.onPin,
      required this.onPostpone,
      required this.onDuplicate,
      required this.onConvert,
      required this.onDelete});
  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool _hovered = false;

  Future<void> _menu(TapDownDetails details) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final value = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
            details.globalPosition & const Size(1, 1),
            Offset.zero & overlay.size),
        items: const [
          PopupMenuItem(value: 'open', child: Text('Открыть')),
          PopupMenuItem(value: 'pin', child: Text('Закрепить / открепить')),
          PopupMenuItem(value: 'postpone', child: Text('Отложить на завтра')),
          PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
          PopupMenuItem(
              value: 'convert', child: Text('Преобразовать в список')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ]);
    switch (value) {
      case 'open':
        widget.onOpen();
      case 'pin':
        widget.onPin();
      case 'postpone':
        widget.onPostpone();
      case 'duplicate':
        widget.onDuplicate();
      case 'convert':
        widget.onConvert();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onSecondaryTapDown: _menu,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: widget.density == ListDensity.compact ? 0 : 2),
            decoration: BoxDecoration(
              color: widget.selected
                  ? Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: .55)
                  : _hovered
                      ? Theme.of(context).colorScheme.surfaceContainerHigh
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                  left: BorderSide(
                      color: widget.accent,
                      width: widget.selected || _hovered ? 3 : 2)),
            ),
            child: Stack(alignment: Alignment.centerRight, children: [
              widget.child,
              AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: widget.hoverActions,
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
