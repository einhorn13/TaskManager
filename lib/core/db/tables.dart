import 'package:drift/drift.dart';

mixin SyncColumns on Table {
  TextColumn get syncState =>
      text().withDefault(const Constant('pending'))(); // pending|synced|failed
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Папки/теги-иерархия. Одна папка на задачу (опционально).
class Folders extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  TextColumn get spaceId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Контекстные теги (@дом, @работа, @телефон) — многие-ко-многим, отдельно от папок.
/// Задел под будущую фичу, таблица уже здесь, чтобы не мигрировать схему позже.
class Tags extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskTags extends Table {
  TextColumn get taskId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

/// Основная сущность — задача.
/// Часть полей (parentTaskId, durationMinutes, recurrenceRule) относятся к фичам
/// из бэклога (подзадачи, длительность, повторы) — заложены сейчас, UI появится позже.
class Tasks extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get spaceId => text().nullable()();
  TextColumn get folderId => text().nullable().references(Folders, #id)();
  TextColumn get parentTaskId =>
      text().nullable().references(Tasks, #id)(); // подзадачи (v2)

  TextColumn get title => text()();
  TextColumn get description =>
      text().nullable()(); // используется и как "заметка"

  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get durationMinutes => integer().nullable()(); // длительность (v2)

  /// 0 = low, 1 = medium, 2 = high — базовый приоритет, заданный вручную
  IntColumn get basePriority => integer().withDefault(const Constant(1))();

  TextColumn get status =>
      text().withDefault(const Constant('todo'))(); // 'todo' | 'done'
  DateTimeColumn get completedAt => dateTime().nullable()();

  RealColumn get position => real().nullable()();

  /// Индивидуальный порог "истекает через N дней", переопределяет глобальный (см. filter_state.dart)
  IntColumn get expiringThresholdDaysOverride => integer().nullable()();

  /// RRULE-подобная строка, напр. 'FREQ=DAILY' — повторяющиеся задачи (v2)
  TextColumn get recurrenceRule => text().nullable()();

  /// Счётчик "отложить на 1 клик" — для будущей статистики
  IntColumn get snoozeCount => integer().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Заметки/вложения к задаче (фото, ссылка, файл) — задел под v2, не используется в MVP UI
class TaskAttachments extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get type => text()(); // 'file' | 'link' | 'photo'
  TextColumn get url => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Шаблоны чеклистов — переиспользуемые заготовки ("Вещи в путешествие")
class ChecklistTemplates extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ChecklistTemplateItems extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().references(ChecklistTemplates, #id)();
  TextColumn get text_ => text().named('text')();
  RealColumn get position => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Чеклисты — плоские, одноразовые по умолчанию, без приоритета/срока
class Checklists extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get spaceId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get templateId =>
      text().nullable().references(ChecklistTemplates, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ChecklistItems extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get checklistId => text().references(Checklists, #id)();
  TextColumn get text_ => text().named('text')();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  RealColumn get position => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Durable outbox будущего sync-engine. Запись создаётся в той же транзакции,
/// что и локальное изменение; сетевой адаптер будет подтверждать/повторять её.
class SyncOperations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // upsert|delete
  TextColumn get payload => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
}

class SyncMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}
