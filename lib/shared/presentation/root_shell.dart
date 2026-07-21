import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/settings/ui_settings.dart';
import '../../core/localization/app_localization.dart';
import '../../core/sync/supabase_config.dart';
import '../../core/sync/sync_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/checklists/presentation/checklists_screen.dart';
import '../../features/collaboration/data/collaboration_service.dart';
import '../../features/collaboration/presentation/share_dialog.dart';
import '../../features/filters/domain/filter_state.dart';
import '../../features/tasks/application/task_providers.dart';
import '../../features/tasks/presentation/task_list_screen.dart';
import '../../core/db/database.dart';
import '../../core/window/app_window_controller.dart';
import '../../features/tasks/presentation/compact_task_widget.dart';
import '../data/folder_repository.dart';
import '../widgets/dismissible_snack_bar.dart';

class RootShell extends ConsumerStatefulWidget {
  final VoidCallback? onExitOffline;
  const RootShell({super.key, this.onExitOffline});
  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _section = 0;
  bool _collapsed = false;

  void _showTasks({SmartFilter? filter, String? folderId}) {
    setState(() => _section = 0);
    if (filter != null || folderId != null) {
      ref.read(taskFilterProvider.notifier).update((state) => state.copyWith(
            smartFilter: filter ?? SmartFilter.all,
            folderId: folderId,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (AppWindowController.instance.isSupported) {
      return ValueListenableBuilder<bool>(
        valueListenable: AppWindowController.instance.compactMode,
        builder: (context, compact, _) =>
            compact ? const CompactTaskWidget() : _buildRegular(context, l10n),
      );
    }
    return _buildRegular(context, l10n);
  }

  Widget _buildRegular(BuildContext context, AppLocalizations l10n) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      final body = IndexedStack(index: _section, children: const [
        TaskListScreen(),
        ChecklistsScreen(),
      ]);
      if (!wide) {
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _section,
            onDestinationSelected: (value) {
              if (value == 2) {
                widget.onExitOffline?.call();
              } else {
                setState(() => _section = value);
              }
            },
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.task_alt),
                  label: l10n.text('Tasks', 'Задачи')),
              NavigationDestination(
                  icon: const Icon(Icons.checklist),
                  label: l10n.text('Lists', 'Списки')),
              if (widget.onExitOffline != null)
                NavigationDestination(
                    icon: const Icon(Icons.cloud_outlined),
                    label: l10n.text('Connect', 'Подключить')),
            ],
          ),
        );
      }
      return Scaffold(
          body: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: _collapsed ? 68 : 232,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: SafeArea(
              child: _DesktopSidebar(
            collapsed: _collapsed,
            section: _section,
            onCollapse: () => setState(() => _collapsed = !_collapsed),
            onTasks: _showTasks,
            onChecklists: () => setState(() => _section = 1),
            onExitOffline: widget.onExitOffline,
          )),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]));
    });
  }
}

class _DesktopSidebar extends ConsumerWidget {
  final bool collapsed;
  final int section;
  final VoidCallback onCollapse;
  final void Function({SmartFilter? filter, String? folderId}) onTasks;
  final VoidCallback onChecklists;
  final VoidCallback? onExitOffline;
  const _DesktopSidebar(
      {required this.collapsed,
      required this.section,
      required this.onCollapse,
      required this.onTasks,
      required this.onChecklists,
      this.onExitOffline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final filter = ref.watch(taskFilterProvider);
    final folders = ref.watch(foldersProvider).value ?? const [];
    final syncStatus = ref.watch(syncStatusProvider);
    final signedIn = SupabaseConfig.enabled &&
        Supabase.instance.client.auth.currentUser != null;
    Future<void> createFolder() async {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => const _CreateFolderDialog(),
      );
      if (name == null || name.isEmpty) return;
      final id = await ref.read(folderRepositoryProvider).createFolder(name);
      onTasks(folderId: id);
    }

    Future<void> applyDrop(Future<void> operation, String message) async {
      await operation;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context)
          .showSnackBar(dismissibleSnackBar(context, content: Text(message)));
    }

    Future<void> deleteFolder(Folder folder) async {
      final mode = await showDialog<FolderDeletionMode>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.delete_outline),
          title: Text(l10n.text(
              'Delete “${folder.name}”?', 'Удалить «${folder.name}»?')),
          content: Text(l10n.text(
            'Choose what to do with the tasks in this folder.',
            'Выберите, что сделать с задачами внутри папки.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.text('Cancel', 'Отмена')),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, FolderDeletionMode.keepTasks),
              child: Text(
                  l10n.text('Keep tasks', 'Удалить папку, задачи оставить')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () =>
                  Navigator.pop(dialogContext, FolderDeletionMode.deleteTasks),
              child: Text(
                  l10n.text('Delete with tasks', 'Удалить папку и задачи')),
            ),
          ],
        ),
      );
      if (mode == null) return;
      await ref
          .read(folderRepositoryProvider)
          .deleteFolder(folder.id, mode: mode);
      if (filter.folderId == folder.id) {
        onTasks(filter: SmartFilter.current);
      }
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        showCloseIcon: true,
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: messenger.hideCurrentSnackBar,
          child: Text(mode == FolderDeletionMode.keepTasks
              ? l10n.text('Folder deleted; tasks kept',
                  'Папка удалена, задачи сохранены')
              : l10n.text('Folder and its tasks deleted',
                  'Папка и вложенные задачи удалены')),
        ),
      ));
    }

    Future<void> syncNow() async {
      if (ref.read(syncStatusProvider).activity == SyncActivity.syncing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.text('Sync is already in progress',
                  'Синхронизация уже выполняется'))),
        );
        return;
      }
      await ref.read(syncEngineProvider).syncNow();
      if (!context.mounted) return;
      final status = ref.read(syncStatusProvider);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
        context,
        content: Text(status.activity == SyncActivity.error
            ? l10n.text('Sync error: ${status.error ?? 'unknown error'}',
                'Ошибка синхронизации: ${status.error ?? 'неизвестная ошибка'}')
            : l10n.text('Sync completed', 'Синхронизация завершена')),
      ));
    }

    Widget item(IconData icon, String label, VoidCallback tap,
            {bool selected = false,
            ValueChanged<Task>? onDrop,
            VoidCallback? onShare,
            VoidCallback? onDelete}) =>
        DragTarget<Task>(
            onAcceptWithDetails:
                onDrop == null ? null : (details) => onDrop(details.data),
            builder: (context, candidates, _) => Tooltip(
                message: collapsed ? label : '',
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Material(
                    color: candidates.isNotEmpty
                        ? Theme.of(context).colorScheme.primaryContainer
                        : selected
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: tap,
                      onSecondaryTap: onDelete,
                      child: SizedBox(
                          height: 42,
                          child: Row(children: [
                            SizedBox(width: 50, child: Icon(icon, size: 20)),
                            if (!collapsed)
                              Expanded(
                                  child: Text(label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                            if (!collapsed && onShare != null)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: l10n.text(
                                    'Share folder', 'Поделиться папкой'),
                                icon: const Icon(Icons.group_add_outlined,
                                    size: 17),
                                onPressed: onShare,
                              ),
                            if (!collapsed && onDelete != null)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip:
                                    l10n.text('Delete folder', 'Удалить папку'),
                                icon:
                                    const Icon(Icons.delete_outline, size: 17),
                                onPressed: onDelete,
                              ),
                          ])),
                    ),
                  ),
                )));
    return Column(children: [
      Stack(children: [
        item(Icons.auto_awesome_outlined, l10n.text('Current', 'Актуальные'),
            () => onTasks(filter: SmartFilter.current),
            selected: section == 0 &&
                filter.smartFilter == SmartFilter.current &&
                filter.folderId == null),
        Positioned(
            right: 1,
            top: 9,
            child: SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: onCollapse,
                    icon: Icon(
                        collapsed
                            ? Icons.keyboard_double_arrow_right
                            : Icons.keyboard_double_arrow_left,
                        size: 17),
                    tooltip: collapsed
                        ? l10n.text('Expand sidebar', 'Развернуть панель')
                        : l10n.text('Collapse sidebar', 'Свернуть панель')))),
      ]),
      item(Icons.today_outlined, l10n.text('Today', 'Сегодня'),
          () => onTasks(filter: SmartFilter.today),
          onDrop: (task) => applyDrop(
              ref.read(taskRepositoryProvider).updateTask(task.id,
                  dueDate: Value(DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day,
                      task.dueDate?.hour ?? 18,
                      task.dueDate?.minute ?? 0))),
              l10n.text('Task moved to Today', 'Задача перенесена на сегодня')),
          selected: section == 0 && filter.smartFilter == SmartFilter.today),
      item(Icons.priority_high, l10n.text('Important', 'Важные'),
          () => onTasks(filter: SmartFilter.important),
          selected:
              section == 0 && filter.smartFilter == SmartFilter.important),
      item(Icons.inbox_outlined, l10n.text('All tasks', 'Все задачи'),
          () => onTasks(filter: SmartFilter.all),
          selected: section == 0 &&
              filter.smartFilter == SmartFilter.all &&
              filter.folderId == null),
      item(Icons.schedule_outlined, l10n.text('Someday', 'Когда-нибудь'),
          () => onTasks(filter: SmartFilter.someday),
          onDrop: (task) => applyDrop(
              ref.read(taskRepositoryProvider).updateTask(task.id,
                  dueDate: const Value(null), basePriority: const Value(0)),
              l10n.text('Task moved to “Someday”',
                  'Задача перенесена в «Когда-нибудь»')),
          selected: section == 0 && filter.smartFilter == SmartFilter.someday),
      if (!collapsed)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 6, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.text('FOLDERS', 'ПАПКИ'),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                tooltip: l10n.text('New folder', 'Новая папка'),
                onPressed: createFolder,
              ),
            ],
          ),
        ),
      ...folders.map((folder) => item(
          folder.spaceId == null ? Icons.folder_outlined : Icons.folder_shared,
          folder.name,
          () => onTasks(folderId: folder.id),
          onDrop: (task) => applyDrop(
              ref
                  .read(taskRepositoryProvider)
                  .updateTask(task.id, folderId: Value(folder.id)),
              l10n.text('Task moved to “${folder.name}”',
                  'Задача перенесена в папку «${folder.name}»')),
          onShare: signedIn && folder.userId == SupabaseConfig.activeUserId
              ? () => showShareDialog(
                    context,
                    ref,
                    entityType: SharedEntityType.folder,
                    entityId: folder.id,
                    alreadyShared: folder.spaceId != null,
                  )
              : null,
          onDelete: () => deleteFolder(folder),
          selected: section == 0 && filter.folderId == folder.id)),
      const Spacer(),
      const Divider(),
      item(Icons.checklist, l10n.text('Lists', 'Списки'), onChecklists,
          selected: section == 1),
      item(Icons.settings_outlined, l10n.text('Settings', 'Настройки'),
          () => showUiSettingsDialog(context, ref)),
      if (signedIn)
        item(
          syncStatus.activity == SyncActivity.syncing
              ? Icons.sync
              : syncStatus.activity == SyncActivity.error
                  ? Icons.sync_problem
                  : Icons.cloud_done_outlined,
          syncStatus.activity == SyncActivity.syncing
              ? l10n.text('Syncing…', 'Синхронизация…')
              : syncStatus.activity == SyncActivity.error
                  ? l10n.text('Sync error', 'Ошибка синхронизации')
                  : l10n.text('Sync now', 'Синхронизировать сейчас'),
          syncNow,
        ),
      if (signedIn)
        item(Icons.logout, l10n.text('Sign out', 'Выйти'),
            () => Supabase.instance.client.auth.signOut()),
      if (!signedIn && onExitOffline != null)
        item(Icons.cloud_outlined,
            l10n.text('Connect cloud', 'Подключить облако'), onExitOffline!),
      const SizedBox(height: 8),
    ]);
  }
}

/// The route owns this controller and disposes it only after the dialog's
/// closing animation has fully unmounted its TextField.
class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.text('New folder', 'Новая папка')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.text('Folder name', 'Название папки'),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.text('Cancel', 'Отмена')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.text('Create', 'Создать')),
        ),
      ],
    );
  }
}
