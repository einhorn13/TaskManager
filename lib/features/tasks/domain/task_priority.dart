/// Уровни эффективного приоритета. Overdue — отдельный, самый высокий уровень,
/// форсируется независимо от base_priority (см. task_manager_plan.md, раздел 4).
enum EffectivePriority { low, medium, high, overdue }

class TaskPriorityEngine {
  const TaskPriorityEngine();

  /// Порог "истекающая" по умолчанию: адаптивный.
  /// - 3 дня, если исходный срок задачи был поставлен больше чем за неделю до дедлайна
  /// - 1 день, если исходный срок был меньше недели
  /// Может быть переопределён индивидуально на уровне задачи (см. Tasks.expiringThresholdDaysOverride).
  int defaultExpiringThresholdDays({
    required DateTime createdAt,
    required DateTime dueDate,
  }) {
    final totalWindow = dueDate.difference(createdAt);
    return totalWindow.inDays > 7 ? 3 : 1;
  }

  /// Чистая функция от текущего времени — пересчитывается на лету при отрисовке,
  /// без похода на сервер. base_priority: 0=low, 1=medium, 2=high.
  EffectivePriority effectivePriority({
    required int basePriority,
    required DateTime? dueDate,
    required DateTime createdAt,
    int? expiringThresholdOverrideDays,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final base = _fromInt(basePriority);

    if (dueDate == null) return base;

    if (dueDate.isBefore(currentTime)) {
      return EffectivePriority.overdue;
    }

    final daysUntilDue = dueDate.difference(currentTime).inHours / 24;

    if (_isSameDay(dueDate, currentTime)) {
      return _max(base, EffectivePriority.high);
    }

    final threshold = expiringThresholdOverrideDays ??
        defaultExpiringThresholdDays(createdAt: createdAt, dueDate: dueDate);

    if (daysUntilDue <= threshold) {
      return _bumpOnce(base);
    }

    return base;
  }

  bool isSomedayCandidate(
      {required int basePriority, required DateTime? dueDate}) {
    // "Когда-нибудь": без срока и самый низкий приоритет — чистый смарт-фильтр,
    // схема для этого не менялась (см. task_manager_plan.md, раздел "Заложено в архитектуру").
    return dueDate == null && basePriority == 0;
  }

  EffectivePriority _fromInt(int value) {
    switch (value) {
      case 0:
        return EffectivePriority.low;
      case 2:
        return EffectivePriority.high;
      default:
        return EffectivePriority.medium;
    }
  }

  EffectivePriority _bumpOnce(EffectivePriority p) {
    switch (p) {
      case EffectivePriority.low:
        return EffectivePriority.medium;
      case EffectivePriority.medium:
      case EffectivePriority.high:
        return EffectivePriority.high;
      case EffectivePriority.overdue:
        return EffectivePriority.overdue;
    }
  }

  EffectivePriority _max(EffectivePriority a, EffectivePriority b) {
    return a.index >= b.index ? a : b;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
