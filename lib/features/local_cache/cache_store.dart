import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';
import '../plate/models/post_model.dart';
import '../forum/domain/forum_site.dart';
import 'cached_post.dart';
import 'cache_database.dart';

class CacheStats {
  const CacheStats(
    this.count,
    this.pinned,
    this.usedBytes,
    this.fileBytes,
    this.sites, {
    this.pinnedBytes = 0,
  });
  final int count, pinned, usedBytes, fileBytes;
  final List<Map<String, Object?>> sites;
  final int pinnedBytes;
}

/// Single queue: cleanup/disable/import cannot race an in-flight cache write.
class CacheStore extends ChangeNotifier {
  CacheStore({Future<Database> Function()? open, int Function()? clock})
    : _open = open ?? openCacheDatabase,
      _clock = clock ?? (() => DateTime.now().microsecondsSinceEpoch);
  final Future<Database> Function() _open;
  final int Function() _clock;
  Future<Database>? _database;
  Future<void> _queue = Future.value();
  bool enabled = true;
  int limitBytes = 100 * 1024 * 1024;
  String? warning;
  bool _disposed = false;
  final Map<int, int> _protected = {};
  int generation = 0;
  Future<Database> get ready => _database ??= _initialize();
  Future<void> get flushed => _queue;

  Future<Database> _initialize() async {
    final db = await _open();
    try {
      await db.transaction((tx) async {
        await tx.execute('''CREATE TABLE IF NOT EXISTS posts (
        rowid INTEGER PRIMARY KEY AUTOINCREMENT, site TEXT NOT NULL, instance TEXT NOT NULL,
        identity TEXT NOT NULL, post_id INTEGER NOT NULL, thread_id INTEGER,
        page INTEGER, payload TEXT NOT NULL, text TEXT NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0, accessed INTEGER NOT NULL,
        UNIQUE(instance, identity, post_id))''');
        // Additive migration: preserve existing cache, pins and first-seen text.
        final columns = await tx.rawQuery('PRAGMA table_info(posts)');
        if (!columns.any((column) => column['name'] == 'browsed_at')) {
          await tx.execute('ALTER TABLE posts ADD COLUMN browsed_at INTEGER');
        }
        await tx.execute(
          'CREATE INDEX IF NOT EXISTS cache_browsed ON posts(instance,identity,browsed_at DESC)',
        );
        await tx.execute(
          'CREATE INDEX IF NOT EXISTS cache_thread ON posts(instance,identity,thread_id,post_id)',
        );
        await tx.execute(
          'CREATE INDEX IF NOT EXISTS cache_lru ON posts(pinned,accessed)',
        );
        await tx.execute(
          "CREATE VIRTUAL TABLE IF NOT EXISTS post_search USING fts5(text, content='posts', content_rowid='rowid', tokenize='trigram')",
        );
        await tx.execute(
          '''CREATE TRIGGER IF NOT EXISTS cache_insert AFTER INSERT ON posts BEGIN
        INSERT INTO post_search(rowid,text) VALUES(new.rowid,new.text); END''',
        );
        await tx.execute(
          '''CREATE TRIGGER IF NOT EXISTS cache_delete AFTER DELETE ON posts BEGIN
        INSERT INTO post_search(post_search,rowid,text) VALUES('delete',old.rowid,old.text); END''',
        );
        await tx.execute(
          'CREATE TABLE IF NOT EXISTS config(key TEXT PRIMARY KEY,value INTEGER NOT NULL)',
        );
      });
      final settings = {
        for (final r in await db.query('config')) r['key']: r['value'],
      };
      enabled = settings['enabled'] != 0;
      final savedLimit = settings['limit'];
      if (savedLimit is int &&
          savedLimit >= 1024 * 1024 &&
          savedLimit <= 2 * 1024 * 1024 * 1024) {
        limitBytes = savedLimit;
      }
      return db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<void> retry() async {
    await _queue;
    try {
      await ready;
    } catch (_) {
      _database = null;
    }
    await ready;
    warning = null;
    if (!_disposed) notifyListeners();
  }

  Future<T> _run<T>(Future<T> Function(Database db) work) {
    final task = _queue.then((_) async {
      try {
        return await work(await ready);
      } catch (_) {
        warning = '本地缓存无法读写，请在缓存配置中重试；在线浏览不受影响';
        rethrow;
      } finally {
        if (!_disposed) notifyListeners();
      }
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> configure({bool? automatic, int? bytes}) => _run((db) async {
    if (bytes != null &&
        (bytes < 1024 * 1024 || bytes > 2 * 1024 * 1024 * 1024)) {
      throw const FormatException('容量须为 1–2048 MB');
    }
    generation++;
    await db.transaction((tx) async {
      if (automatic != null) {
        await tx.insert('config', {
          'key': 'enabled',
          'value': automatic ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (bytes != null) {
        await tx.insert('config', {
          'key': 'limit',
          'value': bytes,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    if (automatic != null) enabled = automatic;
    if (bytes != null) limitBytes = bytes;
    await _evict(db);
  });

  Future<void> capture(
    ForumSite site,
    String identity,
    Iterable<Post> posts, {
    int? threadId,
    int? page,
    bool force = false,
    bool pin = false,
    int? expectedGeneration,
  }) => _run((db) async {
    if (expectedGeneration != null && expectedGeneration != generation) return;
    await db.transaction((tx) async {
      Future<void> save(Post p, {int? parent, int? cursor}) async {
        if (p.id <= 0 || p.site.instanceKey != site.instanceKey) return;
        final known = await tx.query(
          'posts',
          columns: ['rowid', 'thread_id'],
          where: 'instance=? AND identity=? AND post_id=?',
          whereArgs: [site.instanceKey, identity, p.id],
        );
        final root = p.parentUnknown
            ? parent
            : (p.followId == 0 ? p.id : p.followId);
        if (known.isNotEmpty) {
          // Original bytes never change. Only access and proven navigation metadata do.
          await tx.update(
            'posts',
            {
              'accessed': _clock(),
              if (pin) 'pinned': 1,
              if (known.first['thread_id'] == null && root != null)
                'thread_id': root,
              'page': ?cursor,
            },
            where: 'rowid=?',
            whereArgs: [known.first['rowid']],
          );
        } else if (enabled || force) {
          final payload = jsonEncode(cachePostJson(p));
          if (utf8.encode(payload).length > 1024 * 1024) return;
          await tx.insert('posts', {
            'site': site.id,
            'instance': site.instanceKey,
            'identity': identity,
            'post_id': p.id,
            'thread_id': root,
            'page': cursor,
            'payload': payload,
            'text': '${p.id} ${p.title} ${p.value}'.toLowerCase(),
            'accessed': _clock(),
            'pinned': pin ? 1 : 0,
          });
        }
        if (!force) {
          for (final reply in p.lastReplyArr) {
            await save(reply, parent: p.isRoot ? p.id : parent);
          }
        }
      }

      for (final p in posts) {
        await save(p, parent: threadId, cursor: p.isRoot ? 0 : page);
      }
    });
    await _evict(db);
  });

  String _visible(Map<String, String> scopes, List<Object?> args) {
    if (scopes.isEmpty) return '0';
    return scopes.entries
        .map((e) {
          args.addAll([e.key, e.value]);
          return '(instance=? AND identity=?)';
        })
        .join(' OR ');
  }

  /// Only the visible thread screen calls this. Fetching or previewing a post
  /// must never manufacture a visit. LRU access remains an independent clock.
  Future<void> markBrowsed(
    ForumSite site,
    String identity,
    int threadId, {
    int? expectedGeneration,
  }) => _run((db) async {
    if (!enabled ||
        expectedGeneration != null && expectedGeneration != generation) {
      return;
    }
    await db.update(
      'posts',
      {'browsed_at': _clock()},
      where: 'instance=? AND identity=? AND post_id=? AND thread_id=post_id',
      whereArgs: [site.instanceKey, identity, threadId],
    );
  });

  /// Import legacy timestamps once per identity, without inventing missing
  /// original bodies or resurrecting history after explicit cache deletion.
  Future<void> migrateBrowseHistory(
    ForumSite site,
    String identity,
    List<Map<String, dynamic>> history,
  ) => _run((db) async {
    final key = 'browse-migrated:${site.instanceKey}/$identity';
    await db.transaction((tx) async {
      if ((await tx.query(
        'config',
        where: 'key=?',
        whereArgs: [key],
      )).isNotEmpty) {
        return;
      }
      for (final entry in history) {
        final id = entry['id'], time = entry['time'];
        if (id is! int || id <= 0 || time is! int || time <= 0) continue;
        await tx.rawUpdate(
          'UPDATE posts SET browsed_at=? WHERE instance=? AND identity=? '
          'AND post_id=? AND thread_id=post_id AND (browsed_at IS NULL OR browsed_at<?)',
          [time * 1000, site.instanceKey, identity, id, time * 1000],
        );
      }
      await tx.insert('config', {'key': key, 'value': 1});
    });
  });

  Future<List<CachedPost>> search(
    Map<String, String> scopes, {
    String query = '',
    String? site,
    bool pinnedOnly = false,
    bool browsedOnly = false,
    int offset = 0,
    int limit = 80,
  }) async {
    await _queue;
    final db = await ready;
    final args = <Object?>[];
    final filters = ['(${_visible(scopes, args)})'];
    if (site != null) {
      filters.add('site=?');
      args.add(site);
    }
    if (pinnedOnly) filters.add('pinned=1');
    if (browsedOnly) {
      filters.add('browsed_at IS NOT NULL AND thread_id=post_id');
    }
    var q = query.trim().toLowerCase();
    final no = RegExp(r'^(?:no\.|po\.|>>)(\d+)$').firstMatch(q);
    if (no != null) q = no[1]!;
    if (q.isNotEmpty) {
      if (q.runes.length >= 3) {
        filters.add(
          'rowid IN (SELECT rowid FROM post_search WHERE text MATCH ?)',
        );
        args.add('"${q.replaceAll('"', '""')}"');
      }
      filters.add('instr(text,?)>0');
      args.add(q);
    }
    final rows = await db.query(
      'posts',
      where: filters.join(' AND '),
      whereArgs: args,
      orderBy: 'COALESCE(browsed_at,accessed) DESC,rowid DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(CachedPost.new).toList();
  }

  Future<CachedPost?> find(ForumSite site, String identity, int id) async {
    await _queue;
    final rows = await (await ready).query(
      'posts',
      where: 'instance=? AND identity=? AND post_id=?',
      whereArgs: [site.instanceKey, identity, id],
    );
    return rows.isEmpty ? null : CachedPost(rows.first);
  }

  /// A bounded, stable export snapshot, even when the configured cache is huge.
  Future<List<CachedPost>> exportRows(
    Map<String, String> scopes, {
    String? site,
    bool pinnedOnly = false,
  }) => _run((db) async {
    final args = <Object?>[];
    final filters = ['(${_visible(scopes, args)})'];
    if (site != null) {
      filters.add('site=?');
      args.add(site);
    }
    if (pinnedOnly) filters.add('pinned=1');
    return db.transaction((tx) async {
      final result = <CachedPost>[];
      var last = 0, bytes = 512;
      while (true) {
        final batch = await tx.query(
          'posts',
          where: [...filters, 'rowid>?'].join(' AND '),
          whereArgs: [...args, last],
          orderBy: 'rowid',
          limit: 16,
        );
        for (final data in batch) {
          final row = CachedPost(data);
          bytes += utf8.encode(row.payload).length + 512;
          if (bytes > 32 * 1024 * 1024 || result.length >= 100000) {
            throw const FormatException('单份备份最多 32 MB，请到浏览搜索分批选择导出');
          }
          result.add(row);
          last = row.rowId;
        }
        if (batch.length < 16) return result;
      }
    });
  });

  Future<List<CachedPost>> thread(
    ForumSite site,
    String identity,
    int id,
  ) async {
    await _queue;
    final rows = await (await ready).query(
      'posts',
      where: 'instance=? AND identity=? AND thread_id=?',
      whereArgs: [site.instanceKey, identity, id],
      orderBy: 'post_id',
    );
    return rows.map(CachedPost.new).toList();
  }

  Future<void> touch(List<int> ids) => _run((db) async {
    for (final id in ids) {
      await db.update(
        'posts',
        {'accessed': _clock()},
        where: 'rowid=?',
        whereArgs: [id],
      );
    }
  });
  void protect(List<int> ids) {
    for (final id in ids) {
      _protected[id] = (_protected[id] ?? 0) + 1;
    }
  }

  void release(List<int> ids) {
    for (final id in ids) {
      final n = (_protected[id] ?? 1) - 1;
      if (n <= 0) {
        _protected.remove(id);
      } else {
        _protected[id] = n;
      }
    }
  }

  Future<void> pin(List<int> ids, bool value) => _run((db) async {
    for (final id in ids) {
      await db.update(
        'posts',
        {'pinned': value ? 1 : 0},
        where: 'rowid=?',
        whereArgs: [id],
      );
    }
    await _evict(db);
  });

  Future<void> remove({
    List<int>? ids,
    String? site,
    bool includePinned = false,
  }) => _run((db) async {
    generation++;
    final where = <String>[if (!includePinned) 'pinned=0'];
    final args = <Object?>[];
    if (site != null) {
      where.add('site=?');
      args.add(site);
    }
    if (ids != null) {
      if (ids.isEmpty) return;
      // Avoid SQLite variable count limits for bulk selection.
      await db.transaction((tx) async {
        for (final id in ids) {
          await tx.delete(
            'posts',
            where: [...where, 'rowid=?'].join(' AND '),
            whereArgs: [...args, id],
          );
        }
      });
    } else {
      await db.delete(
        'posts',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
      );
    }
    warning = null;
  });

  Future<int> _used(Database db) async {
    final pages =
        (await db.rawQuery('PRAGMA page_count')).first.values.first as int;
    final free =
        (await db.rawQuery('PRAGMA freelist_count')).first.values.first as int;
    final size =
        (await db.rawQuery('PRAGMA page_size')).first.values.first as int;
    return (pages - free) * size;
  }

  Future<void> _evict(Database db) async {
    warning = null;
    if (await _used(db) <= limitBytes) return;
    await db.execute("INSERT INTO post_search(post_search) VALUES('optimize')");
    while (await _used(db) > limitBytes) {
      final rows = await db.query(
        'posts',
        columns: ['rowid'],
        where: 'pinned=0',
        orderBy: 'accessed,rowid',
      );
      final victims = rows
          .where((r) => !_protected.containsKey(r['rowid']))
          .take(8)
          .toList();
      if (victims.isEmpty) {
        warning = '永久保留或正在阅读的内容已占满预算，请增大容量或取消保留；新内容可能无法缓存';
        return;
      }
      await db.transaction((tx) async {
        for (final r in victims) {
          await tx.delete('posts', where: 'rowid=?', whereArgs: [r['rowid']]);
        }
      });
      await db.execute(
        "INSERT INTO post_search(post_search) VALUES('optimize')",
      );
    }
  }

  Future<CacheStats> stats() async {
    await _queue;
    final db = await ready;
    final rows = await db.rawQuery(
      'SELECT site,COUNT(*) AS count,SUM(pinned) AS pinned,SUM(length(CAST(payload AS BLOB))) AS bytes,SUM(CASE WHEN pinned=1 THEN length(CAST(payload AS BLOB)) ELSE 0 END) AS pinned_bytes FROM posts GROUP BY site',
    );
    final pages =
        (await db.rawQuery('PRAGMA page_count')).first.values.first as int;
    final size =
        (await db.rawQuery('PRAGMA page_size')).first.values.first as int;
    return CacheStats(
      rows.fold(0, (n, r) => n + (r['count'] as int)),
      rows.fold(0, (n, r) => n + (r['pinned'] as int)),
      await _used(db),
      pages * size,
      rows,
      pinnedBytes: rows.fold(0, (n, r) => n + (r['pinned_bytes'] as int)),
    );
  }

  Future<void> compact() => _run((db) async {
    await db.execute("INSERT INTO post_search(post_search) VALUES('optimize')");
    await db.execute('VACUUM');
    warning = null;
  });
  Future<void> removeHistoryContent(
    ForumSite site,
    Set<String> identities, {
    int? threadId,
  }) => _run((db) async {
    generation++;
    for (final identity in identities) {
      await db.delete(
        'posts',
        where:
            'instance=? AND identity=? AND pinned=0${threadId == null ? '' : ' AND (thread_id=? OR post_id=?)'}',
        whereArgs: [
          site.instanceKey,
          identity,
          if (threadId != null) ...[threadId, threadId],
        ],
      );
    }
  });
  Future<int> importRows(
    List<Map<String, dynamic>> rows,
    Map<String, String> scopes,
  ) => _run((db) async {
    generation++;
    var added = 0;
    await db.transaction((tx) async {
      for (final row in rows) {
        final site = ForumSite.byId(row['site'] as String);
        final identity = scopes[site.instanceKey];
        if (identity == null || row['instance'] != site.instanceKey) {
          throw const FormatException('备份站点与当前实例不匹配');
        }
        final p = cachePostFromJson(
          Map<String, dynamic>.from(row['post'] as Map),
          site,
        );
        final existing = await tx.query(
          'posts',
          columns: ['rowid'],
          where: 'instance=? AND identity=? AND post_id=?',
          whereArgs: [site.instanceKey, identity, p.id],
        );
        if (existing.isNotEmpty) continue;
        await tx.insert('posts', {
          'site': site.id,
          'instance': site.instanceKey,
          'identity': identity,
          'post_id': p.id,
          'thread_id': row['thread'],
          'page': row['page'],
          'payload': jsonEncode(cachePostJson(p)),
          'text': '${p.id} ${p.title} ${p.value}'.toLowerCase(),
          'pinned': row['pinned'] == true ? 1 : 0,
          'accessed': _clock(),
          'browsed_at': p.isRoot && !p.parentUnknown ? row['browsedAt'] : null,
        });
        added++;
      }
    });
    await _evict(db);
    return added;
  });
  Future<void> close() async {
    await _queue;
    if (_database != null) await (await _database!).close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
