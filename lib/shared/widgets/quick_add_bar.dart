import 'package:flutter/material.dart';

import '../../core/localization/app_localization.dart';
import '../../core/db/database.dart';
import '../../features/tasks/domain/recurrence.dart';
import 'duration_input_dialog.dart';
import 'package:flutter/services.dart';

/// Результат разбора строки быстрого ввода.
/// Парсинг сейчас — минимальный стаб (сегодня/завтра/!important),
/// в этапе 1 заменяется на полноценный NLP-разбор дат.
class QuickAddParseResult {
  final String title;
  final DateTime? dueDate;
  final int basePriority;
  final String? folderId;
  final int? durationMinutes;
  final String? recurrenceRule;

  QuickAddParseResult({
    required this.title,
    this.dueDate,
    this.basePriority = 1,
    this.folderId,
    this.durationMinutes,
    this.recurrenceRule,
  });
}

QuickAddParseResult parseQuickAdd(String raw, {DateTime? now}) {
  var text = raw.trim();
  DateTime? dueDate;
  var priority = 1;

  if (text.contains('!высокий') || text.contains('!important')) {
    priority = 2;
    text = text.replaceAll('!высокий', '').replaceAll('!important', '');
  }

  final currentTime = now ?? DateTime.now();
  if (text.contains('завтра')) {
    dueDate = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day + 1,
    );
    text = text.replaceAll('завтра', '');
  } else if (text.contains('сегодня')) {
    dueDate = DateTime(currentTime.year, currentTime.month, currentTime.day);
    text = text.replaceAll('сегодня', '');
  }

  return QuickAddParseResult(
    title: text.trim(),
    dueDate: dueDate,
    basePriority: priority,
  );
}

class QuickAddBar extends StatefulWidget {
  final void Function(QuickAddParseResult) onSubmit;

  const QuickAddBar({super.key, required this.onSubmit});

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

enum _DynamicBarMode { balanced, add, search }

class DynamicTaskBar extends StatefulWidget {
  final void Function(QuickAddParseResult) onSubmit;
  final ValueChanged<String> onSearch;
  final String searchText;
  final List<Folder> folders;
  final String? initialFolderId;
  const DynamicTaskBar(
      {super.key,
      required this.onSubmit,
      required this.onSearch,
      this.searchText = '',
      this.folders = const [],
      this.initialFolderId});

  @override
  State<DynamicTaskBar> createState() => _DynamicTaskBarState();
}

class _DynamicTaskBarState extends State<DynamicTaskBar> {
  final _addController = TextEditingController();
  final _searchController = TextEditingController();
  final _addFocus = FocusNode();
  final _searchFocus = FocusNode();
  _DynamicBarMode _mode = _DynamicBarMode.balanced;
  DateTime? _dueDate;
  int _priority = 1;
  String? _folderId;
  int? _durationMinutes;
  RecurrenceFrequency _recurrence = RecurrenceFrequency.none;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchText;
    _folderId = widget.initialFolderId;
    _addFocus.addListener(_handleFocusChange);
    _searchFocus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant DynamicTaskBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchText != oldWidget.searchText &&
        widget.searchText != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: widget.searchText,
        selection: TextSelection.collapsed(offset: widget.searchText.length),
      );
      setState(() {});
    }
    if (widget.initialFolderId != oldWidget.initialFolderId &&
        (_folderId == null || _folderId == oldWidget.initialFolderId)) {
      _folderId = widget.initialFolderId;
    }
  }

  void _handleFocusChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _addFocus.hasFocus || _searchFocus.hasFocus) return;
      if (_mode == _DynamicBarMode.add &&
          _addController.text.trim().isNotEmpty) {
        return;
      }
      if (_mode != _DynamicBarMode.balanced) {
        setState(() => _mode = _DynamicBarMode.balanced);
      }
    });
  }

  void _activate(_DynamicBarMode mode) {
    setState(() => _mode = mode);
    if (mode == _DynamicBarMode.add) _addFocus.requestFocus();
    if (mode == _DynamicBarMode.search) _searchFocus.requestFocus();
  }

  void _submit() {
    if (_addController.text.trim().isEmpty) return;
    final parsed = parseQuickAdd(_addController.text);
    widget.onSubmit(QuickAddParseResult(
      title: parsed.title,
      dueDate: _dueDate ?? parsed.dueDate,
      basePriority: parsed.basePriority == 2 ? 2 : _priority,
      folderId: _folderId,
      durationMinutes: _durationMinutes,
      recurrenceRule: RecurrenceRule.toStorageValue(_recurrence),
    ));
    _addController.clear();
    setState(() {
      _dueDate = null;
      _priority = 1;
      _folderId = widget.initialFolderId;
      _durationMinutes = null;
      _recurrence = RecurrenceFrequency.none;
    });
  }

  void _clearAdd() {
    _addController.clear();
    setState(() {
      _dueDate = null;
      _priority = 1;
      _folderId = widget.initialFolderId;
      _durationMinutes = null;
      _recurrence = RecurrenceFrequency.none;
    });
    _addFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _addFocus.unfocus();
            _searchFocus.unfocus();
            setState(() => _mode = _DynamicBarMode.balanced);
          },
        },
        child: Focus(
          child: LayoutBuilder(builder: (context, box) {
            const gap = 8.0;
            const compact = 48.0;
            final half = (box.maxWidth - gap) / 2;
            final addWidth = _mode == _DynamicBarMode.search
                ? compact
                : _mode == _DynamicBarMode.add
                    ? box.maxWidth - compact - gap
                    : half;
            final searchWidth = _mode == _DynamicBarMode.add
                ? compact
                : _mode == _DynamicBarMode.search
                    ? box.maxWidth - compact - gap
                    : half;
            Widget shell(
                    {required double width,
                    required bool active,
                    required IconData icon,
                    required String tooltip,
                    required VoidCallback onTap,
                    required Widget field}) =>
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: width,
                  height: 46,
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: active
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .35)
                            : Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: width <= compact + 4
                      ? IconButton(
                          onPressed: onTap,
                          tooltip: tooltip,
                          icon: Icon(icon, size: 19))
                      : ClipRect(
                          child: Row(children: [
                          IconButton(
                              onPressed: onTap,
                              tooltip: tooltip,
                              icon: Icon(icon, size: 19)),
                          Expanded(child: field),
                        ])),
                );
            final addRow = Row(children: [
              shell(
                  width: addWidth,
                  active: _mode == _DynamicBarMode.add,
                  icon: Icons.add,
                  tooltip: context.l10n.text('Add task', 'Добавить задачу'),
                  onTap: () => _activate(_DynamicBarMode.add),
                  field: TextField(
                      controller: _addController,
                      focusNode: _addFocus,
                      onTap: () => _activate(_DynamicBarMode.add),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                          hintText:
                              context.l10n.text('Add task', 'Добавить задачу'),
                          border: InputBorder.none,
                          suffixIcon: _addController.text.isEmpty
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: context.l10n
                                          .text('Clear', 'Очистить'),
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: _clearAdd,
                                    ),
                                    IconButton(
                                      tooltip: context.l10n.text(
                                          'Create task', 'Создать задачу'),
                                      icon: const Icon(Icons.arrow_forward,
                                          size: 19),
                                      onPressed: _submit,
                                    ),
                                  ],
                                )))),
              const SizedBox(width: gap),
              shell(
                  width: searchWidth,
                  active: _mode == _DynamicBarMode.search,
                  icon: Icons.search,
                  tooltip: context.l10n.text('Search', 'Поиск'),
                  onTap: () => _activate(_DynamicBarMode.search),
                  field: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onTap: () => _activate(_DynamicBarMode.search),
                      onChanged: (value) {
                        widget.onSearch(value);
                        setState(() {});
                      },
                      decoration: InputDecoration(
                          hintText: context.l10n
                              .text('Search tasks', 'Поиск в задачах'),
                          border: InputBorder.none,
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    widget.onSearch('');
                                    setState(() {});
                                  })))),
            ]);
            final showOptions = _mode == _DynamicBarMode.add &&
                _addController.text.trim().isNotEmpty;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              addRow,
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: showOptions
                    ? _QuickTaskOptions(
                        dueDate: _dueDate,
                        priority: _priority,
                        folderId: _folderId,
                        folders: widget.folders,
                        durationMinutes: _durationMinutes,
                        recurrence: _recurrence,
                        onDueDate: (value) => setState(() => _dueDate = value),
                        onPriority: (value) =>
                            setState(() => _priority = value),
                        onFolder: (value) => setState(() => _folderId = value),
                        onDuration: (value) =>
                            setState(() => _durationMinutes = value),
                        onRecurrence: (value) =>
                            setState(() => _recurrence = value),
                        onCreate: _submit,
                      )
                    : const SizedBox.shrink(),
              ),
            ]);
          }),
        ),
      );

  @override
  void dispose() {
    _addFocus.removeListener(_handleFocusChange);
    _searchFocus.removeListener(_handleFocusChange);
    _addController.dispose();
    _searchController.dispose();
    _addFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
}

class _QuickTaskOptions extends StatelessWidget {
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

  const _QuickTaskOptions({
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          MenuAnchor(
            builder: (context, controller, _) => ActionChip(
              avatar: const Icon(Icons.event_outlined, size: 17),
              label: Text(dueDate == null
                  ? l10n.text('Due date', 'Срок')
                  : MaterialLocalizations.of(context)
                      .formatShortDate(dueDate!)),
              onPressed: controller.open,
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
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(l10n.text('Low', 'Низкий'))),
              ButtonSegment(
                  value: 1, label: Text(l10n.text('Medium', 'Средний'))),
              ButtonSegment(
                  value: 2, label: Text(l10n.text('High', 'Высокий'))),
            ],
            selected: {priority},
            onSelectionChanged: (value) => onPriority(value.first),
          ),
          DropdownButton<String?>(
            value: folderId,
            hint: Text(l10n.text('No folder', 'Без папки')),
            items: [
              DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.text('No folder', 'Без папки'))),
              ...folders.map((folder) => DropdownMenuItem<String?>(
                  value: folder.id, child: Text(folder.name))),
            ],
            onChanged: onFolder,
          ),
          ActionChip(
            avatar: const Icon(Icons.timer_outlined, size: 17),
            label: Text(durationMinutes == null
                ? l10n.text('Duration', 'Длительность')
                : formatTaskDuration(context, durationMinutes!)),
            onPressed: () async {
              final value = await showDurationInputDialog(context,
                  initialMinutes: durationMinutes);
              if (value != null) onDuration(value == 0 ? null : value);
            },
          ),
          DropdownButton<RecurrenceFrequency>(
            value: recurrence,
            items: RecurrenceFrequency.values
                .map((value) => DropdownMenuItem(
                    value: value,
                    child: Text(switch (value) {
                      RecurrenceFrequency.none =>
                        l10n.text('Does not repeat', 'Не повторяется'),
                      RecurrenceFrequency.daily =>
                        l10n.text('Every day', 'Каждый день'),
                      RecurrenceFrequency.weekly =>
                        l10n.text('Every week', 'Каждую неделю'),
                      RecurrenceFrequency.monthly =>
                        l10n.text('Every month', 'Каждый месяц'),
                    })))
                .toList(),
            onChanged: (value) => value == null ? null : onRecurrence(value),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add_task, size: 18),
            label: Text(l10n.text('Create', 'Создать')),
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();

  void _submit() {
    if (_controller.text.trim().isEmpty) return;
    final parsed = parseQuickAdd(_controller.text);
    widget.onSubmit(parsed);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.add, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Купить молоко завтра !высокий',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
