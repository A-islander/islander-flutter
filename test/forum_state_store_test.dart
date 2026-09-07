import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';
import 'package:islander_flutter/features/forum/application/forum_state_store.dart';
import 'package:islander_flutter/features/forum/application/external_identity.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';

void main() {
  late StorageService storage;
  test(
    'custom Islander endpoints never import default credentials or drafts',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        'token': 'default-cookie',
        'name': 'old',
        'userId': 7,
        'islander.draft.v1.same.board.1': jsonEncode({'body': 'default draft'}),
      });
      final prefs = await SharedPreferences.getInstance();
      final custom = StorageService(
        prefs,
        islanderSite: ForumSite(
          id: 'islander',
          name: 'test',
          endpoint: 'https://test.invalid/forum/',
          identityEndpoint: 'https://test.invalid/user/',
          webUrl: 'https://test.invalid/',
        ),
      );
      await custom.initialize();
      expect(custom.cookies, isEmpty);
      expect(prefs.getString('token'), 'default-cookie');
      expect(custom.readDraft(custom.draftKey('same', 1, null)), isNull);
      final production = StorageService(prefs);
      await production.initialize();
      expect(production.cookies.single.token, 'default-cookie');
      expect(
        production.readDraft(production.draftKey('same', 1, null))?['body'],
        'default draft',
      );
      await custom.saveDraft(custom.draftKey('same', 1, null), {
        'body': 'test draft',
      });
      await custom.removeDrafts('same');
      expect(
        production.readDraft(production.draftKey('same', 1, null))?['body'],
        'default draft',
      );
    },
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    await storage.initialize();
  });
  Future<void> save(
    ForumStateStore store,
    ForumSite site, {
    String identity = 'anonymous',
    int id = 10,
    int? epoch,
  }) => store.save(
    site: site,
    identity: identity,
    route: site.route('/post/$id'),
    page: 2,
    threadId: id,
    anchor: id + 1,
    fraction: .3,
    title: '海边串',
    historyEpoch: epoch ?? store.epoch(store.scopeKey(site, identity)),
  );
  test(
    'last site and matching identity reading route survive a new store',
    () async {
      final store = ForumStateStore(storage);
      await save(store, ForumSite.bog);
      await store.activate(ForumSite.bog);
      final restored = ForumStateStore(storage);
      expect(await restored.startupRoute(), '/s/bog/post/10');
      expect(
        restored.position(
          restored.scopeKey(ForumSite.bog, 'anonymous'),
          '/s/bog/post/10',
        )?['anchor'],
        11,
      );
      expect(
        restored.history(restored.scopeKey(ForumSite.x, 'anonymous')),
        isEmpty,
      );
    },
  );
  test('same IDs and identity names never share history', () async {
    final store = ForumStateStore(storage);
    await save(store, ForumSite.x, identity: 'one');
    await save(store, ForumSite.bog, identity: 'one');
    await save(store, ForumSite.x, identity: 'two');
    await save(store, ForumSite.x, identity: 'one');
    for (final pair in [
      (ForumSite.x, 'one'),
      (ForumSite.x, 'two'),
      (ForumSite.bog, 'one'),
    ]) {
      expect(store.history(store.scopeKey(pair.$1, pair.$2)), hasLength(1));
    }
    final raw = storage.readForumState(ForumStateStore.storageKey)!;
    expect(jsonEncode(raw), isNot(contains('token')));
    expect(jsonEncode(raw), isNot(contains('cookie')));
  });
  test(
    'clear and disable suppress stale asynchronous history and positions',
    () async {
      final store = ForumStateStore(storage);
      final scope = store.scopeKey(ForumSite.x, 'anonymous');
      final old = store.epoch(scope);
      await save(store, ForumSite.x);
      final pendingClear = store.clear(scope);
      final lateSave = save(store, ForumSite.x, epoch: old);
      await Future.wait([pendingClear, lateSave]);
      expect(store.history(scope), isEmpty);
      expect(store.position(scope, '/s/x/post/10'), isNull);
      await save(store, ForumSite.x);
      expect(store.history(scope), hasLength(1));
      await save(store, ForumSite.x, id: 20, epoch: old);
      expect(store.routeFor(scope), '/s/x/post/10');
      await store.setRecording(scope, false);
      await save(store, ForumSite.x, id: 20);
      expect(store.history(scope), hasLength(1));
      expect(store.position(scope, '/s/x/post/20'), isNull);
      expect(store.routeFor(scope), '/s/x/plate/0');
    },
  );
  test(
    'clear all includes pending new scopes and prevents resurrection',
    () async {
      final store = ForumStateStore(storage);
      final pending = save(store, ForumSite.bog);
      final clear = store.clearAll();
      final late = save(store, ForumSite.x, epoch: 0);
      await Future.wait([pending, clear, late]);
      expect(
        store.history(store.scopeKey(ForumSite.bog, 'anonymous')),
        isEmpty,
      );
      expect(store.history(store.scopeKey(ForumSite.x, 'anonymous')), isEmpty);
    },
  );
  test(
    'corrupt state is preserved and refuses destructive overwrite',
    () async {
      await storage.saveForumState(ForumStateStore.storageKey, {
        'version': 99,
        'scopes': {},
      });
      final store = ForumStateStore(storage);
      expect(store.error, isNotNull);
      expect(await store.startupRoute(), isNull);
      await expectLater(store.activate(ForumSite.x), throwsStateError);
      expect(
        storage.readForumState(ForumStateStore.storageKey)?['version'],
        99,
      );
    },
  );
  test('history is bounded and rejects cross-site routes', () async {
    final store = ForumStateStore(storage);
    for (var i = 1; i <= 502; i++) {
      await save(store, ForumSite.x, id: i);
    }
    expect(
      store.history(store.scopeKey(ForumSite.x, 'anonymous')),
      hasLength(500),
    );
    await expectLater(
      store.save(
        site: ForumSite.x,
        identity: 'anonymous',
        route: '/post/10',
        page: 0,
        historyEpoch: 0,
      ),
      throwsFormatException,
    );
  });
  test(
    'external cookie vaults isolate, deduplicate, persist and remove locally',
    () async {
      final x = ExternalIdentityNotifier(storage, ForumSite.x);
      final bog = ExternalIdentityNotifier(storage, ForumSite.bog);
      addTearDown(x.dispose);
      addTearDown(bog.dispose);
      await Future.wait([x.ready, bog.ready]);
      var verified = 0;
      await x.importCookie(
        'x%2Bcookie',
        '日常',
        verify: (_) async {
          verified++;
        },
      );
      await x.importCookie(
        'x%2Bcookie',
        '',
        verify: (_) async {
          verified++;
        },
      );
      await bog.importCookie('bog_master=a; bog_sel=b', '日常');
      expect(verified, 2);
      expect(x.state.requireValue.cookies, hasLength(1));
      expect(bog.state.requireValue.current!.name, contains('未验证'));
      expect(storage.cookies, isEmpty);
      final restarted = ExternalIdentityNotifier(storage, ForumSite.x);
      addTearDown(restarted.dispose);
      await restarted.ready;
      expect(restarted.state.requireValue.token, 'x%2Bcookie');
      await restarted.remove(restarted.state.requireValue.activeId!);
      expect(restarted.state.requireValue.cookies, isEmpty);
      expect(bog.state.requireValue.cookies, hasLength(1));
    },
  );
  test(
    'failed X verification and invalid external vault do not overwrite',
    () async {
      final x = ExternalIdentityNotifier(storage, ForumSite.x);
      addTearDown(x.dispose);
      await x.ready;
      await expectLater(
        x.importCookie(
          'cookie',
          '',
          verify: (_) async => throw const ForumFailure('拒绝'),
        ),
        throwsA(isA<ForumFailure>()),
      );
      expect(await storage.readExternalVault(ForumSite.x.instanceKey), isNull);
      await storage.writeExternalVault(ForumSite.bog.instanceKey, '{broken');
      final bog = ExternalIdentityNotifier(storage, ForumSite.bog);
      addTearDown(bog.dispose);
      await bog.ready;
      expect(bog.state.hasError, isTrue);
      await expectLater(
        bog.importCookie('bog_master=a; bog_sel=b', ''),
        throwsA(isA<ForumFailure>()),
      );
      expect(
        await storage.readExternalVault(ForumSite.bog.instanceKey),
        '{broken',
      );
    },
  );
}
