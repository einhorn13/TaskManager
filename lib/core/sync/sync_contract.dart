enum SyncEntityType {
  folder('folders'),
  tag('tags'),
  task('tasks'),
  attachment('task_attachments'),
  checklistTemplate('checklist_templates'),
  checklist('checklists'),
  checklistItem('checklist_items');

  final String table;
  const SyncEntityType(this.table);
  static SyncEntityType? fromName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

class SyncPushOperation {
  final SyncEntityType entityType;
  final String entityId;
  final Map<String, Object?> payload;
  const SyncPushOperation(this.entityType, this.entityId, this.payload);
}

class SyncPullResult {
  final List<Map<String, Object?>> changes;
  final DateTime serverTimestamp;
  const SyncPullResult(this.changes, this.serverTimestamp);
}

abstract interface class SyncRemoteGateway {
  Future<void> push(List<SyncPushOperation> operations);
  Future<SyncPullResult> pull({DateTime? changedAfter});
}
