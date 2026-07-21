import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/supabase_config.dart';
import '../../../core/sync/sync_engine.dart';

enum SharedEntityType { folder, task, checklist }

class CollaborationService {
  Future<void> share({
    required SharedEntityType entityType,
    required String entityId,
    required String email,
    required SyncEngine syncEngine,
  }) async {
    if (!SupabaseConfig.enabled ||
        Supabase.instance.client.auth.currentUser == null) {
      throw StateError('Sign in to Supabase before sharing.');
    }
    await syncEngine.syncNow();
    await Supabase.instance.client.rpc('share_with_registered_user', params: {
      'p_entity_type': entityType.name,
      'p_entity_id': entityId,
      'p_email': email.trim(),
    });
    await syncEngine.syncNow();
  }
}
