import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _languagePreferenceKey = 'interface_language';

final appLocaleProvider =
    StateNotifierProvider<AppLocaleController, Locale>((ref) {
  return AppLocaleController();
});

class AppLocaleController extends StateNotifier<Locale> {
  AppLocaleController() : super(const Locale('en')) {
    _restore();
  }

  Future<void> _restore() async {
    final code = (await SharedPreferences.getInstance())
        .getString(_languagePreferenceKey);
    if (code == 'ru' || code == 'en') state = Locale(code!);
  }

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode != 'en' && locale.languageCode != 'ru') return;
    state = locale;
    await (await SharedPreferences.getInstance())
        .setString(_languagePreferenceKey, locale.languageCode);
  }
}

class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  bool get isRussian => locale.languageCode == 'ru';
  String text(String english, String russian) => isRussian ? russian : english;
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const ['en', 'ru'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
