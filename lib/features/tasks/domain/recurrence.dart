/// Простые правила повтора — сознательно не полноценный RRULE (BYDAY и т.п.),
/// чтобы не усложнять MVP. Хранится как текстовая строка в Tasks.recurrenceRule,
/// формат совместим с RRULE-подмножеством, так что при необходимости можно
/// расширить без миграции схемы (см. task_manager_plan.md).
enum RecurrenceFrequency { none, daily, weekly, monthly }

class RecurrenceRule {
  static const _dailyValue = 'FREQ=DAILY';
  static const _weeklyValue = 'FREQ=WEEKLY';
  static const _monthlyValue = 'FREQ=MONTHLY';

  static String? toStorageValue(RecurrenceFrequency freq) {
    switch (freq) {
      case RecurrenceFrequency.none:
        return null;
      case RecurrenceFrequency.daily:
        return _dailyValue;
      case RecurrenceFrequency.weekly:
        return _weeklyValue;
      case RecurrenceFrequency.monthly:
        return _monthlyValue;
    }
  }

  static RecurrenceFrequency fromStorageValue(String? value) {
    switch (value) {
      case _dailyValue:
        return RecurrenceFrequency.daily;
      case _weeklyValue:
        return RecurrenceFrequency.weekly;
      case _monthlyValue:
        return RecurrenceFrequency.monthly;
      default:
        return RecurrenceFrequency.none;
    }
  }

  static String label(RecurrenceFrequency freq) {
    switch (freq) {
      case RecurrenceFrequency.none:
        return 'Не повторяется';
      case RecurrenceFrequency.daily:
        return 'Каждый день';
      case RecurrenceFrequency.weekly:
        return 'Каждую неделю';
      case RecurrenceFrequency.monthly:
        return 'Каждый месяц';
    }
  }

  /// Дата следующего экземпляра. anchor — срок текущей (только что выполненной)
  /// задачи; если срока не было, используем текущий момент как якорь, чтобы у
  /// повторяющейся задачи в принципе появился срок.
  static DateTime? nextDueDate({
    required String? rule,
    required DateTime? anchor,
  }) {
    final freq = fromStorageValue(rule);
    if (freq == RecurrenceFrequency.none) return null;

    final base = anchor ?? DateTime.now();

    switch (freq) {
      case RecurrenceFrequency.none:
        return null;
      case RecurrenceFrequency.daily:
        return base.add(const Duration(days: 1));
      case RecurrenceFrequency.weekly:
        return base.add(const Duration(days: 7));
      case RecurrenceFrequency.monthly:
        final firstOfFollowingMonth = DateTime(base.year, base.month + 2, 1);
        final lastDay =
            firstOfFollowingMonth.subtract(const Duration(days: 1)).day;
        final day = base.day > lastDay ? lastDay : base.day;
        return DateTime(base.year, base.month + 1, day, base.hour, base.minute);
    }
  }

  static DateTime? occurrenceOnDay({
    required String? rule,
    required DateTime? anchor,
    required DateTime day,
  }) {
    if (anchor == null || fromStorageValue(rule) == RecurrenceFrequency.none) {
      return null;
    }
    final target = DateTime(day.year, day.month, day.day);
    final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
    if (target.isBefore(anchorDay)) return null;

    var occurrence = anchor;
    for (var i = 0; i < 2400; i++) {
      final occurrenceDay =
          DateTime(occurrence.year, occurrence.month, occurrence.day);
      if (occurrenceDay == target) return occurrence;
      if (occurrenceDay.isAfter(target)) return null;
      final next = nextDueDate(rule: rule, anchor: occurrence);
      if (next == null || !next.isAfter(occurrence)) return null;
      occurrence = next;
    }
    return null;
  }
}
