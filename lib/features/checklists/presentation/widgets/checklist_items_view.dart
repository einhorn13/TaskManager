import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/supabase_config.dart';
import '../../../collaboration/data/collaboration_service.dart';
import '../../../collaboration/presentation/share_dialog.dart';
import '../../application/checklist_providers.dart';
import '../../../../shared/widgets/dismissible_snack_bar.dart';

class ChecklistItemsView extends ConsumerStatefulWidget {
  final String checklistId;

  const ChecklistItemsView({required this.checklistId, super.key});

  @override
  ConsumerState<ChecklistItemsView> createState() => _ChecklistItemsViewState();
}

class _ChecklistItemsViewState extends ConsumerState<ChecklistItemsView> {
  final _addController = TextEditingController();

  void _addItem() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    ref.read(checklistRepositoryProvider).addItem(widget.checklistId, text);
    _addController.clear();
  }

  Future<void> _saveAsTemplate(String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сохранить как шаблон'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    await ref
        .read(checklistRepositoryProvider)
        .saveAsTemplate(widget.checklistId, title);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      dismissibleSnackBar(context, content: Text('Шаблон "$title" сохранён')),
    );
  }

  Future<void> _deleteChecklist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить список?'),
        content: const Text('Список и все его пункты будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(checklistRepositoryProvider)
        .deleteChecklist(widget.checklistId);
    ref.read(selectedChecklistIdProvider.notifier).state = null;
  }

  Future<void> _renameChecklist(String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Переименовать список'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('Сохранить')),
                ]));
    if (title == null || title.isEmpty) return;
    await ref
        .read(checklistRepositoryProvider)
        .renameChecklist(widget.checklistId, title);
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checklist = ref.watch(checklistByIdProvider(widget.checklistId));
    final items =
        ref.watch(itemsForChecklistProvider(widget.checklistId)).value ??
            const [];
    final repo = ref.watch(checklistRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${checklist?.title ?? ''} · ${items.where((i) => i.isDone).length}/${items.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'template') {
                    _saveAsTemplate(checklist?.title ?? '');
                  } else if (value == 'delete') {
                    _deleteChecklist();
                  } else if (value == 'rename') {
                    _renameChecklist(checklist?.title ?? '');
                  } else if (value == 'share' && checklist != null) {
                    showShareDialog(
                      context,
                      ref,
                      entityType: SharedEntityType.checklist,
                      entityId: checklist.id,
                      alreadyShared: checklist.spaceId != null,
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'rename', child: Text('Переименовать')),
                  if (checklist != null &&
                      SupabaseConfig.enabled &&
                      checklist.userId == SupabaseConfig.activeUserId)
                    PopupMenuItem(
                      value: 'share',
                      child: Text(checklist.spaceId == null
                          ? 'Поделиться'
                          : 'Общий доступ'),
                    ),
                  const PopupMenuItem(
                    value: 'template',
                    child: Text('Сохранить как шаблон'),
                  ),
                  const PopupMenuItem(
                      value: 'delete', child: Text('Удалить список')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Пунктов пока нет'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: const Icon(Icons.delete_outline),
                      ),
                      onDismissed: (_) => repo.deleteItem(item.id),
                      child: CheckboxListTile(
                        value: item.isDone,
                        onChanged: (v) => repo.toggleItem(item.id, v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Row(
                          children: [
                            Expanded(
                                child: Text(item.text_,
                                    style: item.isDone
                                        ? const TextStyle(
                                            decoration:
                                                TextDecoration.lineThrough)
                                        : null)),
                            IconButton(
                                icon: const Icon(Icons.keyboard_arrow_up,
                                    size: 18),
                                tooltip: 'Выше',
                                onPressed: index == 0
                                    ? null
                                    : () => repo.moveItem(
                                        widget.checklistId, item.id, -1)),
                            IconButton(
                                icon: const Icon(Icons.keyboard_arrow_down,
                                    size: 18),
                                tooltip: 'Ниже',
                                onPressed: index == items.length - 1
                                    ? null
                                    : () => repo.moveItem(
                                        widget.checklistId, item.id, 1)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _addController,
            decoration: const InputDecoration(
              hintText: 'Добавить пункт',
              prefixIcon: Icon(Icons.add, size: 18),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _addItem(),
          ),
        ),
      ],
    );
  }
}
