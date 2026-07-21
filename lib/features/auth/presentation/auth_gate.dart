import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/supabase_config.dart';
import '../../../shared/presentation/root_shell.dart';
import 'login_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});
  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!SupabaseConfig.enabled) return;
    _session = Supabase.instance.client.auth.currentSession;
    _subscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      setState(() => _session = event.session);
      if (event.session != null) {
        ref.read(syncEngineProvider).startForUser(event.session!.user.id);
      } else {
        ref.read(syncEngineProvider).stop();
      }
    });
    if (_session != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => ref.read(syncEngineProvider).startForUser(_session!.user.id));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session != null) {
      ref.read(syncEngineProvider).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) => _offline || _session != null
      ? RootShell(
          onExitOffline:
              _offline ? () => setState(() => _offline = false) : null,
        )
      : LoginScreen(
          supabaseAvailable: SupabaseConfig.enabled,
          onOffline: () => setState(() => _offline = true),
        );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }
}
