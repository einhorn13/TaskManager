import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';

class TaskNotificationService {
  TaskNotificationService._();
  static final instance = TaskNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {
      // tz.local (UTC fallback) remains usable when a platform cannot expose
      // an IANA timezone identifier.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windows = WindowsInitializationSettings(
      appName: 'Task Manager',
      appUserModelId: 'TaskManager.Desktop.App',
      guid: '9f9c4ee5-8f7b-4d78-a409-0f7a2f8f7a31',
    );
    await _plugin.initialize(
        settings: const InitializationSettings(
      android: android,
      windows: windows,
    ));

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
    }
    _initialized = true;
  }

  int _notificationId(String taskId) {
    var hash = 0x811c9dc5;
    for (final unit in taskId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> schedule(Task task) async {
    if (!_initialized) return;
    await cancel(task.id);
    final due = task.dueDate;
    if (task.status == 'done' ||
        task.deletedAt != null ||
        due == null ||
        !due.isAfter(DateTime.now())) {
      return;
    }

    await _plugin.zonedSchedule(
      id: _notificationId(task.id),
      title: 'Срок задачи наступил',
      body: task.title,
      payload: task.id,
      scheduledDate: tz.TZDateTime.from(due, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_due_dates',
          'Сроки задач',
          channelDescription: 'Напоминания в момент наступления срока задачи',
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancel(String taskId) async {
    if (!_initialized) return;
    await _plugin.cancel(id: _notificationId(taskId));
  }

  Future<void> rescheduleAll(List<Task> tasks) async {
    if (!_initialized) return;
    await _plugin.cancelAll();
    for (final task in tasks) {
      await schedule(task);
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }
}
