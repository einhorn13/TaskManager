import 'package:flutter/material.dart';

import '../../core/localization/app_localization.dart';

enum DurationUnit { minutes, hours, days }

String formatTaskDuration(BuildContext context, int minutes) {
  final l10n = context.l10n;
  if (minutes % 1440 == 0) {
    final value = minutes ~/ 1440;
    return l10n.text('$value d', '$value дн.');
  }
  if (minutes % 60 == 0) {
    final value = minutes ~/ 60;
    return l10n.text('$value h', '$value ч');
  }
  return l10n.text('$minutes min', '$minutes мин');
}

Future<int?> showDurationInputDialog(BuildContext context,
    {int? initialMinutes}) async {
  var unit = initialMinutes != null && initialMinutes % 1440 == 0
      ? DurationUnit.days
      : initialMinutes != null && initialMinutes % 60 == 0
          ? DurationUnit.hours
          : DurationUnit.minutes;
  final divisor = switch (unit) {
    DurationUnit.minutes => 1,
    DurationUnit.hours => 60,
    DurationUnit.days => 1440,
  };
  final controller = TextEditingController(
      text: initialMinutes == null ? '' : '${initialMinutes ~/ divisor}');
  String? error;
  final result = await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = context.l10n;
        return AlertDialog(
          title: Text(l10n.text('Task duration', 'Длительность задачи')),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.text('Value', 'Значение'),
                    errorText: error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<DurationUnit>(
                value: unit,
                items: [
                  DropdownMenuItem(
                      value: DurationUnit.minutes,
                      child: Text(l10n.text('minutes', 'минуты'))),
                  DropdownMenuItem(
                      value: DurationUnit.hours,
                      child: Text(l10n.text('hours', 'часы'))),
                  DropdownMenuItem(
                      value: DurationUnit.days,
                      child: Text(l10n.text('days', 'дни'))),
                ],
                onChanged: (value) =>
                    value == null ? null : setState(() => unit = value),
              ),
            ],
          ),
          actions: [
            if (initialMinutes != null)
              TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: Text(l10n.text('Clear', 'Очистить')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.text('Cancel', 'Отмена')),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value <= 0) {
                  setState(() => error = l10n.text('Enter a positive integer',
                      'Введите целое число больше 0'));
                  return;
                }
                final multiplier = switch (unit) {
                  DurationUnit.minutes => 1,
                  DurationUnit.hours => 60,
                  DurationUnit.days => 1440,
                };
                Navigator.pop(context, value * multiplier);
              },
              child: Text(l10n.text('Apply', 'Применить')),
            ),
          ],
        );
      },
    ),
  );
  // The dialog Future completes while the closing animation can still build
  // its TextField. Let the local controller be collected after the route is
  // unmounted instead of disposing it too early.
  return result;
}
