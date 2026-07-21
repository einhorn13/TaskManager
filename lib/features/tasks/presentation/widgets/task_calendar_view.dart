import 'package:flutter/material.dart';

import '../../../../core/db/database.dart';
import '../../domain/recurrence.dart';

class _CalendarOccurrence {
  final Task task;
  final DateTime dueDate;
  final bool projected;
  const _CalendarOccurrence(this.task, this.dueDate, this.projected);
}

class TaskCalendarView extends StatefulWidget {
  final List<Task> tasks;
  final ValueChanged<Task> onTaskTap;
  const TaskCalendarView(
      {super.key, required this.tasks, required this.onTaskTap});

  @override
  State<TaskCalendarView> createState() => _TaskCalendarViewState();
}

class _TaskCalendarViewState extends State<TaskCalendarView> {
  late DateTime _month;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<_CalendarOccurrence> _tasksFor(DateTime day) {
    final occurrences = <_CalendarOccurrence>[];
    for (final task in widget.tasks) {
      if (task.dueDate == null) continue;
      if (_sameDay(task.dueDate!, day)) {
        occurrences.add(_CalendarOccurrence(task, task.dueDate!, false));
        continue;
      }
      if (task.status == 'done' || task.recurrenceRule == null) continue;
      final projected = RecurrenceRule.occurrenceOnDay(
          rule: task.recurrenceRule, anchor: task.dueDate, day: day);
      if (projected != null) {
        occurrences.add(_CalendarOccurrence(task, projected, true));
      }
    }
    occurrences.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return occurrences;
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - DateTime.monday;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final selectedTasks = _tasksFor(_selectedDay);
    final locale = MaterialLocalizations.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          IconButton(
            tooltip: 'Предыдущий месяц',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1)),
          ),
          Expanded(
            child: Text(
              locale.formatMonthYear(_month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _month = DateTime(now.year, now.month);
                _selectedDay = DateTime(now.year, now.month, now.day);
              });
            },
            child: const Text('Сегодня'),
          ),
          IconButton(
            tooltip: 'Следующий месяц',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final label in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
              Expanded(child: Center(child: Text(label))),
          ],
        ),
      ),
      Expanded(
        flex: 3,
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.35,
          ),
          itemCount: cellCount,
          itemBuilder: (context, index) {
            final dayNumber = index - leading + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }
            final day = DateTime(_month.year, _month.month, dayNumber);
            final tasks = _tasksFor(day);
            final selected = _sameDay(day, _selectedDay);
            final today = _sameDay(day, DateTime.now());
            return Padding(
              padding: const EdgeInsets.all(2),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedDay = day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: today
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$dayNumber',
                          style: TextStyle(
                              fontWeight:
                                  today || selected ? FontWeight.bold : null)),
                      const Spacer(),
                      if (tasks.isNotEmpty)
                        Wrap(spacing: 3, children: [
                          for (var i = 0; i < tasks.length.clamp(0, 4); i++)
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tasks[i].task.status == 'done'
                                        ? Theme.of(context).colorScheme.outline
                                        : Theme.of(context)
                                            .colorScheme
                                            .primary)),
                          if (tasks.length > 4)
                            Text('+${tasks.length - 4}',
                                style: Theme.of(context).textTheme.labelSmall),
                        ]),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
              '${locale.formatMediumDate(_selectedDay)} · ${selectedTasks.length}',
              style: Theme.of(context).textTheme.titleSmall),
        ),
      ),
      Expanded(
        flex: 2,
        child: selectedTasks.isEmpty
            ? const Center(child: Text('На этот день задач нет'))
            : ListView.builder(
                itemCount: selectedTasks.length,
                itemBuilder: (context, index) {
                  final occurrence = selectedTasks[index];
                  final task = occurrence.task;
                  return ListTile(
                    leading: Icon(task.status == 'done'
                        ? Icons.check_circle
                        : Icons.circle_outlined),
                    title: Text(task.title),
                    subtitle: Text(TimeOfDay.fromDateTime(occurrence.dueDate)
                        .format(context)),
                    trailing: occurrence.projected
                        ? const Tooltip(
                            message: 'Запланированное повторение',
                            child: Icon(Icons.repeat, size: 18),
                          )
                        : null,
                    onTap: () => widget.onTaskTap(task),
                  );
                },
              ),
      ),
    ]);
  }
}
