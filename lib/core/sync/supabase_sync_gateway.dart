import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_contract.dart';

class SupabaseSyncRemoteGateway implements SyncRemoteGateway {
  final SupabaseClient client;
  SupabaseSyncRemoteGateway(this.client);

  @override
  Future<void> push(List<SyncPushOperation> operations) async {
    for (final operation in operations) {
      await client.from(operation.entityType.table).upsert(operation.payload);
    }
  }

  @override
  Future<SyncPullResult> pull({DateTime? changedAfter}) async {
    final changes = <Map<String, Object?>>[];
    for (final entity in SyncEntityType.values) {
      dynamic query = client.from(entity.table).select();
      // Dependency roots are always pulled as a consistent snapshot. A client
      // may have retained a checkpoint while losing/restoring its local DB;
      // delta-only tasks would then reference parents that are absent locally.
      final requiresDependencySnapshot = entity == SyncEntityType.folder ||
          entity == SyncEntityType.tag ||
          entity == SyncEntityType.task ||
          entity == SyncEntityType.checklistTemplate ||
          entity == SyncEntityType.checklist;
      if (changedAfter != null && !requiresDependencySnapshot) {
        query = query.gt('updated_at', changedAfter.toUtc().toIso8601String());
      }
      final rows = await query.order('updated_at');
      for (final raw in rows as List) {
        changes.add(<String, Object?>{
          '_entity_type': entity.name,
          ...Map<String, Object?>.from(raw as Map),
        });
      }
    }
    return SyncPullResult(changes, DateTime.now().toUtc());
  }
}
