import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';
import '../../../main.dart';
import '../domain/forum_site.dart';

final forumStateStoreProvider = Provider(
  (ref) => ForumStateStore(ref.watch(storageServiceProvider)),
);

/// Small bounded, versioned records; all read-modify-write operations serialize.
/// Never contains credentials or full post bodies.
class ForumStateStore {
  ForumStateStore(this.storage) {
    try {
      final saved = storage.readForumState(storageKey);
      if (saved != null) {
        if (saved['version'] != 1 || saved['scopes'] is! Map) {
          throw const FormatException();
        }
        _data = saved;
      }
    } catch (_) {
      error = '浏览状态无法读取，原数据未覆盖';
    }
  }
  static const storageKey = 'islander.forum-state.v1';
  final StorageService storage;
  Map<String, dynamic> _data = {'version': 1, 'scopes': <String, dynamic>{}};
  String? error;
  Future<void> _queue = Future.value();
  Future<void> get flushed => _queue;
  int _allEpoch = 0;
  final _epochs = <String, int>{};
  String scopeKey(ForumSite site, String identity) =>
      '${site.instanceKey}/$identity';
  int epoch(String scope) => _allEpoch + (_epochs[scope] ?? 0);
  Map<String, dynamic> _scope(String key) {
    final value = (_data['scopes'] as Map)[key];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  bool recording(String scope) => _scope(scope)['record'] != false;
  String? get lastRoute {
    final siteId = _data['lastSite'];
    final instance = _data['lastInstance'];
    final matches = ForumSite.all.where(
      (s) => s.id == siteId && s.instanceKey == instance,
    );
    if (matches.isEmpty) return null;
    // A cold start remembers the site only, never the previous reading route.
    return matches.first.route('/plate/0');
  }

  String? routeFor(String scope) {
    final route = _scope(scope)['route'];
    return route is String && safeRoute(route) ? route : null;
  }

  Future<String?> startupRoute() async => lastRoute;

  static bool belongsTo(ForumSite site, String route) =>
      safeRoute(route) &&
      (site.isIslander
          ? !route.startsWith('/s/')
          : route.startsWith('/s/${site.id}/'));

  static bool safeRoute(String route) => RegExp(
    r'^/(?:s/(?:x|bog)/)?(?:plate/[^/?#]+|post/[0-9]+|mine|sage)$',
  ).hasMatch(route);
  Map<String, dynamic>? position(String scope, String route) {
    final positions = _scope(scope)['positions'];
    final value = positions is Map ? positions[route] : null;
    if (value is! Map ||
        value['page'] is! int ||
        value['page'] < 0 ||
        value['page'] >= 1000000 ||
        value['anchor'] != null && value['anchor'] is! int ||
        value['fraction'] is! num ||
        !(value['fraction'] as num).isFinite) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> history(String scope) {
    final raw = _scope(scope)['history'];
    if (raw is! Map) return [];
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    final rows = raw.values
        .whereType<Map>()
        .where(
          (e) =>
              e['time'] is int &&
              e['time'] >= cutoff &&
              e['route'] is String &&
              safeRoute(e['route']),
        )
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    rows.sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));
    return rows.take(500).toList();
  }

  Future<void> _update(void Function(Map<String, dynamic>) change) {
    final task = _queue.then((_) async {
      if (error != null) throw StateError(error!);
      final next = jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;
      change(next);
      await storage.saveForumState(storageKey, next);
      _data = next;
    });
    _queue = task.catchError((Object _) {});
    return task;
  }

  Future<void> activate(ForumSite site) => _update((data) {
    data['lastSite'] = site.id;
    data['lastInstance'] = site.instanceKey;
  });
  Future<void> save({
    required ForumSite site,
    required String identity,
    required String route,
    required int page,
    int? anchor,
    double fraction = 0,
    bool newest = false,
    int? threadId,
    String title = '',
    bool recordHistory = true,
    required int historyEpoch,
  }) {
    if (!belongsTo(site, route) ||
        !fraction.isFinite ||
        page < 0 ||
        page >= 1000000) {
      return Future.error(const FormatException('Invalid route'));
    }
    final key = scopeKey(site, identity);
    return _update((data) {
      // A pre-clear snapshot must not overwrite newer navigation either.
      if (historyEpoch != epoch(key)) return;
      final scopes = data['scopes'] as Map;
      final scope = Map<String, dynamic>.from(scopes[key] as Map? ?? {});
      final allowed = scope['record'] != false && historyEpoch == epoch(key);
      // Disabling/clearing history must not leave a hidden persistent thread trail.
      scope['route'] = threadId != null && !allowed
          ? site.route('/plate/0')
          : route;
      if (allowed || threadId == null) {
        final positions = Map<String, dynamic>.from(
          scope['positions'] as Map? ?? {},
        );
        positions[route] = {
          'page': page,
          'anchor': anchor,
          'fraction': fraction.clamp(0, 1),
          'newest': newest,
          'time': DateTime.now().millisecondsSinceEpoch,
        };
        while (positions.length > 550) {
          positions.remove(positions.keys.first);
        }
        scope['positions'] = positions;
      }
      if (threadId != null && allowed && recordHistory) {
        final rows = Map<String, dynamic>.from(scope['history'] as Map? ?? {});
        final now = DateTime.now().millisecondsSinceEpoch;
        rows['$threadId'] = {
          'id': threadId,
          'route': route,
          'title': String.fromCharCodes(title.runes.take(160)),
          'time': now,
        };
        final sorted =
            rows.entries
                .where(
                  (e) =>
                      e.value is Map &&
                      e.value['time'] is int &&
                      now - (e.value['time'] as int) <=
                          const Duration(days: 90).inMilliseconds,
                )
                .toList()
              ..sort(
                (a, b) =>
                    (b.value['time'] as int).compareTo(a.value['time'] as int),
              );
        scope['history'] = Map.fromEntries(sorted.take(500));
      }
      scopes[key] = scope;
    });
  }

  Future<void> setRecording(String scope, bool enabled) {
    _epochs[scope] = (_epochs[scope] ?? 0) + 1;
    return _update((data) {
      final record = Map<String, dynamic>.from(
        (data['scopes'] as Map)[scope] as Map? ?? {},
      );
      record['record'] = enabled;
      if (!enabled) {
        final positions = Map<String, dynamic>.from(
          record['positions'] as Map? ?? {},
        );
        positions.removeWhere((k, _) => k.contains('/post/'));
        record['positions'] = positions;
        if ('${record['route']}'.contains('/post/')) record.remove('route');
      }
      (data['scopes'] as Map)[scope] = record;
    });
  }

  Future<void> clear(String scope, {int? id}) {
    _epochs[scope] = (_epochs[scope] ?? 0) + 1;
    return _update((data) {
      final record = Map<String, dynamic>.from(
        (data['scopes'] as Map)[scope] as Map? ?? {},
      );
      final rows = Map<String, dynamic>.from(record['history'] as Map? ?? {});
      if (id == null) {
        rows.clear();
      } else {
        rows.remove('$id');
      }
      record['history'] = rows;
      final positions = Map<String, dynamic>.from(
        record['positions'] as Map? ?? {},
      );
      bool selected(String route) =>
          id == null ? route.contains('/post/') : route.endsWith('/post/$id');
      positions.removeWhere((k, _) => selected(k));
      record['positions'] = positions;
      if (selected('${record['route']}')) record.remove('route');
      (data['scopes'] as Map)[scope] = record;
    });
  }

  Future<void> clearAll() {
    _allEpoch++;
    return _update((data) {
      for (final record in (data['scopes'] as Map).values.whereType<Map>()) {
        record['history'] = <String, dynamic>{};
        final positions = Map<String, dynamic>.from(
          record['positions'] as Map? ?? {},
        );
        positions.removeWhere((k, _) => k.contains('/post/'));
        record['positions'] = positions;
        if ('${record['route']}'.contains('/post/')) record.remove('route');
      }
    });
  }
}
