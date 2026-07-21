import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localization.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../shared/widgets/dismissible_snack_bar.dart';
import '../data/collaboration_service.dart';

Future<void> showShareDialog(
  BuildContext context,
  WidgetRef ref, {
  required SharedEntityType entityType,
  required String entityId,
  required bool alreadyShared,
}) async {
  final controller = TextEditingController();
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final l10n = dialogContext.l10n;
        return AlertDialog(
          icon: const Icon(Icons.group_add_outlined),
          title: Text(l10n.text(
              alreadyShared ? 'Shared access' : 'Share with another user',
              alreadyShared ? 'Общий доступ' : 'Поделиться с пользователем')),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.text(
                    'Enter the email of a registered Task Manager user. The space supports you and one editor.',
                    'Введите email зарегистрированного пользователя Task Manager. Пространство поддерживает вас и одного редактора.')),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: Text(l10n.text('Cancel', 'Отмена')),
            ),
            FilledButton.icon(
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add_alt_1, size: 18),
              label: Text(l10n.text('Share', 'Поделиться')),
              onPressed: busy
                  ? null
                  : () async {
                      final email = controller.text.trim();
                      if (!email.contains('@')) {
                        setState(() => error = l10n.text(
                            'Enter a valid email', 'Введите корректный email'));
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await CollaborationService().share(
                          entityType: entityType,
                          entityId: entityId,
                          email: email,
                          syncEngine: ref.read(syncEngineProvider),
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(dismissibleSnackBar(
                          context,
                          content: Text(l10n.text(
                              'Shared access enabled', 'Общий доступ включён')),
                        ));
                      } catch (exception) {
                        if (!dialogContext.mounted) return;
                        setState(() {
                          busy = false;
                          error = exception.toString();
                        });
                      }
                    },
            ),
          ],
        );
      },
    ),
  );
  // showDialog completes before its reverse animation has fully unmounted the
  // TextField. Disposing here can make the last animation frame use a disposed
  // controller; the field removes its listeners and the local controller is
  // then garbage-collected with this invocation.
}
