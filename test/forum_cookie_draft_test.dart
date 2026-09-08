import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/app.dart';
import 'package:islander_flutter/main.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'support/forum_fixture.dart';

ProviderContainer container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(IslanderApp)));
String body(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('composer-body')))
    .controller!
    .text;
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await pumpFrames(tester);
  await tester.tap(finder);
  await pumpFrames(tester);
}

Future<void> openEditor(WidgetTester tester) =>
    tap(tester, find.byKey(const Key('fab-compose')));
Future<void> closeEditor(WidgetTester tester) =>
    tap(tester, find.byTooltip('关闭编辑'));

void main() {
  testWidgets(
    'cookie copy requires confirmation and never previews the token',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpForum(
        tester,
        ForumFixture(),
        authenticated: true,
        size: const Size(320, 720),
      );
      final scope = container(tester);
      final cookie = scope.read(authProvider).current!;
      await tap(tester, find.byKey(const Key('cookie-button')));
      Future<void> requestCopy() async {
        await tap(tester, find.byKey(ValueKey('cookie-menu-${cookie.id}')));
        await tap(tester, find.text('复制饼干'));
        expect(find.text('复制饼干到剪贴板？'), findsOneWidget);
        expect(find.textContaining('ID ${cookie.userId}'), findsWidgets);
        expect(find.textContaining(cookie.token), findsNothing);
        expect(copied, isEmpty);
      }

      await requestCopy();
      await tap(tester, find.text('取消'));
      expect(copied, isEmpty);
      await requestCopy();
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(find.text('复制饼干到剪贴板？'), findsNothing);
      expect(copied, isEmpty);
      await requestCopy();
      await tap(tester, find.text('确认复制'));
      expect(copied, [cookie.token]);
      expect(find.text('饼干已复制，请勿分享给他人'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiple cookies import, switch, label and logout without losing stored entries',
    (tester) async {
      await pumpForum(
        tester,
        ForumFixture(),
        authenticated: true,
        size: const Size(320, 844),
      );
      final scope = container(tester);
      final first = scope.read(authProvider).current!;
      await tap(tester, find.byKey(const Key('cookie-button')));
      await tester.enterText(
        find.byKey(const Key('cookie-token')),
        'second-cookie',
      );
      await tap(tester, find.byKey(const Key('cookie-login')));
      expect(scope.read(authProvider).cookies.length, 2);
      expect(scope.read(authProvider).token, 'second-cookie');
      await tap(tester, find.byKey(const Key('cookie-button')));
      await tap(tester, find.byKey(ValueKey('cookie-menu-${first.id}')));
      await tap(tester, find.text('修改备注'));
      await tester.enterText(find.byKey(const Key('cookie-label')), '日常饼干');
      await tap(tester, find.text('保存'));
      expect(find.text('日常饼干'), findsOneWidget);
      await tap(tester, find.byKey(ValueKey('cookie-switch-${first.id}')));
      expect(scope.read(authProvider).token, 'test-cookie');
      expect(scope.read(authProvider).cookies.length, 2);
      await tap(tester, find.byKey(const Key('cookie-button')));
      await tap(tester, find.byKey(const Key('cookie-logout')));
      expect(scope.read(authProvider).isLoggedIn, false);
      expect(scope.read(authProvider).cookies.length, 2);
      expect(find.text('日常饼干'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed switch keeps current identity and marks only invalid saved cookie',
    (tester) async {
      final fixture = ForumFixture();
      await pumpForum(tester, fixture, authenticated: true);
      final scope = container(tester);
      await scope
          .read(authProvider.notifier)
          .setToken('second-cookie', userId: 8);
      final first = scope.read(authProvider).cookies.first;
      await pumpFrames(tester);
      fixture.failAuth = true;
      await tap(tester, find.byKey(const Key('cookie-button')));
      await tap(tester, find.byKey(ValueKey('cookie-switch-${first.id}')));
      expect(scope.read(authProvider).token, 'second-cookie');
      expect(scope.read(authProvider).cookies.first.invalid, true);
      expect(find.textContaining('已失效，请验证'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new-thread title body and uploaded attachments restore; success clears only that draft',
    (tester) async {
      final fixture = ForumFixture();
      await pumpForum(tester, fixture, authenticated: true);
      final scope = container(tester);
      final store = scope.read(storageServiceProvider);
      final id = scope.read(authProvider).activeId!;
      final key = store.draftKey(id, 1, null);
      await store.saveDraft(key, {
        'version': 1,
        'title': '缓存标题',
        'body': '缓存正文 No.10',
        'media': [
          {
            'id': 'm1',
            'url': 'https://media.example/a.png',
            'thumbnailUrl': 'https://media.example/a.png',
            'type': 'image',
          },
        ],
      });
      await openEditor(tester);
      expect(body(tester), '缓存正文 No.10');
      expect(find.text('缓存标题'), findsOneWidget);
      expect(find.text('附件 1'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('composer-body')),
        '接着写 (´▽｀)',
      );
      await closeEditor(tester);
      expect(store.readDraft(key)!['body'], '接着写 (´▽｀)');
      await openEditor(tester);
      expect(body(tester), '接着写 (´▽｀)');
      fixture.failPublish = true;
      await tap(tester, find.byKey(const Key('composer-submit')));
      expect(store.readDraft(key), isNotNull);
      expect(find.text('发布失败，请重试'), findsOneWidget);
      fixture.failPublish = false;
      await tap(tester, find.byKey(const Key('composer-submit')));
      expect(store.readDraft(key), isNull);
      expect(find.byKey(const Key('composer-body')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching boards saves and restores each board independently', (
    tester,
  ) async {
    await pumpForum(tester, ForumFixture(), authenticated: true);
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('composer-body')), '综合草稿');
    await tap(tester, find.byKey(const ValueKey('composer-board-1-0')));
    await tap(tester, find.text('技术版').last);
    expect(body(tester), '');
    await tester.enterText(find.byKey(const Key('composer-body')), '技术草稿');
    await tap(tester, find.byKey(const ValueKey('composer-board-2-1')));
    await tap(tester, find.text('综合版').last);
    expect(body(tester), '综合草稿');
    await closeEditor(tester);
    final scope = container(tester);
    final store = scope.read(storageServiceProvider);
    expect(
      store.readDraft(
        store.draftKey(scope.read(authProvider).activeId!, 2, null),
      )!['body'],
      '技术草稿',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching cookies blocks open composer and preserves separate drafts',
    (tester) async {
      final fixture = ForumFixture();
      await pumpForum(tester, fixture, authenticated: true);
      final scope = container(tester);
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('composer-body')), '原饼干的草稿');
      await scope
          .read(authProvider.notifier)
          .setToken('second-cookie', userId: 8);
      await pumpFrames(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('composer-submit')))
            .onPressed,
        isNull,
      );
      await closeEditor(tester);
      await openEditor(tester);
      expect(body(tester), '');
      await tester.enterText(
        find.byKey(const Key('composer-body')),
        '第二块饼干的草稿',
      );
      await closeEditor(tester);
      await scope
          .read(authProvider.notifier)
          .setToken('test-cookie', userId: 7);
      await pumpFrames(tester);
      await openEditor(tester);
      expect(body(tester), '原饼干的草稿');
      expect(
        fixture.requests.where((r) => r.uri.path == '/forum/post'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reply draft persists on system back and explicit clearing requires confirmation',
    (tester) async {
      await pumpForum(
        tester,
        ForumFixture(),
        authenticated: true,
        size: const Size(390, 844),
      );
      AppRouter.router.push('/post/10');
      await pumpFrames(tester);
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('composer-body')),
        '回复草稿 No.11',
      );
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      await openEditor(tester);
      expect(body(tester), '回复草稿 No.11');
      await tap(tester, find.byKey(const Key('draft-clear')));
      await tap(tester, find.text('取消'));
      expect(body(tester), '回复草稿 No.11');
      await tap(tester, find.byKey(const Key('draft-clear')));
      await tap(tester, find.text('清空'));
      expect(body(tester), '');
      await closeEditor(tester);
      final scope = container(tester);
      final store = scope.read(storageServiceProvider);
      expect(
        store.readDraft(
          store.draftKey(scope.read(authProvider).activeId!, 1, 10),
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
