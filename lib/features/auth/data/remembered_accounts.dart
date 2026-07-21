import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RememberedAccounts {
  static const _key = 'remembered_account_emails';
  static const _passwordPrefix = 'task_manager_password_';
  static const _secureStorage = FlutterSecureStorage();

  static Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_key) ?? const [];
    return values.toSet().toList()..sort();
  }

  static Future<void> add(String email, String password) async {
    final preferences = await SharedPreferences.getInstance();
    final values = {
      ...preferences.getStringList(_key) ?? const <String>[],
      email.trim().toLowerCase()
    }.toList()
      ..sort();
    await preferences.setStringList(_key, values);
    await _secureStorage.write(
      key: '$_passwordPrefix${email.trim().toLowerCase()}',
      value: password,
    );
  }

  static Future<String?> passwordFor(String email) => _secureStorage.read(
        key: '$_passwordPrefix${email.trim().toLowerCase()}',
      );

  static Future<void> remove(String email) async {
    final preferences = await SharedPreferences.getInstance();
    final values = [...preferences.getStringList(_key) ?? const <String>[]]
      ..remove(email);
    await preferences.setStringList(_key, values);
    await _secureStorage.delete(
      key: '$_passwordPrefix${email.trim().toLowerCase()}',
    );
  }
}
