import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/checklist_providers.dart';

class ChecklistSidebar extends ConsumerWidget {
  const ChecklistSidebar({super.key});

  Future<void> _createChecklist(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый список'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Напр. Покупки'),
        ),
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
    if (title == null || title.isEmpty) return;
    final id =
        await ref.read(checklistRepositoryProvider).createChecklist(title);
    ref.read(selectedChecklistIdProvider.notifier).state = id;
  }

  Future<void> _createFromTemplate(
    WidgetRef ref,
    String templateId,
    String templateTitle,
  ) async {
    final id = await ref
        .read(checklistRepositoryProvider)
        .createChecklist(templateTitle, templateId: templateId);
    ref.read(selectedChecklistIdProvider.notifier).state = id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklists = ref.watch(checklistsProvider).value ?? const [];
    final templates = ref.watch(templatesProvider).value ?? const [];
    final selectedId = ref.watch(selectedChecklistIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              ...checklists.map(
                (c) => Consumer(builder: (context, ref, _) {
                  final items =
                      ref.watch(itemsForChecklistProvider(c.id)).value ??
                          const [];
                  final done = items.where((item) => item.isDone).length;
                  return ListTile(
                    leading: Icon(
                        c.spaceId == null
                            ? Icons.checklist
                            : Icons.group_outlined,
                        size: 18),
                    title: Text(c.title),
                    trailing: Text('$done/${items.length}'),
                    selected: c.id == selectedId,
                    onTap: () => ref
                        .read(selectedChecklistIdProvider.notifier)
                        .state = c.id,
                  );
                }),
              ),
              if (templates.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Шаблоны',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                ...templates.map(
                  (t) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.copy_all, size: 16),
                    title: Text(
                      t.title,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      tooltip: 'Создать список из шаблона',
                      onPressed: () => _createFromTemplate(ref, t.id, t.title),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.tonalIcon(
            onPressed: () => _createChecklist(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Новый список'),
          ),
        ),
      ],
    );
  }
}
