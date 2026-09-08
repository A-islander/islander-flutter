import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:islander_flutter/app.dart';
import 'package:islander_flutter/main.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';
import 'package:islander_flutter/features/forum/application/external_identity.dart';
import 'package:islander_flutter/features/forum/application/site_scope.dart';
import 'package:islander_flutter/features/forum/data/adapters/x_adapter.dart';
import 'package:islander_flutter/features/forum/data/adapters/bog_adapter.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'package:islander_flutter/features/forum/forum_composer.dart';
import 'package:islander_flutter/features/forum/external_cookie_sheet.dart';
import 'external_adapter_test.dart' show xPost, bogPage;
import 'external_posting_test.dart'
    show WriteFixture, response, xForm, bogForm, png;
import 'support/forum_fixture.dart';
import 'forum_cookie_draft_test.dart' show tap, body, openEditor, closeEditor;

class ComposeFixture {
  var fail = true;
  late final http = WriteFixture((r) {
    if (r.method == 'POST') {
      if (r.uri.path == '/post/upload') {
        return response({'code': 200, 'pic': 'received.png'});
      }
      if (r.uri.path == '/post/post') return response({'code': fail ? 101 : 1});
      return response('<p class="success">回复成功</p>');
    }
    if (r.uri.host == 'bog.ac') {
      final path = Uri.decodeComponent(r.uri.path);
      if (path == '/f/综合版/1') {
        return response('${bogPage(more: false)}${bogForm(reply: false)}');
      }
      return response(
        bogPage(
          more: false,
        ).replaceFirst('</nav>', '<a href="/f/技术版">技术版</a></nav>'),
      );
    }
    if (r.uri.host == 'www.nmbxd1.com') return response(xForm());
    switch (r.uri.pathSegments.last) {
      case 'getForumList':
        return response([
          {
            'forums': [
              {'id': 4, 'name': '综合版1'},
            ],
          },
        ]);
      case 'thread':
        return response({
          ...xPost(100, replies: 1),
          'Replies': [xPost(101)],
        });
      case 'getTimelineList':
        return response([
          {'id': 1, 'max_page': 10},
        ]);
      default:
        return response([xPost(100)]);
    }
  });
}

class MemoryPicker extends ImagePicker {
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async => [XFile.fromData(png, path: '/fixture/test.png')];
}

Future<({ProviderContainer container, StorageService storage})> setup(
  WidgetTester tester,
  ComposeFixture fixture,
  ForumSite site, {
  bool reply = true,
  bool authenticated = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'token': 'islander-only',
    'name': '岛民岛身份',
    'userId': 7,
  });
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.initialize();
  final container = ProviderContainer(
    overrides: [
      storageServiceProvider.overrideWithValue(storage),
      forumImagePickerProvider.overrideWithValue(MemoryPicker()),
      dioClientProvider.overrideWithValue(ForumFixture().client()),
      externalRepositoryProvider(site.id).overrideWith((ref) {
        final token =
            ref.watch(externalIdentityProvider(site)).asData?.value.token ?? '';
        final repo = site.id == 'x'
            ? XAdapter(userhash: token, transport: fixture.http.client())
            : BogAdapter(cookie: token, transport: fixture.http.client());
        ref.onDispose(repo.dispose);
        return repo;
      }),
    ],
  );
  addTearDown(container.dispose);
  final notifier = container.read(externalIdentityProvider(site).notifier);
  await notifier.ready;
  if (authenticated) {
    await notifier.importCookie(
      site.id == 'x' ? 'x-selected' : 'bog_master=m; bog_sel=s',
      '外站日常',
      verify: (_) async {},
    );
  }
  AppRouter.router.go(site.route(reply ? '/post/100' : '/plate/0'));
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const IslanderApp()),
  );
  await pumpFrames(tester);
  return (container: container, storage: storage);
}

Future<void> confirm(WidgetTester tester) async {
  await tap(tester, find.byKey(const Key('composer-submit')));
  await tap(tester, find.byKey(const Key('external-publish-confirm')));
}

void main() {
  testWidgets(
    'removing the identity while editing does not resurrect deleted drafts on close',
    (tester) async {
      final fixture = ComposeFixture();
      final scope = await setup(tester, fixture, ForumSite.x);
      final id = scope.container
          .read(externalIdentityProvider(ForumSite.x))
          .asData!
          .value
          .activeId!;
      final key = scope.storage.externalDraftKey(ForumSite.x, id, '', 100);
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('composer-body')),
        '稍后应被删除的草稿',
      );
      await pumpFrames(tester);
      expect(scope.storage.readDraft(key), isNotNull);
      await scope.container
          .read(externalIdentityProvider(ForumSite.x).notifier)
          .remove(id);
      await pumpFrames(tester);
      await closeEditor(tester);
      expect(scope.storage.readDraft(key), isNull);
      expect(fixture.http.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'X quoted reply keeps source and cookie through root navigator sheet; confirms before writing',
    (tester) async {
      final fixture = ComposeFixture();
      final scope = await setup(tester, fixture, ForumSite.x);
      final id = scope.container
          .read(externalIdentityProvider(ForumSite.x))
          .asData!
          .value
          .activeId!;
      final key = scope.storage.externalDraftKey(ForumSite.x, id, '4', 100);
      await tap(tester, find.byKey(const ValueKey('post-actions-101')));
      expect(find.textContaining('SAGE'), findsNothing);
      await tap(tester, find.text('引用回复'));
      expect(body(tester), '>>No.101 ');
      expect(find.text('X 岛 · 使用：外站日常'), findsOneWidget);
      expect(find.byTooltip('添加视频'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('composer-body')),
        '>>No.101\nX 回复',
      );
      await tap(tester, find.byKey(const Key('composer-submit')));
      expect(find.text('确认发布到X 岛？'), findsOneWidget);
      expect(fixture.http.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(
        fixture.http.requests.where((r) => r.uri.host == 'www.nmbxd1.com'),
        isEmpty,
      );
      await tap(tester, find.text('继续编辑'));
      expect(body(tester), '>>No.101\nX 回复');
      await confirm(tester);
      final posts = fixture.http.requests
          .where((r) => r.method == 'POST')
          .toList();
      expect(posts, hasLength(1));
      expect(posts.single.uri.host, 'www.nmbxd1.com');
      expect(posts.single.headers['Cookie'], 'userhash=x-selected');
      expect(posts.single.headers.containsKey('Authorization'), isFalse);
      expect(scope.container.read(authProvider).token, 'islander-only');
      expect(scope.storage.readDraft(key), isNull);
      expect(find.byKey(const Key('composer-body')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BOG failed new thread persists uploaded receipt; reopen and retry does not upload again',
    (tester) async {
      final fixture = ComposeFixture();
      final scope = await setup(tester, fixture, ForumSite.bog, reply: false);
      final id = scope.container
          .read(externalIdentityProvider(ForumSite.bog))
          .asData!
          .value
          .activeId!;
      final key = scope.storage.externalDraftKey(
        ForumSite.bog,
        id,
        '综合版',
        null,
      );
      await scope.storage.saveDraft(key, {
        'version': 1,
        'title': '',
        'body': 'BOG 新串',
      });
      await openEditor(tester);
      expect(body(tester), 'BOG 新串');
      await tap(tester, find.byTooltip('添加图片'));
      expect(find.text('待发送图片 1'), findsOneWidget);
      expect(fixture.http.requests.where((r) => r.method == 'POST'), isEmpty);
      await confirm(tester);
      expect(find.textContaining('BOG 要求验证码'), findsOneWidget);
      expect(scope.storage.readDraft(key)!['files'], isEmpty);
      expect(
        (scope.storage.readDraft(key)!['media'] as List).single['id'],
        'received.png',
      );
      await closeEditor(tester);
      await openEditor(tester);
      expect(find.text('附件 1'), findsOneWidget);
      expect(find.text('待发送图片 1'), findsNothing);
      fixture.fail = false;
      await confirm(tester);
      expect(
        fixture.http.requests.where((r) => r.uri.path == '/post/upload'),
        hasLength(1),
      );
      expect(
        fixture.http.requests.where((r) => r.uri.path == '/post/post'),
        hasLength(2),
      );
      expect(scope.storage.readDraft(key), isNull);
      expect(find.byKey(const Key('composer-body')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'identity switch during confirmation blocks old editor and retains old draft',
    (tester) async {
      final fixture = ComposeFixture();
      final scope = await setup(tester, fixture, ForumSite.x);
      final notifier = scope.container.read(
        externalIdentityProvider(ForumSite.x).notifier,
      );
      final id = scope.container
          .read(externalIdentityProvider(ForumSite.x))
          .asData!
          .value
          .activeId!;
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('composer-body')), '旧身份草稿');
      await tap(tester, find.byKey(const Key('composer-submit')));
      await notifier.importCookie('x-new', '新的身份', verify: (_) async {});
      await pumpFrames(tester);
      await tap(tester, find.byKey(const Key('external-publish-confirm')));
      expect(fixture.http.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(find.textContaining('饼干已改变'), findsOneWidget);
      await closeEditor(tester);
      expect(
        scope.storage.readDraft(
          scope.storage.externalDraftKey(ForumSite.x, id, '', 100),
        )!['body'],
        '旧身份草稿',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Islander login does not authorize external composing', (
    tester,
  ) async {
    final fixture = ComposeFixture();
    final scope = await setup(
      tester,
      fixture,
      ForumSite.x,
      authenticated: false,
    );
    await openEditor(tester);
    expect(find.byKey(const Key('composer-body')), findsNothing);
    expect(find.byType(ExternalCookieSheet), findsOneWidget);
    expect(fixture.http.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(scope.container.read(authProvider).isLoggedIn, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'BOG string boards keep separate drafts even when both numeric IDs are zero',
    (tester) async {
      final fixture = ComposeFixture();
      final scope = await setup(tester, fixture, ForumSite.bog, reply: false);
      final id = scope.container
          .read(externalIdentityProvider(ForumSite.bog))
          .asData!
          .value
          .activeId!;
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('composer-body')), '综合草稿');
      await tap(tester, find.byKey(const ValueKey('composer-board-综合版-0')));
      await tap(tester, find.text('技术版').last);
      expect(body(tester), '');
      await tester.enterText(find.byKey(const Key('composer-body')), '技术草稿');
      await closeEditor(tester);
      final a = scope.storage.externalDraftKey(ForumSite.bog, id, '综合版', null);
      final b = scope.storage.externalDraftKey(ForumSite.bog, id, '技术版', null);
      expect(scope.storage.readDraft(a)!['body'], '综合草稿');
      expect(scope.storage.readDraft(b)!['body'], '技术草稿');
      await scope.container
          .read(externalIdentityProvider(ForumSite.bog).notifier)
          .remove(id);
      expect(scope.storage.readDraft(a), isNull);
      expect(scope.storage.readDraft(b), isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
