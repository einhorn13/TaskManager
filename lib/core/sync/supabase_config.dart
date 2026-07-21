import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get enabled => url.isNotEmpty && anonKey.isNotEmpty;
  static String get activeUserId => enabled
      ? (Supabase.instance.client.auth.currentUser?.id ?? 'local')
      : 'local';
}
