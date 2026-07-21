import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/db/database.dart';
import '../../../../core/settings/ui_settings.dart';
import '../../../../core/sync/supabase_config.dart';
import '../../../../shared/widgets/duration_input_dialog.dart';
import '../../../../shared/widgets/dismissible_snack_bar.dart';
import '../../../collaboration/data/collaboration_service.dart';
import '../../../collaboration/presentation/share_dialog.dart';
import '../../application/task_providers.dart';
import '../../domain/recurrence.dart';
import 'due_date_dialog.dart';

/// Панель редактирования задачи. Пересоздаётся (через ValueKey на task.id) при
/// смене выбранной задачи, поэтому контроллеры полей всегда синхронны с данными
/// — не нужно вручную сверять "старую" и "новую" задачу в didUpdateWidget.
class TaskDetailPanel extends ConsumerStatefulWidget {
  final Task task;

  const TaskDetailPanel({required this.task, super.key});

  @override
  ConsumerState<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends ConsumerState<TaskDetailPanel> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final TextEditingController _subtaskController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _attachmentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController =
        TextEditingController(text: widget.task.description ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _subtaskController.dispose();
    _tagController.dispose();
    _attachmentController.dispose();
    super.dispose();
  }

  void _saveTitle() {
    if (_titleController.text.trim().isEmpty) return;
    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          title: drift.Value(_titleController.text.trim()),
        );
    _showSaved();
  }

  void _saveDescription() {
    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          description: drift.Value(
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
          ),
        );
    _showSaved();
  }

  void _showSaved() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
      context,
      content: const Text('Сохранено'),
      duration: const Duration(milliseconds: 900),
    ));
  }

  Future<void> _pickDueDate() async {
    final dueDate = await showDueDateDialog(
      context,
      initialDate: widget.task.dueDate,
    );
    if (dueDate == null || !mounted) return;

    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          dueDate: drift.Value(dueDate),
        );
  }

  void _clearDueDate() {
    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          dueDate: const drift.Value(null),
        );
    _showSaved();
  }

  void _setBasePriority(int value) {
    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          basePriority: drift.Value(value),
        );
    _showSaved();
  }

  void _setFolder(String? folderId) {
    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          folderId: drift.Value(folderId),
        );
    _showSaved();
  }

  void _setDurationMinutes(int? minutes) {
    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          durationMinutes: drift.Value(minutes),
        );
    _showSaved();
  }

  void _setRecurrence(RecurrenceFrequency freq) {
    ref.read(taskRepositoryProvider).updateTask(
          widget.task.id,
          recurrenceRule: drift.Value(RecurrenceRule.toStorageValue(freq)),
        );
    _showSaved();
  }

  Future<void> _addSubtask(String title) async {
    if (title.trim().isEmpty) return;
    await ref
        .read(taskRepositoryProvider)
        .addSubtask(widget.task.id, title.trim());
  }

  Future<void> _createFolderInline() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая папка'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final id = await ref.read(folderRepositoryProvider).createFolder(name);
    _setFolder(id);
  }

  Future<void> _createAndAssignTag() async {
    final name = _tagController.text.trim().replaceFirst(RegExp(r'^#'), '');
    if (name.isEmpty) return;
    final repo = ref.read(taskExtrasRepositoryProvider);
    final id = await repo.createTag(name);
    await repo.setTaskTag(widget.task.id, id, true);
    _tagController.clear();
  }

  Future<void> _manageTag(Tag tag) async {
    final controller = TextEditingController(text: tag.name);
    final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Изменить тег'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      child: const Text('Удалить')),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, 'save'),
                      child: const Text('Сохранить')),
                ]));
    if (action == 'delete') {
      await ref.read(taskExtrasRepositoryProvider).deleteTag(tag.id);
    } else if (action == 'save' && controller.text.trim().isNotEmpty) {
      await ref
          .read(taskExtrasRepositoryProvider)
          .renameTag(tag.id, controller.text);
    }
  }

  Future<void> _manageFolder(Folder folder) async {
    final controller = TextEditingController(text: folder.name);
    var color = folder.color ?? '#607D8B';
    final action = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: const Text('Изменить папку'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: controller, autofocus: true),
                    const SizedBox(height: 12),
                    Wrap(
                        spacing: 8,
                        children: [
                          '#607D8B',
                          '#1976D2',
                          '#388E3C',
                          '#F57C00',
                          '#7B1FA2',
                          '#D32F2F'
                        ]
                            .map((value) => ChoiceChip(
                                label: Text(value),
                                selected: color == value,
                                onSelected: (_) =>
                                    setState(() => color = value)))
                            .toList()),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'delete'),
                        child: const Text('Удалить')),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, 'save'),
                        child: const Text('Сохранить')),
                  ],
                )));
    if (action == 'delete') {
      await ref.read(folderRepositoryProvider).deleteFolder(folder.id);
    } else if (action == 'save' && controller.text.trim().isNotEmpty) {
      await ref
          .read(folderRepositoryProvider)
          .updateFolder(folder.id, name: controller.text, color: color);
    }
  }

  Future<void> _addAttachment(String type) async {
    final value = _attachmentController.text.trim();
    if (value.isEmpty) return;
    await ref
        .read(taskExtrasRepositoryProvider)
        .addAttachment(widget.task.id, type, value);
    _attachmentController.clear();
  }

  Future<void> _pickAttachment(String type) async {
    final result = await FilePicker.platform
        .pickFiles(type: type == 'photo' ? FileType.image : FileType.any);
    final path = result?.files.single.path;
    if (path == null) return;
    await ref
        .read(taskExtrasRepositoryProvider)
        .addAttachment(widget.task.id, type, path);
  }

  Future<void> _openAttachment(TaskAttachment item) async {
    final raw = item.url.trim();
    final uri =
        Uri.tryParse(raw.contains('://') ? raw : Uri.file(raw).toString());
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть вложение')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(foldersProvider);
    final folders = foldersAsync.value ?? const [];
    final subtaskDuration =
        ref.watch(subtaskDurationsByParentProvider).value?[widget.task.id] ??
            (0, 0);

    final detailWidth = ref.watch(uiSettingsProvider).taskDetailWidth;
    return SizedBox(
        width: detailWidth,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                left: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Детали задачи',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (SupabaseConfig.enabled &&
                                  widget.task.userId ==
                                      SupabaseConfig.activeUserId)
                                IconButton(
                                  tooltip: 'Поделиться задачей',
                                  icon: Icon(
                                    widget.task.spaceId == null
                                        ? Icons.group_add_outlined
                                        : Icons.group_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => showShareDialog(
                                    context,
                                    ref,
                                    entityType: SharedEntityType.task,
                                    entityId: widget.task.id,
                                    alreadyShared: widget.task.spaceId != null,
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => ref
                                    .read(selectedTaskIdProvider.notifier)
                                    .state = null,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleController,
                        style: Theme.of(context).textTheme.titleMedium,
                        decoration:
                            const InputDecoration(border: InputBorder.none),
                        onSubmitted: (_) => _saveTitle(),
                        onEditingComplete: _saveTitle,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Заметки',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onSubmitted: (_) => _saveDescription(),
                        onEditingComplete: _saveDescription,
                      ),
                      const SizedBox(height: 16),
                      Text('Срок',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickDueDate,
                              child: Text(
                                widget.task.dueDate == null
                                    ? 'Не задан'
                                    : DateFormat('d MMM, HH:mm', 'ru')
                                        .format(widget.task.dueDate!),
                              ),
                            ),
                          ),
                          if (widget.task.dueDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Убрать срок',
                              onPressed: _clearDueDate,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Приоритет',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Низкий')),
                          ButtonSegment(value: 1, label: Text('Средний')),
                          ButtonSegment(value: 2, label: Text('Высокий')),
                        ],
                        selected: {widget.task.basePriority},
                        onSelectionChanged: (s) => _setBasePriority(s.first),
                      ),
                      const SizedBox(height: 16),
                      Text('Папка',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: widget.task.folderId,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Без папки'),
                                ),
                                ...folders.map(
                                  (f) => DropdownMenuItem(
                                    value: f.id,
                                    child: Text(f.name),
                                  ),
                                ),
                              ],
                              onChanged: _setFolder,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            tooltip: 'Новая папка',
                            onPressed: _createFolderInline,
                          ),
                          if (widget.task.folderId != null)
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              tooltip: 'Изменить папку',
                              onPressed: () {
                                final matches = folders
                                    .where((f) => f.id == widget.task.folderId);
                                if (matches.isNotEmpty) {
                                  _manageFolder(matches.first);
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Длительность',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final minutes in [null, 15, 30, 60])
                            ChoiceChip(
                              label: Text(minutes == null
                                  ? 'Не задана'
                                  : '$minutes мин'),
                              selected: widget.task.durationMinutes == minutes,
                              onSelected: (_) => _setDurationMinutes(minutes),
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.edit_outlined, size: 17),
                            label: Text(widget.task.durationMinutes != null &&
                                    !const [15, 30, 60]
                                        .contains(widget.task.durationMinutes)
                                ? formatTaskDuration(
                                    context, widget.task.durationMinutes!)
                                : 'Вручную'),
                            onPressed: () async {
                              final value = await showDurationInputDialog(
                                  context,
                                  initialMinutes: widget.task.durationMinutes);
                              if (value != null) {
                                _setDurationMinutes(value == 0 ? null : value);
                              }
                            },
                          ),
                        ],
                      ),
                      if (subtaskDuration.$2 > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Подзадачи: ${formatTaskDuration(context, subtaskDuration.$1)} · '
                          'всего с оценкой задачи: ${formatTaskDuration(context, subtaskDuration.$1 + (widget.task.durationMinutes ?? 0))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text('Повтор',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<RecurrenceFrequency>(
                        initialValue: RecurrenceRule.fromStorageValue(
                            widget.task.recurrenceRule),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: RecurrenceFrequency.values
                            .map((f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(RecurrenceRule.label(f)),
                                ))
                            .toList(),
                        onChanged: (f) => f == null ? null : _setRecurrence(f),
                      ),
                      const SizedBox(height: 20),
                      Text('Теги',
                          style: Theme.of(context).textTheme.labelMedium),
                      Consumer(builder: (context, ref, _) {
                        final tags = ref.watch(tagsProvider).value ?? const [];
                        final selected = ref
                                .watch(taskTagIdsProvider(widget.task.id))
                                .value ??
                            const [];
                        final repo = ref.watch(taskExtrasRepositoryProvider);
                        return Column(children: [
                          Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 6,
                                children: tags
                                    .map((tag) => InputChip(
                                          label: Text('#${tag.name}'),
                                          selected: selected.contains(tag.id),
                                          onPressed: () => _manageTag(tag),
                                          deleteIcon: selected.contains(tag.id)
                                              ? const Icon(Icons.close,
                                                  size: 16)
                                              : null,
                                          onDeleted: selected.contains(tag.id)
                                              ? () => repo.setTaskTag(
                                                  widget.task.id, tag.id, false)
                                              : null,
                                          onSelected: (value) =>
                                              repo.setTaskTag(widget.task.id,
                                                  tag.id, value),
                                        ))
                                    .toList(),
                              )),
                          TextField(
                            controller: _tagController,
                            decoration: const InputDecoration(
                                hintText: 'Новый тег',
                                prefixIcon: Icon(Icons.tag)),
                            onSubmitted: (_) => _createAndAssignTag(),
                          ),
                        ]);
                      }),
                      const SizedBox(height: 20),
                      Text('Вложения',
                          style: Theme.of(context).textTheme.labelMedium),
                      Consumer(builder: (context, ref, _) {
                        final items = ref
                                .watch(taskAttachmentsProvider(widget.task.id))
                                .value ??
                            const [];
                        final repo = ref.watch(taskExtrasRepositoryProvider);
                        return Column(children: [
                          for (final item in items)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(item.type == 'link'
                                  ? Icons.link
                                  : Icons.attach_file),
                              title: Text(item.url,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => _openAttachment(item),
                              trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 17),
                                  onPressed: () =>
                                      repo.deleteAttachment(item.id)),
                            ),
                          TextField(
                            controller: _attachmentController,
                            decoration: InputDecoration(
                              hintText: 'Ссылка или путь к файлу',
                              suffixIcon: PopupMenuButton<String>(
                                icon: const Icon(Icons.add),
                                onSelected: (value) {
                                  if (value == 'link') _addAttachment('link');
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'link',
                                      child: Text('Добавить введённую ссылку')),
                                  PopupMenuItem(
                                      value: 'pick_file',
                                      onTap: () => _pickAttachment('file'),
                                      child: const Text('Выбрать файл…')),
                                  PopupMenuItem(
                                      value: 'pick_photo',
                                      onTap: () => _pickAttachment('photo'),
                                      child: const Text('Выбрать фото…')),
                                ],
                              ),
                            ),
                            onSubmitted: (_) => _addAttachment('link'),
                          ),
                        ]);
                      }),
                      const SizedBox(height: 20),
                      Text('Подзадачи',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Consumer(
                        builder: (context, ref, _) {
                          final subtasks = ref
                                  .watch(
                                      subtasksForTaskProvider(widget.task.id))
                                  .value ??
                              const [];
                          final repo = ref.watch(taskRepositoryProvider);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final sub in subtasks)
                                InkWell(
                                  onTap: () => ref
                                      .read(selectedTaskIdProvider.notifier)
                                      .state = sub.id,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: sub.status == 'done',
                                          onChanged: (v) => repo.toggleDone(
                                              sub.id, v ?? false),
                                        ),
                                        Expanded(
                                          child: Text(
                                            sub.title,
                                            style: sub.status == 'done'
                                                ? const TextStyle(
                                                    decoration: TextDecoration
                                                        .lineThrough)
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              TextField(
                                controller: _subtaskController,
                                decoration: const InputDecoration(
                                  hintText: 'Добавить подзадачу',
                                  isDense: true,
                                  prefixIcon: Icon(Icons.add, size: 16),
                                ),
                                onSubmitted: (value) {
                                  _addSubtask(value);
                                  _subtaskController.clear();
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final current = ref.read(uiSettingsProvider).taskDetailWidth;
                  final next = (current - details.delta.dx).clamp(320.0, 560.0);
                  ref.read(uiSettingsProvider.notifier).update(
                      (settings) => settings.copyWith(taskDetailWidth: next));
                },
              ),
            ),
          ),
        ]));
  }
}
