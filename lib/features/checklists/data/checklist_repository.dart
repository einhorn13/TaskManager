import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/database.dart';
import '../../../core/sync/supabase_config.dart';

const _uuid = Uuid();

/// Чеклисты — намеренно плоские (см. task_manager_plan.md, раздел 5): без
/// приоритета и вложенности, просто текст + галочка. Шаблоны — отдельная
/// сущность, из которой можно создать новый чеклист с предзаполненными пунктами.
class ChecklistRepository {
  final AppDatabase db;

  ChecklistRepository(this.db);

  Stream<List<Checklist>> watchChecklists() {
    return (db.select(db.checklists)
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
        .watch();
  }

  Stream<List<ChecklistTemplate>> watchTemplates() {
    return (db.select(db.checklistTemplates)
          ..where((t) => t.deletedAt.isNull()))
        .watch();
  }

  Stream<List<ChecklistItem>> watchItems(String checklistId) {
    return (db.select(db.checklistItems)
          ..where(
              (i) => i.checklistId.equals(checklistId) & i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.asc(i.position)]))
        .watch();
  }

  /// Создаёт чеклист. Если передан templateId — копирует пункты шаблона
  /// (все невыполненные, шаблон не меняется).
  Future<String> createChecklist(String title, {String? templateId}) async {
    final id = _uuid.v4();
    await db.into(db.checklists).insert(
          ChecklistsCompanion.insert(
            id: id,
            userId: SupabaseConfig.activeUserId,
            title: title,
            templateId:
                templateId == null ? const Value.absent() : Value(templateId),
          ),
        );

    if (templateId != null) {
      final templateItems = await (db.select(db.checklistTemplateItems)
            ..where((i) => i.templateId.equals(templateId))
            ..orderBy([(i) => OrderingTerm.asc(i.position)]))
          .get();

      for (var i = 0; i < templateItems.length; i++) {
        await db.into(db.checklistItems).insert(
              ChecklistItemsCompanion.insert(
                id: _uuid.v4(),
                checklistId: id,
                text_: templateItems[i].text_,
                position: Value(i.toDouble()),
              ),
            );
      }
    }
    return id;
  }

  Future<void> addItem(String checklistId, String text) async {
    final existing = await (db.select(db.checklistItems)
          ..where((i) => i.checklistId.equals(checklistId)))
        .get();
    await db.into(db.checklistItems).insert(
          ChecklistItemsCompanion.insert(
            id: _uuid.v4(),
            checklistId: checklistId,
            text_: text,
            position: Value(existing.length.toDouble()),
          ),
        );
  }

  Future<void> renameChecklist(String id, String title) async {
    await (db.update(db.checklists)..where((c) => c.id.equals(id))).write(
      ChecklistsCompanion(
          title: Value(title.trim()), syncState: const Value('pending')),
    );
  }

  Future<void> moveItem(String checklistId, String itemId, int delta) async {
    final items = await (db.select(db.checklistItems)
          ..where((i) => i.checklistId.equals(checklistId))
          ..orderBy([(i) => OrderingTerm.asc(i.position)]))
        .get();
    final index = items.indexWhere((i) => i.id == itemId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= items.length) return;
    await db.transaction(() async {
      await (db.update(db.checklistItems)
            ..where((i) => i.id.equals(items[index].id)))
          .write(ChecklistItemsCompanion(
              position: Value(target.toDouble()),
              syncState: const Value('pending')));
      await (db.update(db.checklistItems)
            ..where((i) => i.id.equals(items[target].id)))
          .write(ChecklistItemsCompanion(
              position: Value(index.toDouble()),
              syncState: const Value('pending')));
    });
  }

  Future<void> toggleItem(String itemId, bool done) async {
    await (db.update(db.checklistItems)..where((i) => i.id.equals(itemId)))
        .write(ChecklistItemsCompanion(
            isDone: Value(done), syncState: const Value('pending')));
  }

  Future<void> deleteItem(String itemId) async {
    await (db.update(db.checklistItems)..where((i) => i.id.equals(itemId)))
        .write(ChecklistItemsCompanion(
      deletedAt: Value(DateTime.now()),
      syncState: const Value('pending'),
    ));
  }

  Future<void> deleteChecklist(String checklistId) async {
    await db.transaction(() async {
      final now = DateTime.now();
      await (db.update(db.checklistItems)
            ..where((i) => i.checklistId.equals(checklistId)))
          .write(ChecklistItemsCompanion(
        deletedAt: Value(now),
        syncState: const Value('pending'),
      ));
      await (db.update(db.checklists)..where((c) => c.id.equals(checklistId)))
          .write(ChecklistsCompanion(
        deletedAt: Value(now),
        syncState: const Value('pending'),
      ));
    });
  }

  /// Сохранить текущие пункты чеклиста как переиспользуемый шаблон
  /// (см. task_manager_plan.md, вопрос №3 — "Вещи в путешествие" и т.п.)
  Future<void> saveAsTemplate(String checklistId, String templateTitle) async {
    final templateId = _uuid.v4();
    await db.into(db.checklistTemplates).insert(
          ChecklistTemplatesCompanion.insert(
            id: templateId,
            userId: SupabaseConfig.activeUserId,
            title: templateTitle,
          ),
        );

    final items = await (db.select(db.checklistItems)
          ..where((i) => i.checklistId.equals(checklistId))
          ..orderBy([(i) => OrderingTerm.asc(i.position)]))
        .get();

    for (var i = 0; i < items.length; i++) {
      await db.into(db.checklistTemplateItems).insert(
            ChecklistTemplateItemsCompanion.insert(
              id: _uuid.v4(),
              templateId: templateId,
              text_: items[i].text_,
              position: Value(i.toDouble()),
            ),
          );
    }
  }
}
