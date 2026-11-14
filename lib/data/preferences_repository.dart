import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PreferencesRepository {
  Future<String?> readTheme();
  Future<String?> readLanguage();
  Future<void> saveTheme(String theme);
  Future<void> saveLanguage(String? language);
}

class LocalPreferencesRepository implements PreferencesRepository {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> readTheme() => _preferences.getString('theme');
  @override
  Future<String?> readLanguage() => _preferences.getString('language');

  @override
  Future<void> saveTheme(String theme) =>
      _preferences.setString('theme', theme);
  @override
  Future<void> saveLanguage(String? language) => language == null
      ? _preferences.remove('language')
      : _preferences.setString('language', language);
}
