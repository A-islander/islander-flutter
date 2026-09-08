import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/cookie_identity.dart';
import '../../../core/storage/storage_service.dart';
import '../../../main.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/adapters/bog_adapter.dart';
import '../data/adapters/x_adapter.dart';
import '../forum_repository.dart';

final externalIdentityProvider =
    StateNotifierProvider.family<
      ExternalIdentityNotifier,
      AsyncValue<AuthState>,
      ForumSite
    >(
      (ref, site) =>
          ExternalIdentityNotifier(ref.watch(storageServiceProvider), site),
    );

/// No connection to AuthNotifier or Islander's mutable Dio token.
class ExternalIdentityNotifier extends StateNotifier<AsyncValue<AuthState>> {
  ExternalIdentityNotifier(this.storage, this.site)
    : super(const AsyncLoading()) {
    ready = reload();
  }
  final StorageService storage;
  late final Future<void> ready;
  final ForumSite site;
  Future<void> _queue = Future.value();
  Future<void> reload() async {
    try {
      final raw = await storage.readExternalVault(site.instanceKey);
      var value = const AuthState();
      if (raw != null) {
        final json = jsonDecode(raw) as Map;
        if (json['version'] != 1 || json['instance'] != site.instanceKey) {
          throw const FormatException();
        }
        final cookies = (json['cookies'] as List)
            .map((e) => CookieIdentity.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final active = json['activeId'] as String?;
        for (final cookie in cookies) {
          site.id == 'x'
              ? XAdapter.validateCookie(cookie.token)
              : BogAdapter.validateCookie(cookie.token);
        }
        if (cookies.map((e) => e.id).toSet().length != cookies.length ||
            cookies.map((e) => e.token).toSet().length != cookies.length ||
            active != null && !cookies.any((e) => e.id == active)) {
          throw const FormatException();
        }
        value = AuthState(cookies: cookies, activeId: active);
      }
      if (mounted) state = AsyncData(value);
    } catch (_) {
      if (mounted) {
        state = AsyncError(
          const ForumFailure('外站饼干存储无法读取，原数据未覆盖'),
          StackTrace.current,
        );
      }
    }
  }

  Future<void> _change(AuthState Function(AuthState) update) {
    final task = _queue.then((_) async {
      final current = state.asData?.value;
      if (current == null) throw const ForumFailure('请先重试读取饼干存储');
      final next = update(current);
      await storage.writeExternalVault(
        site.instanceKey,
        jsonEncode({
          'version': 1,
          'instance': site.instanceKey,
          'activeId': next.activeId,
          'cookies': next.cookies.map((e) => e.toJson()).toList(),
        }),
      );
      if (mounted) state = AsyncData(next);
    });
    _queue = task.catchError((Object _) {});
    return task;
  }

  Future<void> importCookie(
    String input,
    String label, {
    Future<void> Function(String)? verify,
  }) async {
    final token = site.id == 'x'
        ? XAdapter.validateCookie(input.trim())
        : BogAdapter.validateCookie(input.trim());
    if (site.id == 'x') {
      if (verify != null) {
        await verify(token);
      } else {
        final repo = XAdapter(site: site);
        try {
          await repo.verifyToken(token);
        } finally {
          repo.dispose();
        }
      }
    }
    await _change((current) {
      final existing = current.cookies
          .where((e) => e.token == token)
          .firstOrNull;
      final cookie = CookieIdentity(
        id: existing?.id ?? CookieIdentity.newId(),
        token: token,
        name: site.id == 'bog' ? 'BOG 饼干（未验证）' : 'X 岛饼干（已验证访问）',
        userId: 0,
        label: label.trim().isEmpty ? existing?.label ?? '' : label.trim(),
      );
      return AuthState(
        cookies: [...current.cookies.where((e) => e.id != cookie.id), cookie],
        activeId: cookie.id,
      );
    });
  }

  Future<void> activate(String? id) => _change((current) {
    if (id != null && !current.cookies.any((e) => e.id == id)) {
      throw const ForumFailure('饼干不存在');
    }
    return AuthState(cookies: current.cookies, activeId: id);
  });
  Future<void> remove(String id) async {
    await _change(
      (current) => AuthState(
        cookies: current.cookies.where((e) => e.id != id).toList(),
        activeId: current.activeId == id ? null : current.activeId,
      ),
    );
    await storage.removeExternalDrafts(site, id);
  }
}
