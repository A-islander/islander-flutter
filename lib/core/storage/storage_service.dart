import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cookie_identity.dart';
import '../../features/forum/domain/forum_site.dart';

class StorageService {
  static const String keyToken = 'token';
  static const String keyName = 'name';
  static const String keyUserId = 'userId';
  static const String keyTheme = 'theme';
  static const String keyImgToken = 'imgToken';

  final SharedPreferences _prefs;

  StorageService(this._prefs, {ForumSite? islanderSite})
    : _islanderSite = islanderSite ?? ForumSite.islander;
  final ForumSite _islanderSite;
  bool get _legacyInstance =>
      _islanderSite.id == 'islander' &&
      _islanderSite.endpoint == 'https://forum-api.islander.top/' &&
      _islanderSite.identityEndpoint == 'https://user-api.islander.top/';
  String get _vaultStorageKey => _legacyInstance
      ? vaultKey
      : 'islander.cookie-vault.v2.${_islanderSite.instanceKey}';
  String get _draftPrefix => _legacyInstance
      ? 'islander.draft.v1.'
      : 'islander.draft.v2.${_islanderSite.instanceKey}.';

  Map<String, dynamic>? readForumState(String key) => readDraft(key);
  Future<void> saveForumState(String key, Map<String, dynamic> value) =>
      saveDraft(key, value);

  Future<String?> readExternalVault(String instanceKey) => kIsWeb
      ? Future.value(
          _prefs.getString('islander.external-vault.v1.$instanceKey'),
        )
      : _secure.read(key: 'islander.external-vault.v1.$instanceKey');
  Future<void> writeExternalVault(String instanceKey, String value) async {
    final key = 'islander.external-vault.v1.$instanceKey';
    if (kIsWeb) {
      if (!await _prefs.setString(key, value)) throw StateError('保存失败');
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  static const vaultKey = 'islander.cookie-vault.v1';
  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
  );
  List<CookieIdentity> cookies = const [];
  String? activeCookieId;
  String? vaultError;

  Future<void> initialize() async {
    try {
      final raw = kIsWeb
          ? _prefs.getString(_vaultStorageKey)
          : await _secure.read(key: _vaultStorageKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['version'] != 1) {
          throw const FormatException('Unknown vault version');
        }
        final entries = (data['cookies'] as List)
            .map((e) => CookieIdentity.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final active = data['activeId'] as String?;
        if (entries.map((e) => e.id).toSet().length != entries.length ||
            entries.map((e) => e.token).toSet().length != entries.length ||
            (active != null &&
                !entries.any((e) => e.id == active && !e.invalid))) {
          throw const FormatException('Invalid vault');
        }
        cookies = List.unmodifiable(entries);
        activeCookieId = active;
      } else {
        final legacy = _legacyInstance ? getToken()?.trim() ?? '' : '';
        final entries = legacy.isEmpty
            ? <CookieIdentity>[]
            : [
                CookieIdentity(
                  id: CookieIdentity.newId(),
                  token: legacy,
                  name: getName() ?? '',
                  userId: getUserId() ?? 0,
                ),
              ];
        await saveCookies(entries, entries.firstOrNull?.id);
      }
      // Only remove legacy plaintext after the secure write succeeds.
      for (final key
          in _legacyInstance ? [keyToken, keyName, keyUserId] : <String>[]) {
        if (_prefs.containsKey(key) && !await _prefs.remove(key)) {
          throw StateError('Migration failed');
        }
      }
      vaultError = null;
    } catch (_) {
      cookies = const [];
      activeCookieId = null;
      vaultError = '无法读取饼干存储，原数据未被覆盖。请重试。';
    }
  }

  Future<void> saveCookies(
    List<CookieIdentity> entries,
    String? activeId,
  ) async {
    final raw = jsonEncode({
      'version': 1,
      'activeId': activeId,
      'cookies': entries.map((e) => e.toJson()).toList(),
    });
    if (kIsWeb) {
      if (!await _prefs.setString(_vaultStorageKey, raw)) {
        throw StateError('Storage failed');
      }
    } else {
      await _secure.write(key: _vaultStorageKey, value: raw);
    }
    cookies = List.unmodifiable(entries);
    activeCookieId = activeId;
  }

  String draftKey(String cookieId, int boardId, int? threadId) =>
      '$_draftPrefix$cookieId.${threadId == null ? 'board.$boardId' : 'thread.$threadId'}';
  Map<String, dynamic>? readDraft(String key) {
    final raw = _prefs.getString(key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _draftWrites = Future.value();
  Future<void> saveDraft(String key, Map<String, dynamic>? draft) {
    final raw = draft == null ? null : jsonEncode(draft);
    final task = _draftWrites.then((_) async {
      final ok = raw == null
          ? await _prefs.remove(key)
          : await _prefs.setString(key, raw);
      if (!ok) throw StateError('无法保存草稿');
    });
    _draftWrites = task.catchError((Object _) {});
    return task;
  }

  Future<void> removeDrafts(String cookieId) async {
    await _draftWrites;
    for (final key in _prefs.getKeys().where(
      (k) => k.startsWith('$_draftPrefix$cookieId.'),
    )) {
      await saveDraft(key, null);
    }
  }

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
  Future<bool> setImgToken(String token) =>
      _prefs.setString(keyImgToken, token);

  // Clear all
  Future<bool> clearAll() async {
    await _draftWrites;
    if (!kIsWeb) await _secure.delete(key: vaultKey);
    final cleared = await _prefs.clear();
    if (cleared) {
      cookies = const [];
      activeCookieId = null;
    }
    return cleared;
  }
}
