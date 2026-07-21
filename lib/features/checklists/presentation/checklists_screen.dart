import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localization.dart';
import '../application/checklist_providers.dart';
import 'widgets/checklist_items_view.dart';
import 'widgets/checklist_sidebar.dart';

/// Тот же порог 700px, что и в task_list_screen.dart — на широких экранах
/// сайдбар и содержимое чеклиста показываются рядом, на узких (Android) —
/// как отдельные "страницы" списка и деталей.
class ChecklistsScreen extends ConsumerWidget {
  const ChecklistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedChecklistIdProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;

        if (isWide) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.text('Lists', 'Списки'))),
            body: Row(
              children: [
                const SizedBox(width: 260, child: ChecklistSidebar()),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selectedId == null
                      ? Center(
                          child: Text(context.l10n.text(
                              'Select a list on the left',
                              'Выбери список слева')))
                      : ChecklistItemsView(checklistId: selectedId),
                ),
              ],
            ),
          );
        }

        if (selectedId == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.text('Lists', 'Списки'))),
            body: const ChecklistSidebar(),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () =>
                  ref.read(selectedChecklistIdProvider.notifier).state = null,
            ),
          ),
          body: ChecklistItemsView(checklistId: selectedId),
        );
      },
    );
  }
}
