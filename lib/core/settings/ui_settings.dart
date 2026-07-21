import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_backup_service.dart';
import '../localization/app_localization.dart';
import '../notifications/task_notification_service.dart';
import '../providers.dart';
import '../../shared/widgets/dismissible_snack_bar.dart';

class UiSettings {
  final double taskDetailWidth;
  final ListDensity listDensity;
  const UiSettings(
      {this.taskDetailWidth = 360, this.listDensity = ListDensity.normal});
  UiSettings copyWith({double? taskDetailWidth, ListDensity? listDensity}) =>
      UiSettings(
          taskDetailWidth: taskDetailWidth ?? this.taskDetailWidth,
          listDensity: listDensity ?? this.listDensity);
}

enum ListDensity { compact, normal, comfortable }

final uiSettingsProvider =
    StateProvider<UiSettings>((ref) => const UiSettings());

Future<void> showUiSettingsDialog(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  var width = ref.read(uiSettingsProvider).taskDetailWidth;
  var density = ref.read(uiSettingsProvider).listDensity;
  var languageCode = ref.read(appLocaleProvider).languageCode;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(l10n.text('Interface settings', 'Настройки интерфейса')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.text('Language', 'Язык')),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'en',
                        label: Text(l10n.text('English', 'Английский'))),
                    ButtonSegment(
                        value: 'ru',
                        label: Text(l10n.text('Russian', 'Русский'))),
                  ],
                  selected: {languageCode},
                  onSelectionChanged: (value) {
                    setDialogState(() => languageCode = value.first);
                    ref
                        .read(appLocaleProvider.notifier)
                        .setLocale(Locale(value.first));
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) showUiSettingsDialog(context, ref);
                    });
                  },
                ),
                const SizedBox(height: 20),
                Text(l10n.text('Details panel', 'Панель деталей')),
                const SizedBox(height: 8),
                Text(l10n.text('Width: ${width.round()} px',
                    'Ширина: ${width.round()} px')),
                Slider(
                  value: width,
                  min: 320,
                  max: 560,
                  divisions: 12,
                  onChanged: (value) {
                    setDialogState(() => width = value);
                    ref.read(uiSettingsProvider.notifier).state = UiSettings(
                        taskDetailWidth: value, listDensity: density);
                  },
                ),
                Text(
                  l10n.text(
                      'You can also resize it by dragging the panel’s left edge.',
                      'Ширину также можно менять перетаскиванием левого края панели.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Text(l10n.text('List density', 'Плотность списка')),
                const SizedBox(height: 8),
                SegmentedButton<ListDensity>(
                  segments: [
                    ButtonSegment(
                        value: ListDensity.compact,
                        label: Text(l10n.text('Compact', 'Плотно'))),
                    ButtonSegment(
                        value: ListDensity.normal,
                        label: Text(l10n.text('Normal', 'Обычно'))),
                    ButtonSegment(
                        value: ListDensity.comfortable,
                        label: Text(l10n.text('Comfortable', 'Свободно'))),
                  ],
                  selected: {density},
                  onSelectionChanged: (value) {
                    setDialogState(() => density = value.first);
                    ref.read(uiSettingsProvider.notifier).state = UiSettings(
                        taskDetailWidth: width, listDensity: density);
                  },
                ),
                const SizedBox(height: 24),
                Divider(color: Theme.of(context).colorScheme.errorContainer),
                const SizedBox(height: 12),
                Text(l10n.text('Data', 'Данные'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  l10n.text(
                      'Deletion only affects this device’s local database.',
                      'Удаление затрагивает только локальную базу этого устройства.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.save_alt),
                      label: Text(l10n.text(
                          'Create backup', 'Создать резервную копию')),
                      onPressed: () => _createDatabaseBackup(context, ref),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: Text(
                          l10n.text('Restore backup', 'Восстановить из копии')),
                      onPressed: () => _restoreDatabaseBackup(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(l10n.text(
                      'Reset local database', 'Сбросить локальную базу')),
                  onPressed: () async {
                    final confirmed = await _confirmDatabaseReset(context);
                    if (confirmed != true) return;
                    await ref.read(databaseProvider).clearAllLocalData();
                    await TaskNotificationService.instance.cancelAll();
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(dismissibleSnackBar(
                      context,
                      content: Text(l10n.text(
                          'Local database cleared', 'Локальная база очищена')),
                    ));
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              const defaults = UiSettings();
              ref.read(uiSettingsProvider.notifier).state = defaults;
              setDialogState(() {
                width = defaults.taskDetailWidth;
                density = defaults.listDensity;
              });
            },
            child: Text(l10n.text('Defaults', 'По умолчанию')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.text('Done', 'Готово')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _createDatabaseBackup(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  try {
    final destination =
        await DatabaseBackupService().createBackup(ref.read(databaseProvider));
    if (!context.mounted || destination == null) return;
    ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
      context,
      content: Text(
          l10n.text('Backup created successfully', 'Резервная копия создана')),
    ));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
      context,
      content: Text(l10n.text('Could not create backup: $error',
          'Не удалось создать резервную копию: $error')),
    ));
  }
}

Future<void> _restoreDatabaseBackup(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final service = DatabaseBackupService();
  try {
    final backup = await service.selectBackup();
    if (backup == null || !context.mounted) return;
    await service.validateBackup(backup);
    if (!context.mounted) return;
    final confirmed = await _confirmDatabaseRestore(context);
    if (confirmed != true || !context.mounted) return;

    final database = ref.read(databaseProvider);
    await database.close();
    try {
      await service.replaceDatabase(backup);
    } finally {
      ref.invalidate(databaseProvider);
    }
    await TaskNotificationService.instance.cancelAll();
    ref.read(databaseProvider);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
      context,
      content: Text(l10n.text('Database restored from backup',
          'База данных восстановлена из резервной копии')),
    ));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(dismissibleSnackBar(
      context,
      content: Text(l10n.text('Could not restore backup: $error',
          'Не удалось восстановить резервную копию: $error')),
    ));
  }
}

Future<bool?> _confirmDatabaseRestore(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.restore, size: 40),
      title: Text(
          l10n.text('Restore local database?', 'Восстановить локальную базу?')),
      content: Text(l10n.text(
          'Current local data will be replaced by the selected backup. Supabase data will not be changed. A later sync may merge newer server changes into the restored database.',
          'Текущие локальные данные будут заменены выбранной резервной копией. Данные в Supabase не изменятся. Последующая синхронизация может добавить в восстановленную базу более новые изменения с сервера.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.text('Cancel', 'Отмена')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.text('Restore', 'Восстановить')),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmDatabaseReset(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error, size: 40),
      title: Text(
          l10n.text('Delete all local data?', 'Удалить все локальные данные?')),
      content: Text(l10n.text(
          'All local tasks, folders, tags, attachments, checklists, templates, sync queue entries and notifications will be permanently deleted.\n\nSupabase data will not be deleted and may be downloaded again after signing in or syncing.',
          'Будут безвозвратно удалены все локальные задачи, папки, теги, вложения, чеклисты, шаблоны, очередь синхронизации и уведомления.\n\nДанные в Supabase не удаляются и могут снова загрузиться после входа или синхронизации.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.text('Cancel', 'Отмена')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.text('Delete all', 'Удалить всё')),
        ),
      ],
    ),
  );
}
