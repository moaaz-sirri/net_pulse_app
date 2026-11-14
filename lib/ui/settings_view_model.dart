import 'dart:async';

import 'package:flutter/material.dart';

import '../data/preferences_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._repository);

  final PreferencesRepository _repository;
  ThemeMode _theme = ThemeMode.system;
  ThemeMode get theme => _theme;
  Locale? _locale;
  Locale? get locale => _locale;
  Future<void> _pendingWrite = Future.value();

  Future<void> load() async {
    try {
      final values = await Future.wait([
        _repository.readTheme(),
        _repository.readLanguage(),
      ]);
      _theme = ThemeMode.values.firstWhere(
        (mode) => mode.name == values[0],
        orElse: () => ThemeMode.system,
      );
      final language = values[1];
      _locale = language == null ? null : Locale(language);
    } on Exception catch (error) {
      debugPrint('Could not restore preferences: $error');
    }
  }

  void setTheme(ThemeMode theme) {
    _theme = theme;
    _save(() => _repository.saveTheme(theme.name));
  }

  void setLocale(Locale? locale) {
    _locale = locale;
    _save(() => _repository.saveLanguage(locale?.languageCode));
  }

  void _save(Future<void> Function() write) {
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await write();
      } on Exception catch (error) {
        debugPrint('Could not save preferences: $error');
      }
    });
    notifyListeners();
  }
}
