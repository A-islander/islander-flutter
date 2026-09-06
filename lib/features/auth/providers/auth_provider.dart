import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/cookie_identity.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/network/dio_client.dart';

class AuthState {
  const AuthState({this.cookies = const [], this.activeId, this.error});
  final List<CookieIdentity> cookies;
  final String? activeId, error;
  CookieIdentity? get current =>
      cookies.where((e) => e.id == activeId && !e.invalid).firstOrNull;
  String get token => current?.token ?? '';
  String get name => current?.name ?? '';
  int get userId => current?.userId ?? 0;
  bool get isLoggedIn => current != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final StorageService _storage;
  final DioClient _dio;
  Future<void> _writes = Future.value();
  AuthNotifier(this._storage, this._dio)
    : super(
        AuthState(
          cookies: _storage.cookies,
          activeId: _storage.activeCookieId,
          error: _storage.vaultError,
        ),
      ) {
    if (state.isLoggedIn) _dio.setToken(state.token);
    _dio.onUnauthorized = () {
      final token = state.token;
      _dio.clearToken();
      unawaited(
        markInvalid(token).catchError((Object _) {
          if (!mounted || state.token != token) return;
          state = AuthState(
            cookies: List.unmodifiable(
              state.cookies.map(
                (e) => e.token == token ? e.copyWith(invalid: true) : e,
              ),
            ),
            error: '当前饼干已失效，但本机状态保存失败。请重试读取后验证饼干。',
          );
        }),
      );
    };
  }

  Future<void> _change(AuthState Function(AuthState) change) {
    final task = _writes.then((_) async {
      if (state.error != null) throw StateError('饼干存储不可用，请先重试');
      final next = change(state);
      try {
        await _storage.saveCookies(next.cookies, next.activeId);
      } catch (_) {
        throw StateError('饼干保存失败，未切换身份，请重试');
      }
      if (!mounted) return;
      if (next.token != state.token) {
        next.isLoggedIn ? _dio.setToken(next.token) : _dio.clearToken();
      }
      state = next;
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> retryStorage() async {
    await _writes;
    await _storage.initialize();
    if (!mounted) return;
    state = AuthState(
      cookies: _storage.cookies,
      activeId: _storage.activeCookieId,
      error: _storage.vaultError,
    );
    state.isLoggedIn ? _dio.setToken(state.token) : _dio.clearToken();
  }

  Future<void> setToken(String token, {String name = '', int userId = 0}) =>
      _change((current) {
        token = token.trim();
        if (token.isEmpty) throw ArgumentError('饼干不能为空');
        final old = current.cookies.where((e) => e.token == token).firstOrNull;
        final cookie =
            old?.copyWith(name: name, userId: userId, invalid: false) ??
            CookieIdentity(
              id: CookieIdentity.newId(),
              token: token,
              name: name,
              userId: userId,
            );
        return AuthState(
          cookies: List.unmodifiable([
            for (final entry in current.cookies)
              if (entry.id == cookie.id) cookie else entry,
            if (old == null) cookie,
          ]),
          activeId: cookie.id,
        );
      });
  Future<void> rename(String id, String label) => _change(
    (current) => AuthState(
      cookies: List.unmodifiable(
        current.cookies.map(
          (e) => e.id == id ? e.copyWith(label: label.trim()) : e,
        ),
      ),
      activeId: current.activeId,
    ),
  );
  Future<void> setName(String name) => _change(
    (current) => AuthState(
      cookies: List.unmodifiable(
        current.cookies.map(
          (e) => e.id == current.activeId ? e.copyWith(name: name) : e,
        ),
      ),
      activeId: current.activeId,
    ),
  );
  Future<void> setUserId(int id) => _change(
    (current) => AuthState(
      cookies: List.unmodifiable(
        current.cookies.map(
          (e) => e.id == current.activeId ? e.copyWith(userId: id) : e,
        ),
      ),
      activeId: current.activeId,
    ),
  );
  Future<void> logout() =>
      _change((current) => AuthState(cookies: current.cookies));
  Future<void> remove(String id) async {
    await _change(
      (current) => AuthState(
        cookies: List.unmodifiable(current.cookies.where((e) => e.id != id)),
        activeId: current.activeId == id ? null : current.activeId,
      ),
    );
    await _storage.removeDrafts(id);
  }

  Future<void> markInvalid(String token) => _change(
    (current) => AuthState(
      cookies: List.unmodifiable(
        current.cookies.map(
          (e) => e.token == token ? e.copyWith(invalid: true) : e,
        ),
      ),
      activeId: current.token == token ? null : current.activeId,
    ),
  );
  @override
  void dispose() {
    _dio.onUnauthorized = null;
    super.dispose();
  }
}
