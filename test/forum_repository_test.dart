import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'support/forum_fixture.dart';

void main() {
  test('uses zero-based pages and unwraps the production envelope', () async {
    final fixture = ForumFixture();
    final repo = ForumRepository(fixture.client());
    expect((await repo.plates()).first.name, '综合版');
    final data = await repo.page(kind: 'board', boardId: 2, page: 1);
    expect(data.count, 21);
    expect(data.posts.first.id, 20);
    expect(fixture.requests.last.queryParameters, {
      'plateId': 2,
      'page': 1,
      'size': 20,
    });
    expect(await repo.replyPage(10, 11), 0);
  });
  test(
    'publishes authentic reply payload and deduplicates quote IDs',
    () async {
      final fixture = ForumFixture();
      final client = fixture.client()..setToken('test-cookie');
      await ForumRepository(
        client,
      ).publish(body: 'No.10 No.11 No.10 (´▽｀)', boardId: 1, threadId: 10);
      final request = fixture.requests.single;
      expect(request.uri.path, '/forum/reply');
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'test-cookie');
      expect(request.data['followId'], 10);
      expect(request.data['replyArr'], [10, 11]);
      expect(jsonDecode(request.data['mediaUrl']), []);
      expect(request.data.containsKey('plateId'), false);
    },
  );
  test('rejects overlong UTF-8 body before sending a request', () async {
    final fixture = ForumFixture();
    final repo = ForumRepository(fixture.client());
    await expectLater(
      repo.publish(body: '岛' * 2731, boardId: 1),
      throwsA(isA<ForumFailure>()),
    );
    expect(fixture.requests, isEmpty);
  });
  test(
    'validates replacement cookie without leaking or overwriting active auth',
    () async {
      final fixture = ForumFixture()..failAuth = true;
      final client = fixture.client()..setToken('old-cookie');
      var invalidated = false;
      client.onUnauthorized = () => invalidated = true;
      await expectLater(
        ForumRepository(client).verifyToken('new-cookie'),
        throwsA(isA<ForumFailure>()),
      );
      expect(fixture.requests.single.headers['Authorization'], 'new-cookie');
      expect(invalidated, false);
    },
  );
  test('business SAGE rejection does not log out a valid user', () async {
    final fixture = ForumFixture()
      ..overrideResponse = {'code': 403, 'msg': "it's sage"};
    final client = fixture.client();
    var invalidated = false;
    client.onUnauthorized = () => invalidated = true;
    await expectLater(
      ForumRepository(client).vote(10, true),
      throwsA(isA<ForumFailure>()),
    );
    expect(invalidated, false);
  });
  test('invalid active cookie invalidates authentication', () async {
    final fixture = ForumFixture()
      ..overrideResponse = {'code': 403, 'msg': 'token is field'};
    final client = fixture.client();
    var invalidated = false;
    client.onUnauthorized = () => invalidated = true;
    await expectLater(
      ForumRepository(client).page(kind: 'mine'),
      throwsA(isA<ForumFailure>()),
    );
    expect(invalidated, true);
  });
  test(
    'upload works with bytes on Web and uses the nested server URL',
    () async {
      final fixture = ForumFixture();
      final repo = ForumRepository(fixture.client());
      final file = XFile.fromData(utf8.encode('fixture'), name: 'fixture.png');
      final media = await repo.upload(file, 'image', (_, total) {});
      expect(media.url, 'https://media.example/test.png');
      expect(media.id, 'image-1');
    },
  );
}
