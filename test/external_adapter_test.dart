import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/features/forum/data/adapters/x_adapter.dart';
import 'package:islander_flutter/features/forum/data/adapters/bog_adapter.dart';
import 'package:islander_flutter/features/forum/data/adapters/external_adapter.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'package:islander_flutter/features/plate/models/post_model.dart';

class ExternalFixture implements HttpClientAdapter {
  ExternalFixture(this.respond);
  final dynamic Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  Dio client() => Dio()..httpClientAdapter = this;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final value = await respond(options);
    return ResponseBody.fromString(
      value is String ? value : jsonEncode(value),
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> xPost(int id, {int replies = 0}) => {
  'id': '$id',
  'fid': '1',
  'user_hash': 'publicHash',
  'content': '海边<br>颜文字 (ゝ∀･) >>No.42',
  'now': '2026-09-07(一)12:00:00',
  'ReplyCount': '$replies',
  'Replies': <dynamic>[],
};

String bogPost(int id, {bool reply = false}) =>
    '''<div class="${reply ? 'item-reply' : 'item-main'}">
  <span class="item-pop">#$id</span><span class="item-id">publicCookie</span>
  <span class="item-time">2026-09-07 12:00:00</span><span class="item-title">海边 $id</span>
  <span class="item-fname">综合版</span><div class="item-content">颜文字 &gt;&gt;Po.42<br>(ゝ∀･)<script>bad()</script></div>
  </div>''';

String bogPage({
  int page = 1,
  String path = 'f/时间线',
  bool more = true,
  bool thread = false,
}) =>
    '''
  <nav class="forum-list"><a href="/f/时间线">时间线</a><a href="/f/综合版">综合版</a></nav>
  <div class="item-list">${bogPost(10)}${thread ? bogPost(page == 1 ? 11 : 12, reply: true) : ''}</div>
  <div class="pages"><div class="page-main"><span>$page</span></div>
    ${more ? '<a href="/$path/${page + 1}">下一页</a>' : ''}
    <a href="https://other.invalid/$path/${page + 1}">外部链接</a>
  </div>''';

void main() {
  test('endpoint normalization and same numeric ID remain isolated', () {
    final a = ForumSite(
      id: 'x',
      name: 'test',
      endpoint: 'https://example.com/api',
      webUrl: 'https://example.com',
    );
    final b = ForumSite(
      id: 'x',
      name: 'test',
      endpoint: 'https://example.com/api/',
      webUrl: 'https://example.com',
    );
    expect(a.instanceKey, b.instanceKey);
    expect(
      Post(id: 10, source: ForumSite.x).key,
      isNot(Post(id: 10, source: ForumSite.bog).key),
    );
    expect(a.instanceKey, isNot(ForumSite.x.instanceKey));
    expect(
      () => ForumSite(
        id: 'x',
        name: '',
        endpoint: 'https://secret@example.com/',
        webUrl: '',
      ),
      throwsArgumentError,
    );
    expect(
      () => ForumSite(
        id: 'x',
        name: '',
        endpoint: 'https://example.com/?token=secret',
        webUrl: '',
      ),
      throwsArgumentError,
    );
  });
  test('HTML becomes safe plain text without losing line breaks or kaomoji', () {
    expect(
      ExternalAdapter.text(
        '你好<br>&gt;&gt;Po.42<p>(ゝ∀･)</p><script>secret</script><style>bad</style>',
      ),
      '你好\n>>Po.42(ゝ∀･)',
    );
    expect(ForumRepository.quoteIds('>>No.42 >>Po.7 >>8 No.42'), [42, 7, 8]);
  });
  test(
    'X discovers timeline IDs and sends only its own immutable cookie',
    () async {
      final fixture = ExternalFixture(
        (r) => r.uri.path.endsWith('getTimelineList')
            ? [
                {'id': '9', 'max_page': '5'},
              ]
            : List.generate(20, (i) => xPost(i + 10)),
      );
      final repo = XAdapter(
        transport: fixture.client(),
        userhash: 'encoded%2Bcookie',
      );
      final page = await repo.page(kind: 'timeline');
      expect(page.totalCount, isNull);
      expect(page.hasMore, isTrue);
      expect(fixture.requests.last.uri.queryParameters['id'], '9');
      expect(
        fixture.requests.last.headers['Cookie'],
        'userhash=encoded%2Bcookie',
      );
      expect(
        fixture.requests.last.headers.containsKey('Authorization'),
        isFalse,
      );
      expect(fixture.requests.last.followRedirects, isFalse);
    },
  );
  test('X thread pages use 19 replies, retain root and filter Tips', () async {
    final fixture = ExternalFixture(
      (r) => {
        ...xPost(10, replies: 20),
        'Replies': [
          {'id': '0', 'user_hash': 'Tips'},
          xPost(r.uri.queryParameters['page'] == '1' ? 11 : 30),
        ],
      },
    );
    final repo = XAdapter(transport: fixture.client());
    final first = await repo.page(kind: 'thread', postId: 10);
    final second = await repo.page(kind: 'thread', postId: 10, page: 1);
    expect(first.posts.map((p) => p.id), [10, 11]);
    expect(first.totalPages, 2);
    expect(first.hasMore, isTrue);
    expect(second.posts.map((p) => p.id), [30]);
    expect(second.root!.id, 10);
    expect(second.hasMore, isFalse);
    expect(second.posts.single.followId, 10);
    expect(second.posts.single.userId, 0);
  });
  test('X reference has unknown parent and safe CDN media', () async {
    final fixture = ExternalFixture(
      (r) => r.uri.path.endsWith('getCDNPath')
          ? [
              {'url': 'https://media.example/'},
            ]
          : {...xPost(42), 'img': 'abc', 'ext': '.png'},
    );
    final post = await XAdapter(transport: fixture.client()).post(42);
    expect(post.parentUnknown, isTrue);
    expect(post.isRoot, isFalse);
    expect(post.parentId, isNull);
    expect(post.value, contains('(ゝ∀･)'));
    expect(post.mediaUrl, contains('https://media.example/image/abc.png'));
    expect(
      post.time,
      DateTime.utc(2026, 9, 7, 4).millisecondsSinceEpoch ~/ 1000,
    );
  });
  test('X remote errors never reflect server text or credentials', () async {
    final repo = XAdapter(
      transport: ExternalFixture(
        (_) => {'success': false, 'error': 'secret-cookie'},
      ).client(),
    );
    await expectLater(
      repo.post(1),
      throwsA(
        isA<ForumFailure>().having(
          (e) => e.message,
          'redacted',
          isNot(contains('secret')),
        ),
      ),
    );
  });
  test(
    'BOG board key remains original name; unknown totals follow real next links',
    () async {
      final fixture = ExternalFixture(
        (r) => bogPage(
          path: r.uri.pathSegments.contains('综合版') ? 'f/综合版' : 'f/时间线',
        ),
      );
      final repo = BogAdapter(transport: fixture.client());
      final boards = await repo.plates();
      expect(boards.single.key, '综合版');
      expect(boards.single.id, 0);
      final page = await repo.page(kind: 'board', boardKey: boards.single.key);
      expect(fixture.requests.last.uri.pathSegments, ['f', '综合版', '1']);
      expect(page.hasMore, isTrue);
      expect(page.totalCount, isNull);
      expect(page.posts.single.value, isNot(contains('bad')));
      expect(page.posts.single.boardKey, '综合版');
    },
  );
  test('BOG thread root is not duplicated on later pages', () async {
    final repo = BogAdapter(
      transport: ExternalFixture(
        (_) => bogPage(page: 2, path: 't/10', thread: true, more: false),
      ).client(),
    );
    final page = await repo.page(kind: 'thread', postId: 10, page: 1);
    expect(page.root!.id, 10);
    expect(page.posts.single.id, 12);
    expect(page.posts.single.followId, 10);
    expect(page.hasMore, isFalse);
  });
  test(
    'BOG missing structure, wrong thread and clamped page fail explicitly',
    () async {
      for (final value in [
        '<html>login</html>',
        bogPage(page: 1),
        bogPage(page: 2, path: 't/10', thread: true),
      ]) {
        final repo = BogAdapter(
          transport: ExternalFixture((_) => value).client(),
        );
        await expectLater(
          repo.page(kind: 'thread', postId: 99, page: 1),
          throwsA(isA<ForumFailure>()),
        );
      }
    },
  );
  test('BOG JSON quote preserves parent and media', () async {
    final repo = BogAdapter(
      transport: ExternalFixture(
        (_) => {
          'code': '6001',
          'info': {
            'id': '11',
            'res': '10',
            'content': '&gt;&gt;Po.10',
            'cookie': 'publicHash',
            'images': [
              {'url': 'abc', 'ext': '.jpg'},
            ],
          },
        },
      ).client(),
    );
    final post = await repo.post(11);
    expect(post.followId, 10);
    expect(post.authorId, 'publicHash');
    expect(post.userId, 0);
    expect(post.mediaUrl, contains('/image/large/abc.jpg'));
  });
  test('unsupported external mutations never send HTTP requests', () async {
    final fixture = ExternalFixture(
      (_) => throw StateError('must not request'),
    );
    for (final repo in [
      XAdapter(transport: fixture.client()),
      BogAdapter(transport: fixture.client()),
    ]) {
      for (final request in [
        repo.vote(1, true),
        repo.changeVisibility(1, recover: true),
        repo.register(),
        repo.page(kind: 'mine'),
      ]) {
        await expectLater(
          request,
          throwsA(
            isA<ForumFailure>().having((e) => e.code, 'code', 'unsupported'),
          ),
        );
      }
    }
    expect(fixture.requests, isEmpty);
  });
  test(
    'cookie validation rejects header injection and foreign cookie names',
    () {
      expect(
        () => XAdapter(userhash: 'a\r\nAuthorization: b'),
        throwsA(isA<ForumFailure>()),
      );
      expect(
        () => BogAdapter(cookie: 'bog_master=a; bog_sel=b; userhash=c'),
        throwsA(isA<ForumFailure>()),
      );
      final bog = BogAdapter(cookie: 'bog_master=a; bog_sel=b');
      expect(bog.capabilities.verify, isFalse);
      expect(bog.cookie, 'bog_master=a; bog_sel=b');
      bog.dispose();
    },
  );
}
