import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/network/dio_client.dart';

class AuthState {
  final String token;
  final String name;
  final int userId;
  final bool isLoggedIn;

  const AuthState({this.token = '', this.name = '', this.userId = 0})
    : isLoggedIn = false;
  const AuthState.loggedIn({
    required this.token,
    required this.name,
    required this.userId,
  }) : isLoggedIn = true;

  AuthState copyWith({String? token, String? name, int? userId}) {
    return AuthState.loggedIn(
      token: token ?? this.token,
      name: name ?? this.name,
      userId: userId ?? this.userId,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final StorageService _storage;
  final DioClient _dio;

  AuthNotifier(this._storage, this._dio) : super(const AuthState()) {
    _dio.onUnauthorized = logout;
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final token = _storage.getToken() ?? '';
    final name = _storage.getName() ?? '';
    final userId = _storage.getUserId() ?? 0;
    if (token.isNotEmpty) {
      state = AuthState.loggedIn(token: token, name: name, userId: userId);
      _dio.setToken(token);
    }
  }

  Future<void> setToken(
    String token, {
    String name = '',
    int userId = 0,
  }) async {
    await _storage.setToken(token);
    await _storage.setName(name);
    await _storage.setUserId(userId);
    _dio.setToken(token);
    state = AuthState.loggedIn(token: token, name: name, userId: userId);
  }

  Future<void> setName(String name) async {
    await _storage.setName(name);
    if (state.isLoggedIn) state = state.copyWith(name: name);
  }

  Future<void> setUserId(int id) async {
    await _storage.setUserId(id);
    if (state.isLoggedIn) state = state.copyWith(userId: id);
  }

  Future<void> logout() async {
    _dio.clearToken();
    state = const AuthState();
    await _storage.removeToken();
    await _storage.setName('');
    await _storage.setUserId(0);
  }
}
