import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'support/forum_fixture.dart';

ScrollController scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byKey(const Key('forum-scroll')))
    .controller!;

Future<void> swipeUp(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('forum-scroll')),
    const Offset(0, -500),
  );
  await pumpFrames(tester);
}

int reads(ForumFixture fixture, int page) => fixture.requests
    .where(
      (request) =>
          request.uri.path == '/forum/indexLast' &&
          request.queryParameters['page'] == page,
    )
    .length;

void main() {
  testWidgets(
    'end-of-list refresh reloads the starting page and resets the range',
    (tester) async {
      final fixture = ForumFixture()..listCount = 21;
      await pumpForum(tester, fixture, size: const Size(390, 640));
      expect(find.byKey(const Key('end-refresh')), findsNothing);
      await swipeUp(tester);
      expect(find.text('1–2 / 2'), findsOneWidget);
      final button = find.byKey(const Key('end-refresh'));
      await tester.ensureVisible(button);
      await pumpFrames(tester);
      expect(find.text('已经到底了'), findsNothing);
      expect(
        find.descendant(of: button, matching: find.text('已经到底了，点击刷新')),
        findsOneWidget,
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      await pumpFrames(tester);
      expect(reads(fixture, 0), 2);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('测试主串 20'), findsNothing);
      expect(find.byKey(const Key('end-refresh')), findsNothing);
      expect(scroll(tester).offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('merged end refresh fits a narrow phone with large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpForum(
      tester,
      ForumFixture()..listCount = 1,
      size: const Size(320, 720),
    );
    await tester.ensureVisible(find.byKey(const Key('end-refresh')));
    await pumpFrames(tester);
    expect(find.text('已经到底了，点击刷新'), findsOneWidget);
    expect(find.text('已经到底了'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh discards a pending append', (tester) async {
    final gate = Completer<void>();
    final fixture = ForumFixture()
      ..listCount = 61
      ..nextPageGate = gate.future;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await swipeUp(tester);
    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('forum-refresh')),
    );
    final refreshed = refresh.onRefresh();
    await pumpFrames(tester);
    await refreshed;
    gate.complete();
    await pumpFrames(tester);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('测试主串 20'), findsNothing);
    expect(scroll(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching boards discards the old timeline append', (
    tester,
  ) async {
    final gate = Completer<void>();
    final fixture = ForumFixture()
      ..listCount = 61
      ..nextPageGate = gate.future;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await swipeUp(tester);
    AppRouter.router.go('/plate/2');
    await pumpFrames(tester);
    gate.complete();
    await pumpFrames(tester);
    expect(find.text('技术版'), findsWidgets);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('测试主串 20'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from a thread preserves appended pages and offset', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await swipeUp(tester);
    final controller = scroll(tester);
    final offset = controller.offset;
    AppRouter.router.push('/post/20');
    await pumpFrames(tester);
    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
    expect(find.text('1–2 / 4'), findsOneWidget);
    expect(controller.offset, closeTo(offset, .1));
    expect(reads(fixture, 1), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scroll appends once, deduplicates live rows and stops at last page',
    (tester) async {
      final gate = Completer<void>();
      final fixture = ForumFixture()
        ..listCount = 41
        ..duplicatePrevious = true
        ..nextPageGate = gate.future;
      await pumpForum(tester, fixture, size: const Size(390, 640));
      await swipeUp(tester);
      expect(reads(fixture, 1), 1);
      expect(find.byKey(const Key('load-more-progress')), findsOneWidget);
      await swipeUp(tester);
      expect(reads(fixture, 1), 1);
      gate.complete();
      await pumpFrames(tester);
      expect(scroll(tester).offset, greaterThan(0));
      expect(find.text('1–2 / 3'), findsOneWidget);
      scroll(tester).jumpTo(0);
      await pumpFrames(tester);
      expect(find.text('测试主串 10'), findsOneWidget);
      expect(find.text('测试主串 20'), findsOneWidget);
      await swipeUp(tester);
      expect(reads(fixture, 2), 1);
      expect(find.text('1–3 / 3'), findsOneWidget);
      await swipeUp(tester);
      expect(find.byKey(const Key('load-more-end')), findsOneWidget);
      expect(reads(fixture, 3), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('append failure keeps rows and retries only when requested', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 41;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    fixture.failRead = true;
    await swipeUp(tester);
    expect(find.byKey(const Key('load-more-retry')), findsOneWidget);
    expect(find.text('测试主串 10'), findsOneWidget);
    await swipeUp(tester);
    expect(reads(fixture, 1), 1);
    fixture.failRead = false;
    await tester.ensureVisible(find.byKey(const Key('load-more-retry')));
    await tester.tap(find.byKey(const Key('load-more-retry')));
    await pumpFrames(tester);
    expect(reads(fixture, 1), 2);
    expect(find.text('1–2 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling from the middle prepends before first-page refresh', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await tester.tap(find.byKey(const Key('page-jump-trigger')));
    await pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('page-jump-input')), '2');
    await tester.tap(find.byKey(const Key('page-jump-submit')));
    await pumpFrames(tester);
    await swipeUp(tester);
    expect(find.text('2–3 / 4'), findsOneWidget);
    scroll(tester).jumpTo(0);
    await pumpFrames(tester);
    await tester.drag(
      find.byKey(const Key('forum-scroll')),
      const Offset(0, 330),
    );
    await pumpFrames(tester);
    expect(find.text('1–3 / 4'), findsOneWidget);
    expect(reads(fixture, 1), 1);
    scroll(tester).jumpTo(0);
    await pumpFrames(tester);
    await tester.drag(
      find.byKey(const Key('forum-scroll')),
      const Offset(0, 330),
    );
    await pumpFrames(tester);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('测试主串 30'), findsNothing);
    expect(reads(fixture, 0), 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual jump ignores an older in-flight append', (tester) async {
    final gate = Completer<void>();
    final fixture = ForumFixture()
      ..listCount = 61
      ..nextPageGate = gate.future;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await swipeUp(tester);
    await tester.tap(find.byKey(const Key('page-jump-trigger')));
    await pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('page-jump-input')), '3');
    await tester.tap(find.byKey(const Key('page-jump-submit')));
    await pumpFrames(tester);
    gate.complete();
    await pumpFrames(tester);
    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.text('测试主串 30'), findsOneWidget);
    expect(find.text('测试主串 20'), findsNothing);
    expect(scroll(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread replies append without duplicating the root', (
    tester,
  ) async {
    final fixture = ForumFixture()..replyCount = 41;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    await swipeUp(tester);
    expect(fixture.requests.last.uri.path, '/forum/list');
    expect(fixture.requests.last.queryParameters['page'], 1);
    scroll(tester).jumpTo(0);
    await pumpFrames(tester);
    expect(find.text('讨论正文 10'), findsOneWidget);
    expect(find.textContaining('回复正文 11'), findsOneWidget);
    scroll(tester).jumpTo(scroll(tester).position.maxScrollExtent);
    await pumpFrames(tester);
    expect(find.textContaining('回复正文 31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty next page stops requests even with stale server count', (
    tester,
  ) async {
    final fixture = ForumFixture()
      ..listCount = 61
      ..emptyNextPage = true;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await swipeUp(tester);
    expect(find.byKey(const Key('load-more-end')), findsOneWidget);
    await swipeUp(tester);
    expect(reads(fixture, 1), 1);
    expect(reads(fixture, 2), 0);
    expect(tester.takeException(), isNull);
  });
}
