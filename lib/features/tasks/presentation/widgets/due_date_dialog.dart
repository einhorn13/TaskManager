import 'package:flutter/material.dart';

DateTime combineDueDate(DateTime date, TimeOfDay? time) => DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 23,
      time?.minute ?? 59,
    );

TimeOfDay? parseDueTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

Future<DateTime?> showDueDateDialog(
  BuildContext context, {
  DateTime? initialDate,
}) async {
  final now = DateTime.now();
  final initial = initialDate ?? now;
  var selectedDate = DateTime(initial.year, initial.month, initial.day);
  final timeController = TextEditingController(
    text: initialDate == null
        ? ''
        : '${initial.hour.toString().padLeft(2, '0')}:'
            '${initial.minute.toString().padLeft(2, '0')}',
  );
  String? timeError;

  final result = await showDialog<DateTime>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Срок задачи'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CalendarDatePicker(
                  initialDate: selectedDate,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 5),
                  onDateChanged: (value) =>
                      setState(() => selectedDate = value),
                ),
                const Divider(),
                TextField(
                  controller: timeController,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: 'Время (необязательно)',
                    hintText: '23:59 — конец дня',
                    errorText: timeError,
                    prefixIcon: const Icon(Icons.schedule_outlined),
                    suffixIcon: timeController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Не указывать время',
                            onPressed: () => setState(timeController.clear),
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() => timeError = null),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final rawTime = timeController.text.trim();
              final time = rawTime.isEmpty ? null : parseDueTime(rawTime);
              if (rawTime.isNotEmpty && time == null) {
                setState(() => timeError = 'Введите время в формате ЧЧ:ММ');
                return;
              }
              Navigator.pop(context, combineDueDate(selectedDate, time));
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
  timeController.dispose();
  return result;
}
