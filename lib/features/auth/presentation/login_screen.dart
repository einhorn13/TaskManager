import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remembered_accounts.dart';

enum _AuthMode { login, register }

class LoginScreen extends StatefulWidget {
  final VoidCallback onOffline;
  final bool supabaseAvailable;
  const LoginScreen(
      {super.key, required this.onOffline, this.supabaseAvailable = true});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordRepeat = TextEditingController();
  List<String> _accounts = const [];
  _AuthMode _mode = _AuthMode.login;
  bool _loading = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await RememberedAccounts.load();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      if (_email.text.isEmpty && accounts.isNotEmpty) {
        _email.text = accounts.first;
        _loadPassword(accounts.first);
      }
    });
  }

  Future<void> _selectAccount(String email) async {
    setState(() {
      _email.text = email;
      _error = null;
    });
    await _loadPassword(email);
  }

  Future<void> _loadPassword(String email) async {
    final password = await RememberedAccounts.passwordFor(email);
    if (!mounted || _email.text != email) return;
    setState(() => _password.text = password ?? '');
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _message = null;
      _password.clear();
      _passwordRepeat.clear();
      if (mode == _AuthMode.register) _email.clear();
    });
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || _password.text.isEmpty) return;
    if (_mode == _AuthMode.register && _password.text != _passwordRepeat.text) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    if (_mode == _AuthMode.register && _password.text.length < 6) {
      setState(() => _error = 'Пароль должен содержать минимум 6 символов');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      if (_mode == _AuthMode.login) {
        await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: _password.text);
        await RememberedAccounts.add(email, _password.text);
      } else {
        final response = await Supabase.instance.client.auth
            .signUp(email: email, password: _password.text);
        await RememberedAccounts.add(email, _password.text);
        if (response.session == null && mounted) {
          _setMode(_AuthMode.login);
          _email.text = email;
          setState(() => _message =
              'Аккаунт создан. Подтверди email по ссылке из письма, затем войди.');
        }
      }
      await _loadAccounts();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не удалось подключиться к Supabase');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _forget(String email) async {
    await RememberedAccounts.remove(email);
    if (_email.text == email) _email.clear();
    await _loadAccounts();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
              child: Padding(
            padding: const EdgeInsets.all(28),
            child: AutofillGroup(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Icon(Icons.check_circle,
                      size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                      _mode == _AuthMode.login
                          ? 'Вход в Task Manager'
                          : 'Новый пользователь',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  if (_mode == _AuthMode.login && _accounts.isNotEmpty) ...[
                    Text('Пользователи на этом устройстве',
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 6),
                    Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _accounts
                            .map((email) => InputChip(
                                  avatar: const Icon(Icons.person_outline,
                                      size: 17),
                                  label: Text(email),
                                  selected: _email.text == email,
                                  onPressed: () => _selectAccount(email),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: () => _forget(email),
                                ))
                            .toList()),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                      controller: _email,
                      autofocus: _accounts.isEmpty,
                      readOnly: false,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: Icon(Icons.lock_outline)),
                      onSubmitted:
                          _mode == _AuthMode.login ? (_) => _submit() : null),
                  if (_mode == _AuthMode.register) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: _passwordRepeat,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Повтори пароль',
                            prefixIcon: Icon(Icons.lock_reset)),
                        onSubmitted: (_) => _submit()),
                  ],
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_message != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_message!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary))),
                  const SizedBox(height: 20),
                  if (!widget.supabaseAvailable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Supabase не настроен в supabase.env. Доступен offline-режим.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  FilledButton.icon(
                      onPressed: _loading || !widget.supabaseAvailable
                          ? null
                          : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(_mode == _AuthMode.login
                              ? Icons.login
                              : Icons.person_add),
                      label: Text(_mode == _AuthMode.login
                          ? 'Войти'
                          : 'Создать аккаунт')),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loading || !widget.supabaseAvailable
                        ? null
                        : () => _setMode(_mode == _AuthMode.login
                            ? _AuthMode.register
                            : _AuthMode.login),
                    icon: Icon(_mode == _AuthMode.login
                        ? Icons.person_add_outlined
                        : Icons.arrow_back),
                    label: Text(_mode == _AuthMode.login
                        ? 'Добавить нового пользователя'
                        : 'Вернуться ко входу'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : widget.onOffline,
                    icon: const Icon(Icons.cloud_off_outlined),
                    label: const Text('Продолжить offline'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'Email хранится локально, пароль — в защищённом системном хранилище.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                ])),
          )),
        )),
      );

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordRepeat.dispose();
    super.dispose();
  }
}
