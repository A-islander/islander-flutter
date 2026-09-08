import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:islander_flutter/features/forum/data/adapters/external_writer.dart';
import 'package:islander_flutter/features/forum/data/adapters/x_adapter.dart';
import 'package:islander_flutter/features/forum/data/adapters/bog_adapter.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'package:islander_flutter/shared/widgets/media_item.dart';
import 'external_adapter_test.dart' show bogPage;

String xForm({bool reply = true}) =>
    '''<form method="post" action="/Home/Forum/${reply ? 'doReplyThread' : 'doPostThread'}.html">
<input type="hidden" name="${reply ? 'resto' : 'fid'}" value="${reply ? 100 : 4}">
<input type="hidden" name="__hash__" value="fresh-token">
<input type="hidden" name="email" value="sage"><input type="hidden" name="isManager" value="true">
<input name="title" maxlength="100"><textarea name="content" maxlength="10000"></textarea>
<input type="checkbox" name="water" value="true" checked><input type="file" name="image"></form>''';
String bogForm({bool reply = true}) =>
    '''<form method="post" action="/post">
<div class="compose-title"><span>综合版</span></div>
<input type="hidden" name="${reply ? 'res' : 'forum'}" value="${reply ? 100 : 1}">
<input name="title" maxlength="50" disabled><textarea name="comment"></textarea></form>''';
final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
XFile picture() => XFile.fromData(png, path: '/fixture/回复.png', name: '回复.png');
Matcher failure(String code) =>
    throwsA(isA<ForumFailure>().having((e) => e.code, 'code', code));

class WriteFixture implements HttpClientAdapter {
  WriteFixture(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  final payloads = <String>[];
  Dio client() => Dio()..httpClientAdapter = this;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    payloads.add(
      stream == null
          ? ''
          : utf8.decode(
              await stream.expand((e) => e).toList(),
              allowMalformed: true,
            ),
    );
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody response(
  Object body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) => ResponseBody.fromString(
  body is String ? body : jsonEncode(body),
  status,
  headers: headers,
);

void main() {
  test('BOG optional title follows the official advanced-fields toggle', () {
    final source = bogForm(reply: false)
        .replaceFirst(
          '<input name="title"',
          '<div class="hid-input"><input name="title"',
        )
        .replaceFirst(
          '<textarea',
          '</div><button id="other"></button><textarea',
        );
    final parsed = ExternalWriter.parseForm(
      source,
      page: Uri.parse('https://bog.ac/f/综合版/1'),
      site: 'bog',
      body: '正文',
      title: '可选标题',
      boardId: 0,
      boardName: '综合版',
    );
    expect(parsed.fields['title'], ['可选标题']);
    expect(parsed.fields.containsKey('name'), isFalse);
  });
  for (final reply in [true, false]) {
    test(
      'X ${reply ? 'reply' : 'thread'} uses fresh hash, session and atomic image',
      () async {
        final fixture = WriteFixture((r) {
          if (r.uri.path.endsWith('getForumList')) {
            return response([
              {
                'forums': [
                  {'id': 4, 'name': '综合版1'},
                ],
              },
            ]);
          }
          if (r.method == 'GET') {
            return response(
              xForm(reply: reply),
              headers: {
                'set-cookie': [
                  'PHPSESSID=current; Path=/; Secure',
                  'foreign=wrong; Domain=evil.test; Path=/',
                  'scoped=wrong; Path=/elsewhere',
                  'expired=wrong; Max-Age=0; Path=/',
                  'userhash=wrong; Path=/',
                ],
              },
            );
          }
          return response('<p class="success">${reply ? '回复' : '发表'}成功！</p>');
        });
        final repo = XAdapter(
          transport: fixture.client(),
          userhash: 'selected%2Bcookie',
        );
        await repo.publish(
          body: '>>No.101\n正文 & = + (ゝ∀･)',
          title: '标题',
          boardId: 4,
          threadId: reply ? 100 : null,
          files: [picture()],
          expectedToken: 'selected%2Bcookie',
        );
        final gets = fixture.requests.where((r) => r.method == 'GET').toList();
        expect(gets.last.uri.host, 'www.nmbxd1.com');
        expect(
          Uri.decodeComponent(gets.last.uri.path),
          reply ? '/t/100' : '/f/综合版1',
        );
        final post = fixture.requests.last;
        expect(post.followRedirects, isFalse);
        expect(post.uri.host, 'www.nmbxd1.com');
        expect(
          post.headers['Cookie'],
          'userhash=selected%2Bcookie; PHPSESSID=current',
        );
        expect(post.headers.containsKey('Authorization'), isFalse);
        expect(post.headers['Origin'], 'https://www.nmbxd1.com');
        final fields = Map.fromEntries((post.data as FormData).fields);
        expect(fields[reply ? 'resto' : 'fid'], reply ? '100' : '4');
        expect(fields['__hash__'], 'fresh-token');
        expect(fields['content'], '>>No.101\n正文 & = + (ゝ∀･)');
        expect(fields['water'], 'true');
        expect(fields.keys, isNot(contains('email')));
        expect(fields.keys, isNot(contains('isManager')));
        expect(fixture.payloads.last, contains('filename="回复.png"'));
        expect(fixture.payloads.last, contains('content-type: image/png'));
        expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
      },
    );

    test(
      'BOG ${reply ? 'reply' : 'thread'} maps true target and upload receipts',
      () async {
        final fixture = WriteFixture((r) {
          if (r.uri.path.endsWith('/upload')) {
            return response({'code': 200, 'pic': 'uploaded.png'});
          }
          if (Uri.decodeComponent(r.uri.path) == '/f/时间线/1') {
            return response(bogPage());
          }
          if (r.method == 'GET') {
            return response(
              bogForm(reply: reply),
              headers: {
                'set-cookie': ['session=current; Path=/'],
              },
            );
          }
          return response({'code': 1});
        });
        final repo = BogAdapter(
          transport: fixture.client(),
          cookie: 'bog_master=master#id; bog_sel=shadow',
        );
        final media = await repo.upload(picture(), 'image', (_, _) {});
        await repo.publish(
          body: '>>Po.101\n正文 & = +',
          boardId: 0,
          boardKey: '综合版',
          threadId: reply ? 100 : null,
          media: [media],
        );
        final post = fixture.requests.last;
        expect(post.uri.path, '/post/post');
        expect(
          post.headers['Cookie'],
          'bog_master=master#id; bog_sel=shadow; session=current',
        );
        expect(post.headers.containsKey('Authorization'), isFalse);
        final fields = Uri.splitQueryString(post.data as String);
        expect(fields[reply ? 'res' : 'forum'], reply ? '100' : '1');
        expect(fields[reply ? 'forum' : 'res'], isNull);
        expect(fields['comment'], '>>Po.101\n正文 & = +');
        expect(fields['img[]'], 'uploaded.png');
        expect(fields['title'], isNull);
        expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(2));
      },
    );
  }

  test(
    'preflight rejects foreign, ambiguous, mismatched, disabled and challenged forms',
    () async {
      final original = xForm();
      final cases = <String, String>{
        original.replaceFirst('/Home/', 'https://evil.test/Home/'): 'response',
        original.replaceFirst('value="100"', 'value="101"'): 'response',
        original.replaceFirst('name="__hash__"', 'name="unknown"'): 'response',
        '$original$original': 'response',
        original.replaceFirst('</form>', '<input name="captcha"></form>'):
            'challenge',
        original.replaceFirst('maxlength="10000"', 'maxlength="1"'): 'invalid',
        original.replaceFirst('<textarea', '<textarea disabled'): 'response',
        original
                .replaceFirst('<textarea', '<fieldset disabled><textarea')
                .replaceFirst('</textarea>', '</textarea></fieldset>'):
            'response',
        original.replaceFirst('.html"', '.html?redirect=evil"'): 'response',
        original.replaceFirst(
          '<input type="hidden" name="resto"',
          '<input type="hidden" name="resto" value="100"><input type="hidden" name="resto"',
        ): 'response',
      };
      for (final entry in cases.entries) {
        final fixture = WriteFixture((_) => response(entry.key));
        await expectLater(
          XAdapter(
            transport: fixture.client(),
            userhash: 'secret',
          ).publish(body: '正文', boardId: 4, threadId: 100),
          failure(entry.value),
        );
        expect(fixture.requests.map((r) => r.method), ['GET']);
      }
    },
  );

  test('BOG new thread rejects wrong board and reply form contamination', () {
    for (final source in [
      bogForm(reply: false).replaceFirst('综合版', '其他板块'),
      bogForm(reply: false).replaceFirst(
        '</form>',
        '<input name="res" type="hidden" value="100"></form>',
      ),
      bogForm(reply: false).replaceFirst('name="forum"', 'name="other"'),
      '${bogForm(reply: false)}${bogForm(reply: false)}',
    ]) {
      expect(
        () => ExternalWriter.parseForm(
          source,
          page: Uri.parse('https://bog.ac/f/综合版/1'),
          site: 'bog',
          body: '正文',
          title: '',
          boardId: 0,
          boardName: '综合版',
        ),
        failure('response'),
      );
    }
    expect(
      () => ExternalWriter.parseForm(
        bogForm(reply: false),
        page: Uri.parse('https://bog.ac/f/综合版/1'),
        site: 'bog',
        body: '正文',
        title: 'disabled title',
        boardId: 0,
        boardName: '综合版',
      ),
      failure('invalid'),
    );
  });

  test(
    'result parsing never treats arbitrary HTTP 200 or foreign codes as success',
    () {
      for (final value in [
        '回复成功',
        '<p class="success">回复成功？并没有</p>',
        '<script>回复成功</script>',
      ]) {
        expect(() => ExternalWriter.xResult(value), failure('unknown_result'));
      }
      for (final code in [200, 6001, 0, null]) {
        expect(ExternalWriter.bogError(code).code, 'unknown_result');
      }
      for (final entry in {
        101: 'challenge',
        1102: 'duplicate',
        1101: 'not_found',
        4: 'rate_limit',
        1000: 'auth',
      }.entries) {
        expect(ExternalWriter.bogError(entry.key).code, entry.value);
      }
      expect(
        () => ExternalWriter.xResult('<p class="error">secret-cookie 饼干无效</p>'),
        throwsA(
          isA<ForumFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret-cookie')),
          ),
        ),
      );
    },
  );

  test(
    'failed POST has unknown result, no retry and no leaked redirect',
    () async {
      for (final status in [302, 500]) {
        final fixture = WriteFixture(
          (r) => r.method == 'GET'
              ? response(xForm())
              : response(
                  'secret-cookie',
                  status: status,
                  headers: {
                    'location': ['https://evil.test/'],
                  },
                ),
        );
        await expectLater(
          XAdapter(
            transport: fixture.client(),
            userhash: 'secret-cookie',
          ).publish(body: '正文', boardId: 4, threadId: 100),
          failure('unknown_result'),
        );
        expect(fixture.requests, hasLength(2));
        expect(
          fixture.requests.every((r) => r.uri.host == 'www.nmbxd1.com'),
          isTrue,
        );
      }
      final fixture = WriteFixture((r) {
        if (r.method == 'GET') return response(xForm());
        throw DioException(
          requestOptions: r,
          type: DioExceptionType.receiveTimeout,
        );
      });
      await expectLater(
        XAdapter(
          transport: fixture.client(),
          userhash: 'secret',
        ).publish(body: '正文', boardId: 4, threadId: 100),
        failure('unknown_result'),
      );
      expect(fixture.requests, hasLength(2));
    },
  );

  test(
    'missing or changed identity, invalid payloads and foreign attachments make no requests',
    () async {
      final fixture = WriteFixture((_) => throw StateError('must not request'));
      await expectLater(
        XAdapter(transport: fixture.client()).publish(body: '正文', boardId: 4),
        failure('auth'),
      );
      final x = XAdapter(transport: fixture.client(), userhash: 'selected');
      await expectLater(
        x.publish(body: '正文', boardId: 4, expectedToken: 'other'),
        failure('auth'),
      );
      await expectLater(
        x.publish(body: '岛' * 8192, boardId: 4),
        failure('invalid'),
      );
      await expectLater(
        x.publish(body: '正文', boardId: 4, files: [picture(), picture()]),
        failure('invalid'),
      );
      await expectLater(
        x.publish(
          body: '正文',
          boardId: 4,
          files: [XFile.fromData(utf8.encode('<html>'), name: 'fake.jpg')],
        ),
        failure('invalid'),
      );
      final bog = BogAdapter(
        transport: fixture.client(),
        cookie: 'bog_master=m; bog_sel=s',
      );
      await expectLater(
        bog.publish(
          body: '正文',
          boardId: 0,
          threadId: 100,
          media: [
            const MediaItem(
              id: 'a.png',
              url: 'https://other.test/image_pre/thumb/a.png',
              thumbnailUrl: '',
              type: 'image',
            ),
          ],
        ),
        failure('invalid'),
      );
      expect(fixture.requests, isEmpty);
    },
  );

  test('custom X endpoint never falls back to official write host', () async {
    final site = ForumSite(
      id: 'x',
      name: '私有实例',
      endpoint: 'https://custom.test/api/',
      webUrl: 'https://evil.test/',
    );
    final fixture = WriteFixture(
      (r) =>
          response(r.method == 'GET' ? xForm() : '<p class="success">回复成功</p>'),
    );
    await XAdapter(
      site: site,
      transport: fixture.client(),
      userhash: 'custom',
    ).publish(body: '正文', boardId: 4, threadId: 100);
    expect(fixture.requests.map((r) => r.uri.host).toSet(), {'custom.test'});
  });

  test('disposing the source during preflight prevents submission', () async {
    final gate = Completer<ResponseBody>();
    final fixture = WriteFixture((_) => gate.future);
    final repo = XAdapter(transport: fixture.client(), userhash: 'selected');
    final request = repo.publish(body: '正文', boardId: 4, threadId: 100);
    final checked = expectLater(request, throwsA(isA<ForumFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    repo.dispose();
    gate.complete(response(xForm()));
    await checked;
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
  });
}
