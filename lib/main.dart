import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/notifications/task_notification_service.dart';
import 'core/sync/supabase_config.dart';
import 'core/window/app_window_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    initializeDateFormatting('en'),
    initializeDateFormatting('ru'),
  ]);
  await AppWindowController.instance.initialize();
  try {
    await TaskNotificationService.instance.initialize();
  } catch (_) {
    // Notifications are optional; database and UI must remain available when
    // the platform notification subsystem cannot initialize.
  }
  if (SupabaseConfig.enabled) {
    await Supabase.initialize(
        url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  }
  runApp(const ProviderScope(child: TaskManagerApp()));
}
