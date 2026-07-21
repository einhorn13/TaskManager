import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/providers.dart';
import '../data/checklist_repository.dart';

final checklistRepositoryProvider = Provider<ChecklistRepository>((ref) {
  return ChecklistRepository(ref.watch(databaseProvider));
});

final checklistsProvider = StreamProvider<List<Checklist>>((ref) {
  return ref.watch(checklistRepositoryProvider).watchChecklists();
});

final templatesProvider = StreamProvider<List<ChecklistTemplate>>((ref) {
  return ref.watch(checklistRepositoryProvider).watchTemplates();
});

/// id открытого чеклиста. null — ничего не выбрано (показываем список списков).
final selectedChecklistIdProvider = StateProvider<String?>((ref) => null);

/// Пункты конкретного чеклиста — family, чтобы не завязываться на выбранный id
/// и можно было в будущем открыть два чеклиста рядом, если понадобится.
final itemsForChecklistProvider =
    StreamProvider.family<List<ChecklistItem>, String>((ref, checklistId) {
  return ref.watch(checklistRepositoryProvider).watchItems(checklistId);
});

/// Сам чеклист (для заголовка) по id — производный от общего списка.
final checklistByIdProvider = Provider.family<Checklist?, String>((ref, id) {
  final list = ref.watch(checklistsProvider).value ?? const [];
  try {
    return list.firstWhere((c) => c.id == id);
  } catch (_) {
    return null;
  }
});
