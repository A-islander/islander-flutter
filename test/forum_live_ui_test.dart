import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'support/forum_fixture.dart';

void main() {
  testWidgets('deleted content is hidden from anonymous readers', (
    tester,
  ) async {
    await pumpForum(tester, ForumFixture()..deleted = true);
    expect(find.text('No.10 · 该内容已删除'), findsOneWidget);
    expect(find.text('讨论正文 10'), findsNothing);
    expect(find.text('测试主串 10'), findsNothing);
  });
  testWidgets('loads real repository data and switches pages', (tester) async {
    final fixture = ForumFixture();
    await pumpForum(tester, fixture);
    expect(find.text('测试主串 10'), findsOneWidget);
    expect(find.text('海浪之家酒吧'), findsNothing);
    await tester.ensureVisible(find.text('下一页 →'));
    await tester.tap(find.text('下一页 →'));
    await pumpFrames(tester);
    expect(find.text('测试主串 20'), findsOneWidget);
    expect(fixture.requests.last.queryParameters['page'], 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'thread root is not duplicated and No. reply routes resolve parent',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      AppRouter.router.push('/post/11');
      await pumpFrames(tester);
      expect(find.text('讨论正文 10'), findsOneWidget);
      expect(find.textContaining('回复正文 11'), findsOneWidget);
      expect(find.text('串的讨论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('anonymous compose opens cookie import instead of submitting', (
    tester,
  ) async {
    final fixture = ForumFixture();
    await pumpForum(tester, fixture, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('fab-compose')));
    await pumpFrames(tester);
    expect(find.byKey(const Key('cookie-token')), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'full-width composer preserves content on failure and retries once',
    (tester) async {
      final fixture = ForumFixture()..failPublish = true;
      await pumpForum(tester, fixture, authenticated: true);
      await tester.tap(find.byKey(const Key('fab-compose')));
      await pumpFrames(tester);
      final rect = tester.getRect(find.byKey(const Key('forum-sheet-surface')));
      expect(rect.left, 0);
      expect(rect.right, 1200);
      await tester.enterText(find.byKey(const Key('composer-title')), '新串标题');
      await tester.enterText(
        find.byKey(const Key('composer-body')),
        '测试发串 No.10',
      );
      await tester.ensureVisible(find.byKey(const Key('composer-submit')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('composer-submit')));
      await pumpFrames(tester);
      expect(find.text('发布失败，请重试'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('composer-body')))
            .controller!
            .text,
        '测试发串 No.10',
      );
      fixture.failPublish = false;
      await tester.ensureVisible(find.byKey(const Key('composer-submit')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('composer-submit')));
      await pumpFrames(tester);
      expect(find.byKey(const Key('composer-body')), findsNothing);
      final sent = fixture.requests
          .where((r) => r.uri.path == '/forum/post')
          .toList();
      expect(sent.length, 2);
      expect(sent.last.data['plateId'], 1);
      expect(sent.last.data['replyArr'], [10]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('phone reply stays usable above the keyboard', (tester) async {
    final fixture = ForumFixture();
    await pumpForum(
      tester,
      fixture,
      authenticated: true,
      size: const Size(390, 844),
    );
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    await tester.tap(find.byKey(const Key('fab-compose')));
    await pumpFrames(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(
      find.byKey(const Key('composer-body')),
      '手机回复 No.11',
    );
    await tester.ensureVisible(find.byKey(const Key('composer-submit')));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const Key('composer-submit')));
    await pumpFrames(tester);
    expect(
      fixture.requests
          .where((r) => r.uri.path == '/forum/reply')
          .single
          .data['followId'],
      10,
    );
    expect(find.byKey(const Key('composer-body')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed list loads offer retry', (tester) async {
    final fixture = ForumFixture()..failRead = true;
    await pumpForum(tester, fixture);
    expect(find.text('加载失败，请重试'), findsOneWidget);
    fixture.failRead = false;
    await tester.tap(find.text('重试'));
    await pumpFrames(tester);
    expect(find.text('测试主串 10'), findsOneWidget);
  });
}
