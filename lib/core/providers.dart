import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'notifications/task_notification_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  unawaited((db.select(db.tasks)..where((t) => t.deletedAt.isNull()))
      .get()
      .then(TaskNotificationService.instance.rescheduleAll));
  ref.onDispose(db.close);
  return db;
});
