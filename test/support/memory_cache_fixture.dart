import 'dart:convert';
import 'package:islander_flutter/features/local_cache/cache_store.dart';
import 'package:islander_flutter/features/local_cache/cached_post.dart';
import 'package:islander_flutter/features/forum/domain/forum_site.dart';
import 'package:islander_flutter/features/plate/models/post_model.dart';

/// UI-only double: SQL/FTS/transactions use real SQLite in local_cache_test.dart.
/// Avoids native database events crossing Flutter's per-test fake async zones.
class MemoryCacheFixture extends CacheStore {
  final Map<int, Map<String, Object?>> rows = {};
  int serial = 0, access = 0;
  @override
  Future<void> migrateBrowseHistory(
    ForumSite site,
    String identity,
    List<Map<String, dynamic>> history,
  ) async {}

  @override
  Future<void> markBrowsed(
    ForumSite site,
    String identity,
    int threadId, {
    int? expectedGeneration,
  }) async {
    if (!enabled ||
        expectedGeneration != null && expectedGeneration != generation) {
      return;
    }
    for (final row in rows.values) {
      if (row['instance'] == site.instanceKey &&
          row['identity'] == identity &&
          row['post_id'] == threadId &&
          row['thread_id'] == threadId) {
        row['browsed_at'] = ++access;
      }
    }
  }

  @override
  Future<void> get flushed async {}
  @override
  Future<void> capture(
    ForumSite site,
    String identity,
    Iterable<Post> posts, {
    int? threadId,
    int? page,
    bool force = false,
    bool pin = false,
    int? expectedGeneration,
  }) async {
    for (final p in posts) {
      final old = rows.values
          .where(
            (r) =>
                r['instance'] == site.instanceKey &&
                r['identity'] == identity &&
                r['post_id'] == p.id,
          )
          .firstOrNull;
      if (old != null) {
        old['accessed'] = ++access;
        continue;
      }
      if (!enabled && !force) continue;
      final id = ++serial;
      rows[id] = {
        'rowid': id,
        'site': site.id,
        'instance': site.instanceKey,
        'identity': identity,
        'post_id': p.id,
        'thread_id': p.parentUnknown
            ? threadId
            : p.isRoot
            ? p.id
            : p.followId,
        'page': p.isRoot ? 0 : page,
        'payload': jsonEncode(cachePostJson(p)),
        'accessed': ++access,
        'pinned': pin ? 1 : 0,
      };
    }
  }

  @override
  Future<List<CachedPost>> search(
    Map<String, String> scopes, {
    String query = '',
    String? site,
    bool pinnedOnly = false,
    bool browsedOnly = false,
    int offset = 0,
    int limit = 80,
  }) async {
    final result =
        rows.values
            .where(
              (r) =>
                  scopes[r['instance']] == r['identity'] &&
                  (site == null || r['site'] == site) &&
                  (!pinnedOnly || r['pinned'] == 1) &&
                  (!browsedOnly ||
                      r['browsed_at'] != null &&
                          r['thread_id'] == r['post_id']),
            )
            .map(CachedPost.new)
            .where(
              (r) => '${r.post.id} ${r.post.title} ${r.post.value}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            final recent = b.displayTime.compareTo(a.displayTime);
            return recent == 0 ? b.rowId.compareTo(a.rowId) : recent;
          });
    return result.skip(offset).take(limit).toList();
  }

  @override
  Future<CachedPost?> find(ForumSite site, String identity, int id) async {
    final row = rows.values
        .where(
          (r) =>
              r['instance'] == site.instanceKey &&
              r['identity'] == identity &&
              r['post_id'] == id,
        )
        .firstOrNull;
    return row == null ? null : CachedPost(row);
  }

  @override
  Future<List<CachedPost>> thread(
    ForumSite site,
    String identity,
    int id,
  ) async => rows.values
      .where(
        (r) =>
            r['instance'] == site.instanceKey &&
            r['identity'] == identity &&
            r['thread_id'] == id,
      )
      .map(CachedPost.new)
      .toList();
  @override
  Future<void> touch(List<int> ids) async {
    for (final id in ids) {
      rows[id]?['accessed'] = ++access;
    }
  }

  @override
  Future<void> pin(List<int> ids, bool value) async {
    for (final id in ids) {
      rows[id]?['pinned'] = value ? 1 : 0;
    }
    notifyListeners();
  }

  @override
  Future<void> remove({
    List<int>? ids,
    String? site,
    bool includePinned = false,
  }) async {
    rows.removeWhere(
      (id, r) =>
          (ids == null || ids.contains(id)) &&
          (site == null || site == r['site']) &&
          (includePinned || r['pinned'] != 1),
    );
    notifyListeners();
  }

  @override
  Future<void> configure({bool? automatic, int? bytes}) async {
    if (automatic != null) enabled = automatic;
    if (bytes != null) limitBytes = bytes;
    notifyListeners();
  }

  @override
  Future<CacheStats> stats() async => CacheStats(
    rows.length,
    rows.values.where((r) => r['pinned'] == 1).length,
    65536,
    65536,
    [],
  );
  @override
  Future<void> close() async {}
}
