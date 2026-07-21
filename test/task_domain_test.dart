import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/tasks/domain/recurrence.dart';
import 'package:task_manager/features/tasks/domain/task_priority.dart';
import 'package:task_manager/features/filters/domain/filter_state.dart';

void main() {
  group('RecurrenceRule', () {
    test('monthly recurrence clamps to last day of shorter month', () {
      final next = RecurrenceRule.nextDueDate(
        rule: 'FREQ=MONTHLY',
        anchor: DateTime(2025, 1, 31, 10, 30),
      );
      expect(next, DateTime(2025, 2, 28, 10, 30));
    });

    test('leap year is respected', () {
      final next = RecurrenceRule.nextDueDate(
        rule: 'FREQ=MONTHLY',
        anchor: DateTime(2024, 1, 31),
      );
      expect(next, DateTime(2024, 2, 29));
    });

    test('calendar projects daily occurrences without creating records', () {
      final occurrence = RecurrenceRule.occurrenceOnDay(
        rule: 'FREQ=DAILY',
        anchor: DateTime(2026, 7, 1, 9, 15),
        day: DateTime(2026, 7, 19),
      );
      expect(occurrence, DateTime(2026, 7, 19, 9, 15));
    });

    test('calendar projection follows monthly clamp sequence', () {
      final occurrence = RecurrenceRule.occurrenceOnDay(
        rule: 'FREQ=MONTHLY',
        anchor: DateTime(2026, 1, 31, 18),
        day: DateTime(2026, 3, 28),
      );
      expect(occurrence, DateTime(2026, 3, 28, 18));
    });
  });

  group('TaskPriorityEngine', () {
    const engine = TaskPriorityEngine();

    test('overdue always wins', () {
      final priority = engine.effectivePriority(
        basePriority: 0,
        dueDate: DateTime(2025, 1, 1),
        createdAt: DateTime(2024, 12, 1),
        now: DateTime(2025, 1, 2),
      );
      expect(priority, EffectivePriority.overdue);
    });

    test('same-day task is at least high', () {
      final priority = engine.effectivePriority(
        basePriority: 0,
        dueDate: DateTime(2025, 1, 2, 18),
        createdAt: DateTime(2025, 1, 1),
        now: DateTime(2025, 1, 2, 9),
      );
      expect(priority, EffectivePriority.high);
    });
  });

  group('TaskFilter', () {
    test('folder can be explicitly reset without losing other filters', () {
      const filter = TaskFilter(
        smartFilter: SmartFilter.important,
        folderId: 'folder-1',
        tagIds: {'tag-1'},
        searchText: 'отчёт',
      );
      final reset = filter.copyWith(folderId: null);
      expect(reset.folderId, isNull);
      expect(reset.smartFilter, SmartFilter.important);
      expect(reset.tagIds, {'tag-1'});
      expect(reset.searchText, 'отчёт');
    });
  });
}
