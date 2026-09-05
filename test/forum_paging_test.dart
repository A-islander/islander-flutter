import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'support/forum_fixture.dart';

void main() {
  testWidgets(
    'phone thread omits return-list link and system back retains list',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      AppRouter.router.push('/post/10');
      await pumpFrames(tester);
      expect(find.text('返回列表'), findsNothing);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(find.text('时间线'), findsWidgets);
      expect(find.text('测试主串 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop thread keeps the return-list link', (tester) async {
    await pumpForum(tester, ForumFixture());
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    expect(find.text('返回列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px toolbar opens a full-width validated page jump sheet', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture, size: const Size(320, 720));
    expect(find.byTooltip('刷新'), findsNothing);
    await tester.tap(find.byKey(const Key('page-jump-trigger')));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    final sheet = tester.getRect(find.byKey(const Key('forum-sheet-surface')));
    expect(sheet.left, 0);
    expect(sheet.right, 320);
    final input = find.byKey(const Key('page-jump-input'));
    final submit = find.byKey(const Key('page-jump-submit'));
    final previousRequests = fixture.requests.length;
    await tester.enterText(input, '5');
    await tester.tap(submit);
    await pumpFrames(tester);
    expect(find.text('请输入 1—4 之间的页码'), findsOneWidget);
    expect(fixture.requests.length, previousRequests);
    await tester.enterText(input, '2');
    await tester.tap(submit);
    await pumpFrames(tester);
    expect(find.byKey(const Key('page-jump-input')), findsNothing);
    expect(fixture.requests.last.queryParameters['page'], 1);
    expect(find.text('测试主串 20'), findsOneWidget);
    expect(find.text('2 / 4'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed jumps retry the target page rather than the old page', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture);
    expect(find.byTooltip('刷新'), findsOneWidget);
    await tester.tap(find.byKey(const Key('page-jump-trigger')));
    await pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('page-jump-input')), '3');
    fixture.failRead = true;
    await tester.tap(find.byKey(const Key('page-jump-submit')));
    await pumpFrames(tester);
    expect(find.text('加载失败，请重试'), findsOneWidget);
    fixture.failRead = false;
    await tester.tap(find.text('重试'));
    await pumpFrames(tester);
    expect(fixture.requests.last.queryParameters['page'], 2);
    expect(find.text('测试主串 30'), findsOneWidget);
  });

  testWidgets(
    'returning from a thread preserves page and reading offset; pulling loads previous page',
    (tester) async {
      final fixture = ForumFixture()..listCount = 61;
      await pumpForum(tester, fixture, size: const Size(390, 640));
      await tester.tap(find.byKey(const Key('page-jump-trigger')));
      await pumpFrames(tester);
      await tester.enterText(find.byKey(const Key('page-jump-input')), '2');
      await tester.tap(find.byKey(const Key('page-jump-submit')));
      await pumpFrames(tester);
      final controller = tester
          .widget<CustomScrollView>(find.byKey(const Key('forum-scroll')))
          .controller!;
      controller.jumpTo(100);
      await pumpFrames(tester);
      final offset = controller.offset;
      expect(offset, greaterThan(0));
      await tester.tap(find.text('测试主串 20'));
      await pumpFrames(tester);
      AppRouter.router.pop();
      await pumpFrames(tester);
      expect(find.text('2 / 4'), findsWidgets);
      expect(controller.offset, closeTo(offset, .1));
      controller.jumpTo(0);
      await pumpFrames(tester);
      final reads = fixture.requests
          .where((r) => r.uri.path == '/forum/indexLast')
          .length;
      await tester.drag(
        find.byKey(const Key('forum-scroll')),
        const Offset(0, 330),
      );
      await pumpFrames(tester);
      expect(
        fixture.requests.where((r) => r.uri.path == '/forum/indexLast').length,
        greaterThan(reads),
      );
      expect(fixture.requests.last.queryParameters['page'], 0);
      expect(find.text('1–2 / 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'latest reply action uses server count and jumps to the final page',
    (tester) async {
      final fixture = ForumFixture()..replyCount = 41;
      await pumpForum(tester, fixture, size: const Size(390, 844));
      AppRouter.router.push('/post/10');
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('page-jump-trigger')));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('page-jump-latest')));
      await pumpFrames(tester);
      expect(fixture.requests.last.uri.path, '/forum/list');
      expect(fixture.requests.last.queryParameters['page'], 2);
      expect(find.text('3 / 3'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
