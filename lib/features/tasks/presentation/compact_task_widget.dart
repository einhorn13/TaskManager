import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/database.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/window/app_window_controller.dart';
import '../../../shared/widgets/duration_input_dialog.dart';
import '../../../shared/widgets/quick_add_bar.dart';
import '../../filters/domain/filter_state.dart';
import '../application/task_providers.dart';
import '../domain/recurrence.dart';

class CompactTaskWidget extends ConsumerStatefulWidget {
  const CompactTaskWidget({super.key});

  @override
  ConsumerState<CompactTaskWidget> createState() => _CompactTaskWidgetState();
}

class _CompactTaskWidgetState extends ConsumerState<CompactTaskWidget> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _adding = false;
  DateTime? _dueDate;
  int _priority = 1;
  String? _folderId;
  int? _durationMinutes;
  RecurrenceFrequency _recurrence = RecurrenceFrequency.none;

  @override
  void initState() {
    super.initState();
    _folderId = ref.read(taskFilterProvider).folderId;
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _addTask() async {
    final parsed = parseQuickAdd(_controller.text);
    if (parsed.title.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final filter = ref.read(taskFilterProvider);
      await ref.read(taskRepositoryProvider).addTask(
            title: parsed.title,
            dueDate: _dueDate ?? parsed.dueDate,
            basePriority: parsed.basePriority == 2 ? 2 : _priority,
            folderId: _folderId,
            durationMinutes: _durationMinutes,
            recurrenceRule: RecurrenceRule.toStorageValue(_recurrence),
          );
      _controller.clear();
      setState(() {
        _dueDate = null;
        _priority = 1;
        _folderId = filter.folderId;
        _durationMinutes = null;
        _recurrence = RecurrenceFrequency.none;
      });
      _focusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _clearTask() {
    final filter = ref.read(taskFilterProvider);
    _controller.clear();
    setState(() {
      _dueDate = null;
      _priority = 1;
      _folderId = filter.folderId;
      _durationMinutes = null;
      _recurrence = RecurrenceFrequency.none;
    });
    _focusNode.requestFocus();
  }

  void _selectView(String value) {
    final parts = value.split(':');
    final kind = parts.first;
    final id = value.substring(kind.length + 1);
    if (kind == 'folder') {
      ref.read(taskFilterProvider.notifier).state = TaskFilter(
        smartFilter: SmartFilter.all,
        folderId: id,
      );
      return;
    }

    ref.read(taskFilterProvider.notifier).state = TaskFilter(
      smartFilter: SmartFilter.values.byName(id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = ref.watch(taskFilterProvider);
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    final all = ref.watch(filteredSortedTasksProvider);
    final active = all.where((task) => task.status != 'done').toList();
    final overdue = active
        .where((task) =>
            task.dueDate != null && task.dueDate!.isBefore(DateTime.now()))
        .length;
    final title = _viewTitle(l10n, filter, folders);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: scheme.surface.withValues(alpha: dark ? .68 : .58),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .22),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) =>
                            AppWindowController.instance.startDragging(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PopupMenuButton<String>(
                              tooltip: l10n.text(
                                  'Choose view', 'Выбрать папку или фильтр'),
                              onSelected: _selectView,
                              position: PopupMenuPosition.under,
                              itemBuilder: (_) => [
                                ...SmartFilter.values.map(
                                  (value) => PopupMenuItem(
                                    value: 'filter:${value.name}',
                                    child: Row(children: [
                                      const Icon(Icons.filter_alt_outlined,
                                          size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(_filterLabel(l10n, value)),
                                      ),
                                    ]),
                                  ),
                                ),
                                if (folders.isNotEmpty)
                                  const PopupMenuDivider(),
                                ...folders.map(
                                  (folder) => PopupMenuItem(
                                    value: 'folder:${folder.id}',
                                    child: Row(children: [
                                      const Icon(Icons.folder_outlined,
                                          size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(folder.name,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ]),
                                  ),
                                ),
                              ],
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              color: scheme.onPrimary,
                                              fontWeight: FontWeight.w700,
                                            )),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_drop_down_rounded,
                                      color: scheme.onPrimary),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              overdue == 0
                                  ? l10n.text('${active.length} active',
                                      '${active.length} активных')
                                  : l10n.text(
                                      '${active.length} active · $overdue overdue',
                                      '${active.length} активных · $overdue просрочено'),
                              style: TextStyle(
                                  color:
                                      scheme.onPrimary.withValues(alpha: .8)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.text('Hide to tray', 'Свернуть в трей'),
                      onPressed: AppWindowController.instance.hideToTray,
                      color: scheme.onPrimary,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    IconButton(
                      tooltip: l10n.text('Full view', 'Полный вид'),
                      onPressed: AppWindowController.instance.exitCompactMode,
                      color: scheme.onPrimary,
                      icon: const Icon(Icons.open_in_full_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: l10n.text('Quit', 'Завершить работу'),
                      onPressed: AppWindowController.instance.quit,
                      color: scheme.onPrimary,
                      icon: const Icon(Icons.power_settings_new_rounded,
                          size: 20),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTask(),
                  decoration: InputDecoration(
                    hintText:
                        l10n.text('Quick add task…', 'Быстро добавить задачу…'),
                    prefixIcon: const Icon(Icons.add_task_rounded),
                    suffixIcon: _adding
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_controller.text.isNotEmpty)
                                IconButton(
                                  tooltip: l10n.text('Clear', 'Очистить'),
                                  onPressed: _clearTask,
                                  icon:
                                      const Icon(Icons.close_rounded, size: 19),
                                ),
                              IconButton(
                                tooltip:
                                    l10n.text('Add task', 'Добавить задачу'),
                                onPressed: _addTask,
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                            ],
                          ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _controller.text.trim().isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: _CompactQuickOptions(
                          dueDate: _dueDate,
                          priority: _priority,
                          folderId: _folderId,
                          folders: folders,
                          durationMinutes: _durationMinutes,
                          recurrence: _recurrence,
                          onDueDate: (value) =>
                              setState(() => _dueDate = value),
                          onPriority: (value) =>
                              setState(() => _priority = value),
                          onFolder: (value) =>
                              setState(() => _folderId = value),
                          onDuration: (value) =>
                              setState(() => _durationMinutes = value),
                          onRecurrence: (value) =>
                              setState(() => _recurrence = value),
                          onCreate: _addTask,
                        ),
                      ),
              ),
              Expanded(
                child: active.isEmpty
                    ? _EmptyCompactView(l10n: l10n)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: active.length,
                        itemBuilder: (context, index) =>
                            _CompactTaskTile(task: active[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactQuickOptions extends StatelessWidget {
  final DateTime? dueDate;
  final int priority;
  final String? folderId;
  final List<Folder> folders;
  final int? durationMinutes;
  final RecurrenceFrequency recurrence;
  final ValueChanged<DateTime?> onDueDate;
  final ValueChanged<int> onPriority;
  final ValueChanged<String?> onFolder;
  final ValueChanged<int?> onDuration;
  final ValueChanged<RecurrenceFrequency> onRecurrence;
  final VoidCallback onCreate;

  const _CompactQuickOptions({
    required this.dueDate,
    required this.priority,
    required this.folderId,
    required this.folders,
    required this.durationMinutes,
    required this.recurrence,
    required this.onDueDate,
    required this.onPriority,
    required this.onFolder,
    required this.onDuration,
    required this.onRecurrence,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    InputDecoration decoration(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 17),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: MenuAnchor(
                builder: (context, menu, _) => OutlinedButton.icon(
                  onPressed: menu.open,
                  icon: const Icon(Icons.event_outlined, size: 17),
                  label: Text(
                    dueDate == null
                        ? l10n.text('Due date', 'Срок')
                        : MaterialLocalizations.of(context)
                            .formatShortDate(dueDate!),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => onDueDate(null),
                    child: Text(l10n.text('No due date', 'Без срока')),
                  ),
                  MenuItemButton(
                    onPressed: () {
                      final now = DateTime.now();
                      onDueDate(DateTime(now.year, now.month, now.day));
                    },
                    child: Text(l10n.text('Today', 'Сегодня')),
                  ),
                  MenuItemButton(
                    onPressed: () {
                      final now = DateTime.now();
                      onDueDate(DateTime(now.year, now.month, now.day + 1));
                    },
                    child: Text(l10n.text('Tomorrow', 'Завтра')),
                  ),
                  MenuItemButton(
                    onPressed: () async {
                      final value = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate ?? DateTime.now(),
                      );
                      if (value != null) onDueDate(value);
                    },
                    child: Text(l10n.text('Choose date…', 'Выбрать дату…')),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: priority,
                isExpanded: true,
                decoration:
                    decoration(l10n.text('Priority', 'Приоритет'), Icons.flag),
                items: [
                  DropdownMenuItem(
                      value: 0, child: Text(l10n.text('Low', 'Низкий'))),
                  DropdownMenuItem(
                      value: 1, child: Text(l10n.text('Medium', 'Средний'))),
                  DropdownMenuItem(
                      value: 2, child: Text(l10n.text('High', 'Высокий'))),
                ],
                onChanged: (value) => value == null ? null : onPriority(value),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: folderId,
                isExpanded: true,
                decoration:
                    decoration(l10n.text('Folder', 'Папка'), Icons.folder),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.text('No folder', 'Без папки')),
                  ),
                  ...folders.map((folder) => DropdownMenuItem<String?>(
                        value: folder.id,
                        child:
                            Text(folder.name, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: onFolder,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final value = await showDurationInputDialog(context,
                      initialMinutes: durationMinutes);
                  if (value != null) onDuration(value == 0 ? null : value);
                },
                icon: const Icon(Icons.timer_outlined, size: 17),
                label: Text(
                  durationMinutes == null
                      ? l10n.text('Duration', 'Длительность')
                      : formatTaskDuration(context, durationMinutes!),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<RecurrenceFrequency>(
                initialValue: recurrence,
                isExpanded: true,
                decoration: decoration(
                    l10n.text('Repeat', 'Повтор'), Icons.repeat_rounded),
                items: RecurrenceFrequency.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(_recurrenceLabel(l10n, value),
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) =>
                    value == null ? null : onRecurrence(value),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: Text(l10n.text('Create', 'Создать')),
            ),
          ]),
        ],
      ),
    );
  }
}

String _recurrenceLabel(AppLocalizations l10n, RecurrenceFrequency frequency) {
  return switch (frequency) {
    RecurrenceFrequency.none => l10n.text('Does not repeat', 'Не повторяется'),
    RecurrenceFrequency.daily => l10n.text('Every day', 'Каждый день'),
    RecurrenceFrequency.weekly => l10n.text('Every week', 'Каждую неделю'),
    RecurrenceFrequency.monthly => l10n.text('Every month', 'Каждый месяц'),
  };
}

String _viewTitle(
    AppLocalizations l10n, TaskFilter filter, List<Folder> folders) {
  if (filter.folderId != null) {
    for (final folder in folders) {
      if (folder.id == filter.folderId) return folder.name;
    }
  }
  return switch (filter.smartFilter) {
    SmartFilter.current => l10n.text('Current', 'Актуальные'),
    SmartFilter.today => l10n.text('Today', 'Сегодня'),
    SmartFilter.expiring => l10n.text('Expiring', 'Истекающие'),
    SmartFilter.important => l10n.text('Important', 'Важные'),
    SmartFilter.someday => l10n.text('Someday', 'Когда-нибудь'),
    SmartFilter.all => l10n.text('All tasks', 'Все задачи'),
  };
}

String _filterLabel(AppLocalizations l10n, SmartFilter value) {
  return switch (value) {
    SmartFilter.current => l10n.text('Current', 'Актуальные'),
    SmartFilter.today => l10n.text('Today', 'Сегодня'),
    SmartFilter.expiring => l10n.text('Expiring', 'Истекающие'),
    SmartFilter.important => l10n.text('Important', 'Важные'),
    SmartFilter.someday => l10n.text('Someday', 'Когда-нибудь'),
    SmartFilter.all => l10n.text('All tasks', 'Все задачи'),
  };
}

class _CompactTaskTile extends ConsumerWidget {
  final Task task;
  const _CompactTaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final overdue =
        task.dueDate != null && task.dueDate!.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            ref.read(selectedTaskIdProvider.notifier).state = task.id;
            await AppWindowController.instance.exitCompactMode();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Checkbox(
                  value: false,
                  visualDensity: VisualDensity.compact,
                  onChanged: (value) => ref
                      .read(taskRepositoryProvider)
                      .toggleDone(task.id, value ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (task.dueDate != null) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.schedule_rounded,
                              size: 13,
                              color: overdue ? scheme.error : scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.MMMd(locale)
                                .add_Hm()
                                .format(task.dueDate!),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: overdue
                                      ? scheme.error
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
                if (task.isPinned)
                  Icon(Icons.push_pin_rounded, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCompactView extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyCompactView({required this.l10n});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded,
                size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(l10n.text('Nothing pending', 'Ничего не осталось')),
          ],
        ),
      );
}
