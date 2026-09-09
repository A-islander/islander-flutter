import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:islander_flutter/features/local_cache/cache_store.dart';
import 'package:islander_flutter/features/local_cache/cache_backup.dart';
import 'package:islander_flutter/features/local_cache/cached_repository.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'package:islander_flutter/features/plate/models/post_model.dart';
import 'package:islander_flutter/features/plate/models/plate_model.dart';

Future<CacheStore> testCache({int Function()? clock}) async {
  sqfliteFfiInit();
  final store = CacheStore(
    open: () => databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    ),
    clock: clock,
  );
  await store.ready;
  return store;
}

class CacheRemote extends ForumRepository {
  CacheRemote(this.site) : super.base();
  @override
  final ForumSite site;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<List<Plate>> plates() async => [];
  @override
  Future<Post> post(int id) async {
    if (fail) throw const ForumFailure('offline');
    return Post(id: id, source: site, value: '主贴');
  }

  @override
  Future<PostPage> page({
    required String kind,
    int boardId = 0,
    String? boardKey,
    int postId = 0,
    int page = 0,
  }) async {
    await gate?.future;
    if (fail) throw const ForumFailure('offline');
    return PostPage(
      [Post(id: 11, source: site, followId: 10, value: '回复')],
      1,
      hasMore: false,
      root: Post(id: 10, source: site, value: '主贴'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CacheStore store;
  var clock = 0;
  final site = ForumSite.islander;
  late Map<String, String> scopes;
  setUp(() async {
    store = await testCache(clock: () => ++clock);
    scopes = {for (final s in ForumSite.all) s.instanceKey: 'a'};
  });
  tearDown(() async {
    await store.close();
    store.dispose();
  });
  test(
    'all cached posts share one descending time order without visited priority',
    () async {
      await store.capture(site, 'a', [const Post(id: 10, value: '旧浏览')]);
      await store.markBrowsed(site, 'a', 10);
      await store.capture(site, 'a', [
        const Post(id: 20, value: '新加载主串'),
        const Post(id: 21, followId: 20, value: '新加载回复'),
      ]);
      expect((await store.search(scopes)).map((r) => r.post.id), [21, 20, 10]);
      expect(
        (await store.search(scopes, offset: 1, limit: 1)).single.post.id,
        20,
      );
      await store.markBrowsed(site, 'a', 20);
      expect((await store.search(scopes)).map((r) => r.post.id), [20, 21, 10]);
      expect((await store.find(site, 'a', 21))!.browsedAt, isNull);
    },
  );
  test(
    'browse timestamps distinguish roots from loads, previews and LRU touches',
    () async {
      await store.capture(site, 'a', [
        const Post(id: 10, value: '先打开'),
        const Post(id: 20, value: '后打开'),
        const Post(id: 11, followId: 10, value: '回复'),
      ]);
      expect(await store.search(scopes, browsedOnly: true), isEmpty);
      await store.markBrowsed(site, 'a', 10);
      final stamp = (await store.find(site, 'a', 10))!.browsedAt;
      await store.markBrowsed(site, 'a', 20);
      await store.markBrowsed(site, 'a', 11);
      await store.capture(site, 'a', [const Post(id: 10, value: '不覆盖')]);
      expect((await store.find(site, 'a', 10))!.browsedAt, stamp);
      expect((await store.find(site, 'a', 11))!.browsedAt, isNull);
      expect(
        (await store.search(scopes, browsedOnly: true)).map((p) => p.post.id),
        [20, 10],
      );
      expect((await store.search(scopes, query: '回复')).single.post.id, 11);
      await store.markBrowsed(site, 'a', 10);
      expect((await store.search(scopes, browsedOnly: true)).first.post.id, 10);
    },
  );
  test(
    'browse markers isolate identities and reject disabled or stale requests',
    () async {
      for (final s in ForumSite.all) {
        await store.capture(s, 'a', [Post(id: 10, source: s)]);
      }
      await store.capture(site, 'b', [const Post(id: 10)]);
      await store.markBrowsed(site, 'b', 10);
      expect(await store.search(scopes, browsedOnly: true), isEmpty);
      final old = store.generation;
      await store.configure(automatic: false);
      await store.markBrowsed(site, 'a', 10);
      await store.configure(automatic: true);
      await store.markBrowsed(site, 'a', 10, expectedGeneration: old);
      expect(await store.search(scopes, browsedOnly: true), isEmpty);
      await store.markBrowsed(ForumSite.x, 'a', 10);
      expect(
        (await store.search(scopes, browsedOnly: true)).single.site.id,
        'x',
      );
    },
  );
  test(
    'legacy history migrates only real cached roots once and preserves newer visits',
    () async {
      await store.capture(site, 'a', [
        const Post(id: 10, value: '原文'),
        const Post(id: 11, followId: 10),
      ]);
      final history = [
        {'id': 10, 'time': 20},
        {'id': 11, 'time': 30},
        {'id': 99, 'time': 40},
      ];
      await store.migrateBrowseHistory(site, 'a', history);
      expect((await store.find(site, 'a', 10))!.browsedAt, 20000);
      expect((await store.find(site, 'a', 11))!.browsedAt, isNull);
      expect(await store.find(site, 'a', 99), isNull);
      final row = (await store.find(site, 'a', 10))!;
      await store.remove(ids: [row.rowId]);
      await store.capture(site, 'a', [const Post(id: 10, value: '重新加载')]);
      await store.migrateBrowseHistory(site, 'a', history);
      expect((await store.find(site, 'a', 10))!.browsedAt, isNull);
    },
  );
  test(
    'existing database gets additive browse migration without losing posts or pins',
    () async {
      await store.capture(site, 'a', [
        const Post(id: 10, value: '保留原文'),
      ], pin: true);
      final db = await store.ready;
      await db.execute('DROP INDEX cache_browsed');
      await db.execute('ALTER TABLE posts DROP COLUMN browsed_at');
      final upgraded = CacheStore(open: () async => db);
      await upgraded.ready;
      final row = (await upgraded.find(site, 'a', 10))!;
      expect(row.post.value, '保留原文');
      expect(row.pinned, true);
      expect(row.browsedAt, isNull);
      await upgraded.markBrowsed(site, 'a', 10);
      final backup = decodeCacheBackup(
        encodeCacheBackup(await upgraded.exportRows(scopes)),
      );
      expect(backup.single['browsedAt'], isNotNull);
    },
  );
  test(
    'first content wins, loaded preview replies are individual rows, access updates',
    () async {
      await store.capture(site, 'a', [
        const Post(
          id: 10,
          value: '最初的原文',
          lastReplyArr: [Post(id: 11, followId: 10, value: '颜文字 (╯°□°）╯')],
        ),
      ]);
      final before = (await store.find(site, 'a', 10))!;
      await store.capture(site, 'a', [
        const Post(id: 10, value: '不可覆盖', status: 2),
      ]);
      final after = (await store.find(site, 'a', 10))!;
      expect(after.post.value, '最初的原文');
      expect(after.post.status, 0);
      expect(after.accessed, greaterThan(before.accessed));
      expect(after.post.lastReplyArr, isEmpty);
      expect((await store.find(site, 'a', 11))!.threadId, 10);
      expect((await store.stats()).count, 2);
    },
  );
  test(
    'same number isolated by island, endpoint and identity; search never touches LRU',
    () async {
      for (final s in ForumSite.all) {
        await store.capture(s, 'a', [Post(id: 10, source: s, value: s.name)]);
      }
      await store.capture(site, 'b', [const Post(id: 10, value: '身份 B 私有')]);
      final before = (await store.find(site, 'a', 10))!.accessed;
      expect(await store.search(scopes), hasLength(3));
      expect(await store.search(scopes, query: '私有'), isEmpty);
      expect((await store.find(site, 'a', 10))!.accessed, before);
      final other = ForumSite(
        id: 'islander',
        name: '另一实例',
        endpoint: 'https://other.example',
        webUrl: 'https://other.example',
      );
      expect(await store.find(other, 'a', 10), isNull);
    },
  );
  test(
    'Chinese short and long text, No IDs, literal punctuation and emoji searchable',
    () async {
      await store.capture(site, 'a', [
        const Post(id: 123, title: '海岛生活', value: '沙滩 100% _ 😀 (╯°□°）╯ ABC'),
      ]);
      for (final query in [
        '沙',
        '沙滩',
        '海岛生活',
        'No.123',
        '😀',
        '100%',
        '_',
        '(╯°□°）╯',
        'abc',
      ]) {
        expect(
          await store.search(scopes, query: query),
          hasLength(1),
          reason: query,
        );
      }
      expect(await store.search(scopes, query: '" OR 1=1 --'), isEmpty);
      expect(await store.search(scopes, query: '不存在'), isEmpty);
    },
  );
  test(
    'unknown parent gets proven navigation metadata without changing original content',
    () async {
      final x = ForumSite.x;
      await store.capture(x, 'a', [
        Post(id: 11, source: x, parentUnknown: true, value: '第一次引用'),
      ]);
      expect((await store.find(x, 'a', 11))!.route, contains('localOnly=1'));
      await store.capture(
        x,
        'a',
        [Post(id: 11, source: x, followId: 10, value: '不覆盖')],
        threadId: 10,
        page: 4,
      );
      final row = (await store.find(x, 'a', 11))!;
      expect(row.post.value, '第一次引用');
      expect(row.threadId, 10);
      expect(row.page, 4);
      expect(row.route, '/s/x/post/10?focus=11&page=4');
    },
  );
  test(
    'off stops inserts, not existing access; explicit pin affects only that post',
    () async {
      await store.capture(site, 'a', [const Post(id: 10, value: 'existing')]);
      final before = (await store.find(site, 'a', 10))!.accessed;
      await store.configure(automatic: false);
      await store.capture(site, 'a', [
        const Post(id: 10, value: 'other'),
        const Post(id: 11),
      ]);
      expect(await store.find(site, 'a', 11), isNull);
      expect((await store.find(site, 'a', 10))!.accessed, greaterThan(before));
      await store.capture(
        site,
        'a',
        [
          const Post(id: 12, lastReplyArr: [Post(id: 13, followId: 12)]),
        ],
        force: true,
        pin: true,
      );
      expect((await store.find(site, 'a', 12))!.pinned, isTrue);
      expect(await store.find(site, 'a', 13), isNull);
    },
  );
  test(
    'cleanup invalidates pending generation; default cleanup skips pins',
    () async {
      final generation = store.generation;
      await store.capture(site, 'a', [const Post(id: 10)], pin: true);
      await store.capture(site, 'a', [const Post(id: 11)]);
      await store.remove();
      await store.capture(site, 'a', [
        const Post(id: 12),
      ], expectedGeneration: generation);
      expect(await store.search(scopes), hasLength(1));
      await store.remove(includePinned: true);
      expect(await store.search(scopes), isEmpty);
    },
  );
  test(
    'LRU includes search index bytes, protects pins and recent reads, compaction preserves rows',
    () async {
      await store.configure(bytes: 1024 * 1024);
      final random = Random(9);
      String body() => String.fromCharCodes(
        List.generate(15000, (_) => 33 + random.nextInt(88)),
      );
      await store.capture(site, 'a', [Post(id: 1, value: body())], pin: true);
      for (var i = 2; i <= 18; i++) {
        await store.capture(site, 'a', [Post(id: i, value: body())]);
      }
      expect((await store.find(site, 'a', 1))!.pinned, isTrue);
      expect(await store.find(site, 'a', 2), isNull);
      expect(
        (await store.stats()).usedBytes,
        lessThanOrEqualTo(store.limitBytes),
      );
      final count = (await store.stats()).count;
      await store.compact();
      expect((await store.stats()).count, count);
      expect((await store.stats()).fileBytes, (await store.stats()).usedBytes);
    },
  );
  test(
    'backup round trips source, pin, page, content; excludes identity and deduplicates',
    () async {
      await store.capture(
        ForumSite.bog,
        'a',
        [Post(id: 11, source: ForumSite.bog, followId: 10, value: '备份正文')],
        threadId: 10,
        page: 2,
        pin: true,
      );
      final rows = await store.exportRows(scopes);
      final bytes = encodeCacheBackup(rows);
      final decoded = decodeCacheBackup(bytes);
      expect(jsonEncode(decoded), isNot(contains('identity')));
      expect(decoded.single['page'], 2);
      expect(decoded.single['pinned'], true);
      expect(await store.importRows(decoded, scopes), 0);
      await store.remove(includePinned: true);
      expect(await store.importRows(decoded, scopes), 1);
      expect(
        (await store.search(scopes)).single.route,
        '/s/bog/post/10?focus=11&page=2',
      );
    },
  );
  test(
    'bad archive, future version and foreign endpoint rejected before mutation',
    () async {
      Uint8List zip(Object data, {String name = 'islander-cache.json'}) {
        final b = utf8.encode(jsonEncode(data));
        return Uint8List.fromList(
          ZipEncoder().encode(Archive()..add(ArchiveFile(name, b.length, b))),
        );
      }

      expect(
        () => decodeCacheBackup(zip({}, name: '../escape.json')),
        throwsFormatException,
      );
      expect(
        () => decodeCacheBackup(
          zip({'format': 'islander-cache', 'version': 999, 'posts': []}),
        ),
        throwsFormatException,
      );
      expect(
        () => decodeCacheBackup(
          zip({
            'format': 'islander-cache',
            'version': 1,
            'posts': [
              {
                'site': 'x',
                'instance': 'foreign',
                'post': {'id': 10},
              },
            ],
          }),
        ),
        throwsFormatException,
      );
      expect((await store.stats()).count, 0);
    },
  );
  test('configuration survives reopening the store', () async {
    final db = await store.ready;
    await store.configure(automatic: false, bytes: 8 * 1024 * 1024);
    final reopened = CacheStore(open: () async => db);
    await reopened.ready;
    expect(reopened.enabled, false);
    expect(reopened.limitBytes, 8 * 1024 * 1024);
    // Same connection belongs to the test store.
  });
  test('row handles never get reused after cleanup', () async {
    await store.capture(site, 'a', [const Post(id: 10)]);
    final old = (await store.find(site, 'a', 10))!;
    await store.remove(includePinned: true);
    await store.capture(site, 'a', [const Post(id: 11)]);
    expect((await store.find(site, 'a', 11))!.rowId, greaterThan(old.rowId));
  });
  test(
    'history-linked cleanup preserves other identities and permanent replies',
    () async {
      await store.capture(site, 'a', [
        const Post(id: 10),
        const Post(id: 11, followId: 10),
      ]);
      await store.capture(site, 'b', [const Post(id: 10)]);
      final reply = (await store.find(site, 'a', 11))!;
      await store.pin([reply.rowId], true);
      await store.removeHistoryContent(site, {'a'}, threadId: 10);
      expect(await store.find(site, 'a', 10), isNull);
      expect(await store.find(site, 'a', 11), isNotNull);
      expect(await store.find(site, 'b', 10), isNotNull);
      final repo = CachedForumRepository(
        CacheRemote(site)..fail = true,
        store,
        'a',
      );
      expect((await repo.post(10)).value, contains('主贴尚未缓存'));
      expect((await repo.page(kind: 'thread', postId: 10)).posts.single.id, 11);
      repo.dispose();
    },
  );
  test('a failed initial open can be retried without clearing data', () async {
    var attempts = 0;
    final lazy = CacheStore(
      open: () async {
        if (attempts++ == 0) throw StateError('temporary failure');
        return databaseFactoryFfiNoIsolate.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
      },
    );
    await expectLater(
      lazy.capture(site, 'a', [const Post(id: 10)]),
      throwsStateError,
    );
    await lazy.retry();
    await lazy.capture(site, 'a', [const Post(id: 10)]);
    expect((await lazy.search(scopes)).single.post.id, 10);
    await lazy.close();
    lazy.dispose();
  });
  for (final s in ForumSite.all) {
    test(
      '${s.id} repository captures loaded pages, then uses offline rows and page hints',
      () async {
        final remote = CacheRemote(s);
        final repo = CachedForumRepository(remote, store, 'a');
        await repo.page(kind: 'thread', postId: 10, page: 2);
        await store.flushed;
        expect((await store.search(scopes)).length, 2);
        remote.fail = true;
        expect((await repo.post(10)).fromCache, true);
        expect(await repo.replyPage(10, 11), 2);
        final page = await repo.page(kind: 'thread', postId: 10, page: 2);
        expect(page.fromCache, true);
        expect(page.root!.id, 10);
        expect(page.posts.single.id, 11);
        final stranger = CachedForumRepository(remote, store, 'b');
        await expectLater(
          stranger.page(kind: 'thread', postId: 10),
          throwsA(isA<ForumFailure>()),
        );
        repo.dispose();
        stranger.dispose();
      },
    );
  }
  test(
    'late network response after cleanup cannot repopulate deleted cache',
    () async {
      final remote = CacheRemote(site)..gate = Completer<void>();
      final repo = CachedForumRepository(remote, store, 'a');
      final pending = repo.page(kind: 'thread', postId: 10);
      await store.remove(includePinned: true);
      remote.gate!.complete();
      await pending;
      await store.flushed;
      expect(await store.search(scopes), isEmpty);
      repo.dispose();
    },
  );
}
