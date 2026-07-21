import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

class DatabaseBackupException implements Exception {
  final String message;
  const DatabaseBackupException(this.message);

  @override
  String toString() => message;
}

class DatabaseBackupService {
  static const _databaseName = 'task_manager.sqlite';
  static const _requiredTables = {
    'folders',
    'tags',
    'task_tags',
    'tasks',
    'task_attachments',
    'checklist_templates',
    'checklist_template_items',
    'checklists',
    'checklist_items',
    'sync_operations',
    'sync_metadata',
  };

  Future<String?> createBackup(AppDatabase database) async {
    final tempDirectory = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final tempFile = File(
        p.join(tempDirectory.path, 'task_manager_backup_$timestamp.sqlite'));

    try {
      await writeBackup(database, tempFile);
      final bytes = await tempFile.readAsBytes();
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save database backup',
        fileName: 'task_manager_backup_$timestamp.sqlite',
        type: FileType.custom,
        allowedExtensions: const ['sqlite'],
        bytes: bytes,
      );
      if (destination != null &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await File(destination).writeAsBytes(bytes, flush: true);
      }
      return destination;
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<void> writeBackup(AppDatabase database, File destination) async {
    if (await destination.exists()) await destination.delete();
    await database.customStatement('VACUUM INTO ?', [destination.path]);
  }

  Future<File?> selectBackup() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select database backup',
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db', 'backup'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  Future<void> validateBackup(File backup) async {
    bool usable;
    try {
      usable = await backup.exists() && await backup.length() > 0;
    } catch (_) {
      usable = false;
    }
    if (!usable) {
      throw const DatabaseBackupException(
          'The backup file is empty or missing.');
    }

    Database? sqliteDatabase;
    try {
      sqliteDatabase = sqlite3.open(backup.path, mode: OpenMode.readOnly);
      final integrity = sqliteDatabase
          .select('PRAGMA integrity_check')
          .first
          .values
          .first
          .toString();
      if (integrity.toLowerCase() != 'ok') {
        throw const DatabaseBackupException(
            'The backup is damaged (integrity check failed).');
      }

      final version = sqliteDatabase.userVersion;
      if (version != AppDatabase.currentSchemaVersion) {
        throw DatabaseBackupException(
            'Unsupported backup schema version: $version. Expected ${AppDatabase.currentSchemaVersion}.');
      }

      final tables = sqliteDatabase
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'] as String)
          .toSet();
      if (!_requiredTables.every(tables.contains)) {
        throw const DatabaseBackupException(
            'The selected file is not a Task Manager backup.');
      }
    } on DatabaseBackupException {
      rethrow;
    } catch (_) {
      throw const DatabaseBackupException(
          'The selected file is not a valid SQLite backup.');
    } finally {
      sqliteDatabase?.close();
    }
  }

  Future<void> replaceDatabase(File backup) async {
    final target = await databaseFile();
    if (p.equals(p.absolute(backup.path), p.absolute(target.path))) {
      throw const DatabaseBackupException(
          'Choose a backup file, not the active application database.');
    }
    final rollback = File('${target.path}.before_restore');
    final wal = File('${target.path}-wal');
    final shm = File('${target.path}-shm');

    if (await rollback.exists()) await rollback.delete();
    if (await target.exists()) await target.copy(rollback.path);
    try {
      await backup.copy(target.path);
      if (await wal.exists()) await wal.delete();
      if (await shm.exists()) await shm.delete();
    } catch (_) {
      if (await rollback.exists()) await rollback.copy(target.path);
      rethrow;
    } finally {
      if (await rollback.exists()) await rollback.delete();
    }
  }

  static Future<File> databaseFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _databaseName));
  }
}
