// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/shared/widgets/quick_add_bar.dart';
import 'package:task_manager/features/tasks/presentation/widgets/due_date_dialog.dart';
import 'package:flutter/material.dart';

void main() {
  test('quick add parses date marker and priority', () {
    final result = parseQuickAdd(
      'Купить молоко завтра !высокий',
      now: DateTime(2026, 7, 13, 23, 59),
    );
    expect(result.title, 'Купить молоко');
    expect(result.basePriority, 2);
    expect(result.dueDate, DateTime(2026, 7, 14));
  });

  test('due date defaults to the end of day when time is omitted', () {
    final result = combineDueDate(DateTime(2026, 7, 13), null);
    expect(result, DateTime(2026, 7, 13, 23, 59));
  });

  test('due date keeps an explicitly selected time', () {
    final result = combineDueDate(
      DateTime(2026, 7, 13),
      const TimeOfDay(hour: 14, minute: 35),
    );
    expect(result, DateTime(2026, 7, 13, 14, 35));
  });

  test('due time parser rejects invalid values', () {
    expect(parseDueTime('9:05'), const TimeOfDay(hour: 9, minute: 5));
    expect(parseDueTime('24:00'), isNull);
    expect(parseDueTime('12:60'), isNull);
  });
}
