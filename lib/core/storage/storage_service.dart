import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String keyToken = 'token';
  static const String keyName = 'name';
  static const String keyUserId = 'userId';
  static const String keyTheme = 'theme';
  static const String keyImgToken = 'imgToken';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // Token
  String? getToken() => _prefs.getString(keyToken);
  Future<bool> setToken(String token) => _prefs.setString(keyToken, token);
  Future<bool> removeToken() => _prefs.remove(keyToken);

  // User info
  String? getName() => _prefs.getString(keyName);
  Future<bool> setName(String name) => _prefs.setString(keyName, name);

  int? getUserId() => _prefs.getInt(keyUserId);
  Future<bool> setUserId(int id) => _prefs.setInt(keyUserId, id);

  // Theme
  String? getTheme() => _prefs.getString(keyTheme);
  Future<bool> setTheme(String theme) => _prefs.setString(keyTheme, theme);

  // Img token
  String? getImgToken() => _prefs.getString(keyImgToken);
  Future<bool> setImgToken(String token) => _prefs.setString(keyImgToken, token);

  // Clear all
  Future<bool> clearAll() => _prefs.clear();
}
