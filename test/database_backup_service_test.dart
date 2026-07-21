import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:task_manager/core/db/database.dart';
import 'package:task_manager/core/db/database_backup_service.dart';
import 'package:task_manager/features/tasks/data/task_repository.dart';

void main() {
  test('backup is valid and contains committed local data', () async {
    final directory = await Directory.systemTemp.createTemp('task_backup_test');
    final source = File('${directory.path}/source.sqlite');
    final backup = File('${directory.path}/backup.sqlite');
    final database = AppDatabase.forTesting(NativeDatabase(source));

    try {
      await TaskRepository(database).addTask(title: 'Long-term local task');
      final service = DatabaseBackupService();
      await service.writeBackup(database, backup);
      await service.validateBackup(backup);

      final restored = sqlite3.open(backup.path, mode: OpenMode.readOnly);
      try {
        final titles = restored
            .select('SELECT title FROM tasks')
            .map((row) => row['title'])
            .toList();
        expect(titles, contains('Long-term local task'));
      } finally {
        restored.close();
      }
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test('validation rejects a non-database file', () async {
    final directory = await Directory.systemTemp.createTemp('task_backup_test');
    final invalid = File('${directory.path}/invalid.sqlite');
    await invalid.writeAsString('not a database');
    try {
      await expectLater(
        DatabaseBackupService().validateBackup(invalid),
        throwsA(isA<DatabaseBackupException>()),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
