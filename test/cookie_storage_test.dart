import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';
import 'package:islander_flutter/core/storage/cookie_identity.dart';
import 'package:islander_flutter/features/auth/providers/auth_provider.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'support/forum_fixture.dart';

class FailingStorage extends StorageService {
  FailingStorage(super.prefs);
  bool fail = false;
  @override
  Future<void> saveCookies(
    List<CookieIdentity> entries,
    String? activeId,
  ) async {
    if (fail) throw StateError('disk unavailable');
    await super.saveCookies(entries, activeId);
  }
}

class DelayedFixture extends ForumFixture {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await finish.future;
    return ResponseBody.fromString(
      jsonEncode({'code': 403, 'msg': 'token is field'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Future<StorageService> storage() async {
  final result = StorageService(await SharedPreferences.getInstance());
  await result.initialize();
  return result;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'legacy cookie migrates once, removes plaintext and survives restart',
    () async {
      SharedPreferences.setMockInitialValues({
        'token': 'legacy-cookie',
        'name': '旧岛民',
        'userId': 7,
      });
      final first = await storage();
      final id = first.activeCookieId;
      expect(first.cookies.single.token, 'legacy-cookie');
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        isNull,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          StorageService.vaultKey,
        ),
        isNull,
      );
      final second = await storage();
      expect(second.activeCookieId, id);
      expect(second.cookies.single.name, '旧岛民');
      expect(second.cookies.length, 1);
    },
  );
  test(
    'failed migration preserves legacy credentials; retry can recover',
    () async {
      SharedPreferences.setMockInitialValues({
        'token': 'legacy-cookie',
        'userId': 7,
      });
      final prefs = await SharedPreferences.getInstance();
      final failed = FailingStorage(prefs)..fail = true;
      await failed.initialize();
      expect(failed.vaultError, isNotNull);
      expect(prefs.getString('token'), 'legacy-cookie');
      failed.fail = false;
      await failed.initialize();
      expect(failed.cookies.single.token, 'legacy-cookie');
      expect(failed.vaultError, isNull);
    },
  );
  test(
    'corrupt vault is not overwritten by initialization or import',
    () async {
      const secure = FlutterSecureStorage();
      await secure.write(key: StorageService.vaultKey, value: '{broken');
      final store = await storage();
      final auth = AuthNotifier(store, ForumFixture().client());
      addTearDown(auth.dispose);
      expect(store.vaultError, isNotNull);
      await expectLater(auth.setToken('new'), throwsStateError);
      expect(await secure.read(key: StorageService.vaultKey), '{broken');
    },
  );
  test(
    'cookies deduplicate, retain labels, switch, logout and remove independently',
    () async {
      final store = await storage();
      final auth = AuthNotifier(store, ForumFixture().client());
      addTearDown(auth.dispose);
      await Future.wait([
        auth.setToken('a', name: 'A', userId: 7),
        auth.setToken('b', name: 'B', userId: 8),
      ]);
      final a = auth.state.cookies.first;
      final b = auth.state.cookies.last;
      await auth.rename(a.id, '工作饼干');
      await auth.setToken('a', name: 'A', userId: 7);
      expect(auth.state.cookies.length, 2);
      expect(auth.state.current!.displayName, '工作饼干');
      final aKey = store.draftKey(a.id, 1, null);
      final bKey = store.draftKey(b.id, 1, null);
      await store.saveDraft(aKey, {'body': 'A draft'});
      await store.saveDraft(bKey, {'body': 'B draft'});
      await auth.logout();
      expect(auth.state.isLoggedIn, false);
      expect(auth.state.cookies.length, 2);
      expect(store.readDraft(aKey)!['body'], 'A draft');
      await auth.setToken('b', name: 'B', userId: 8);
      await auth.markInvalid('a');
      expect(auth.state.token, 'b');
      expect(auth.state.cookies.first.invalid, true);
      await auth.remove(a.id);
      expect(auth.state.token, 'b');
      expect(store.readDraft(aKey), isNull);
      expect(store.readDraft(bKey)!['body'], 'B draft');
    },
  );
  test('failed cookie write does not switch active identity', () async {
    final store = FailingStorage(await SharedPreferences.getInstance());
    await store.initialize();
    final auth = AuthNotifier(store, ForumFixture().client());
    addTearDown(auth.dispose);
    await auth.setToken('a', userId: 7);
    store.fail = true;
    await expectLater(auth.setToken('b', userId: 8), throwsStateError);
    expect(auth.state.token, 'a');
    expect(auth.state.cookies.length, 1);
  });
  test(
    'late authorization failure from old identity does not log out new identity',
    () async {
      final fixture = DelayedFixture();
      final client = fixture.client()..setToken('a');
      var invalidated = false;
      client.onUnauthorized = () => invalidated = true;
      final pending = expectLater(
        ForumRepository(client).page(kind: 'mine'),
        throwsA(isA<ForumFailure>()),
      );
      await fixture.started.future;
      client.setToken('b');
      fixture.finish.complete();
      await pending;
      expect(invalidated, false);
    },
  );
  test(
    'identity-bound publish and upload never send under another cookie',
    () async {
      final fixture = ForumFixture();
      final repo = ForumRepository(fixture.client()..setToken('b'));
      await expectLater(
        repo.publish(body: 'draft', boardId: 1, expectedToken: 'a'),
        throwsA(isA<ForumFailure>()),
      );
      await expectLater(
        repo.upload(
          XFile.fromData(Uint8List.fromList([1, 2]), name: 'test.png'),
          'image',
          (_, _) {},
          expectedToken: 'a',
        ),
        throwsA(isA<ForumFailure>()),
      );
      await expectLater(
        repo.vote(10, true, expectedToken: 'a'),
        throwsA(isA<ForumFailure>()),
      );
      await expectLater(
        repo.changeVisibility(10, recover: false, expectedToken: 'a'),
        throwsA(isA<ForumFailure>()),
      );
      expect(fixture.requests, isEmpty);
    },
  );
  test(
    'draft scopes and ordered clears survive a new storage instance',
    () async {
      final store = await storage();
      final keys = [
        store.draftKey('a', 1, null),
        store.draftKey('a', 2, null),
        store.draftKey('a', 1, 10),
        store.draftKey('a', 1, 11),
        store.draftKey('b', 1, 10),
      ];
      expect(keys.toSet().length, 5);
      for (final key in keys) {
        await store.saveDraft(key, {'body': key});
      }
      final pending = [
        store.saveDraft(keys.first, {'body': 'old'}),
        store.saveDraft(keys.first, null),
      ];
      await Future.wait(pending);
      final restarted = await storage();
      expect(restarted.readDraft(keys.first), isNull);
      for (final key in keys.skip(1)) {
        expect(restarted.readDraft(key)!['body'], key);
      }
    },
  );
}
