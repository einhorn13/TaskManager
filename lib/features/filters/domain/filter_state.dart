/// Готовые смарт-фильтры. Добавление нового — это новое значение enum + один
/// предикат в TaskFilter.matches, а не правки в UI-компонентах (см. план, раздел 5).
enum SmartFilter { current, today, expiring, important, someday, all }

/// Составное состояние фильтра — задачи, теги и папки комбинируются, а не
/// взаимоисключают друг друга. Это и есть архитектурный задел под
/// "быстрый комбинированный фильтр" из бэклога.
/// Сентинел, чтобы отличить "параметр не передан" от "передан null" —
/// иначе copyWith(folderId: null) с `??` никогда не сбросит папку.
const _unset = Object();

class TaskFilter {
  final SmartFilter smartFilter;
  final String? folderId;
  final Set<String> tagIds;
  final String searchText;

  const TaskFilter({
    this.smartFilter = SmartFilter.current,
    this.folderId,
    this.tagIds = const {},
    this.searchText = '',
  });

  TaskFilter copyWith({
    SmartFilter? smartFilter,
    Object? folderId = _unset,
    Set<String>? tagIds,
    String? searchText,
  }) {
    return TaskFilter(
      smartFilter: smartFilter ?? this.smartFilter,
      folderId:
          identical(folderId, _unset) ? this.folderId : folderId as String?,
      tagIds: tagIds ?? this.tagIds,
      searchText: searchText ?? this.searchText,
    );
  }
}
