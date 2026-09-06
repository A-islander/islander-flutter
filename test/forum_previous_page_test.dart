import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'support/forum_fixture.dart';

ScrollController scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byKey(const Key('forum-scroll')))
    .controller!;
Future<void> jump(WidgetTester tester, String page) async {
  await tester.tap(find.byKey(const Key('page-jump-trigger')));
  await pumpFrames(tester);
  await tester.enterText(find.byKey(const Key('page-jump-input')), page);
  await tester.tap(find.byKey(const Key('page-jump-submit')));
  await pumpFrames(tester);
}

Future<void> pull(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('forum-scroll')),
    const Offset(0, 300),
  );
  await pumpFrames(tester);
}

int reads(ForumFixture fixture, int page) => fixture.requests
    .where(
      (r) =>
          r.uri.path == '/forum/indexLast' && r.queryParameters['page'] == page,
    )
    .length;

void main() {
  testWidgets(
    'first page has no previous-page hint or reserved control space',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 640));
      expect(find.text('已到第一页，下拉刷新'), findsNothing);
      expect(find.byKey(const Key('previous-page-control')), findsNothing);
      expect(find.byKey(const Key('forum-refresh')), findsOneWidget);
      expect(find.text('测试主串 10'), findsOneWidget);
      await pull(tester);
      expect(find.byKey(const Key('previous-page-control')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('final prepend removes the control without moving the read row', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await jump(tester, '2');
    final before = tester.getTopLeft(find.text('测试主串 20')).dy;
    final rowState = tester.state(find.byKey(const ValueKey('post-20')));
    tester
        .widget<TextButton>(find.byKey(const Key('load-previous-button')))
        .onPressed!();
    await pumpFrames(tester);
    expect(find.text('1–2 / 4'), findsOneWidget);
    expect(find.byKey(const Key('previous-page-control')), findsNothing);
    expect(tester.getTopLeft(find.text('测试主串 20')).dy, closeTo(before, 1));
    expect(tester.state(find.byKey(const ValueKey('post-20'))), same(rowState));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty previous page collapses the control and stops retrying', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await jump(tester, '2');
    fixture.overrideResponse = {
      'code': 200,
      'data': {'count': 61, 'list': []},
    };
    tester
        .widget<TextButton>(find.byKey(const Key('load-previous-button')))
        .onPressed!();
    await pumpFrames(tester);
    expect(find.byKey(const Key('previous-page-control')), findsNothing);
    expect(find.text('测试主串 20'), findsOneWidget);
    expect(scroll(tester).offset, 0);
    expect(reads(fixture, 0), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing a filter does not compensate the same prepend twice', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await jump(tester, '3');
    await pull(tester);
    await tester.tap(find.byTooltip('筛选与跳转'));
    await pumpFrames(tester);
    scroll(tester).jumpTo(0);
    await tester.enterText(find.byType(TextField), '30');
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextField), '');
    await pumpFrames(tester);
    expect(scroll(tester).offset, 0);
    expect(find.text('2–3 / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'prepend preserves row position, loads each previous page once, then refreshes page one',
    (tester) async {
      final fixture = ForumFixture()..listCount = 61;
      await pumpForum(tester, fixture, size: const Size(390, 640));
      await jump(tester, '3');
      final gate = Completer<void>();
      fixture.nextPageGate = gate.future;
      await pull(tester);
      expect(reads(fixture, 1), 1);
      expect(find.byKey(const Key('load-previous-progress')), findsOneWidget);
      await pull(tester);
      expect(reads(fixture, 1), 1);
      final before = tester.getTopLeft(find.text('测试主串 30')).dy;
      final rowState = tester.state(find.byKey(const ValueKey('post-30')));
      fixture.overrideResponse = {
        'code': 200,
        'data': {
          'count': 61,
          'list': List.generate(20, (index) => fixture.post(20 + index)),
        },
      };
      gate.complete();
      await pumpFrames(tester);
      fixture.overrideResponse = null;
      expect(find.text('2–3 / 4'), findsOneWidget);
      expect(tester.getTopLeft(find.text('测试主串 30')).dy, closeTo(before, 1));
      expect(reads(fixture, 2), 1);
      expect(
        tester.state(find.byKey(const ValueKey('post-30'))),
        same(rowState),
      );
      scroll(tester).jumpTo(0);
      await pumpFrames(tester);
      await pull(tester);
      expect(find.text('1–3 / 4'), findsOneWidget);
      expect(
        reads(fixture, 0),
        2,
      ); // initial page and the prepend, no refresh yet
      scroll(tester).jumpTo(0);
      await pumpFrames(tester);
      await pull(tester);
      expect(find.text('1 / 4'), findsOneWidget);
      expect(reads(fixture, 0), 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'previous-page errors keep current rows and require explicit retry',
    (tester) async {
      final fixture = ForumFixture()..listCount = 61;
      await pumpForum(tester, fixture, size: const Size(390, 640));
      await jump(tester, '3');
      fixture.failRead = true;
      await pull(tester);
      expect(find.byKey(const Key('load-previous-retry')), findsOneWidget);
      expect(find.text('测试主串 30'), findsOneWidget);
      await pull(tester);
      expect(reads(fixture, 1), 1);
      fixture.failRead = false;
      await tester.tap(find.byKey(const Key('load-previous-retry')));
      await pumpFrames(tester);
      expect(reads(fixture, 1), 2);
      expect(find.text('2–3 / 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('jump ignores an in-flight previous-page response', (
    tester,
  ) async {
    final fixture = ForumFixture()..listCount = 61;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await jump(tester, '3');
    final gate = Completer<void>();
    fixture.nextPageGate = gate.future;
    await pull(tester);
    await jump(tester, '4');
    gate.complete();
    await pumpFrames(tester);
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.text('测试主串 20'), findsNothing);
    expect(scroll(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread previous replies prepend without repeating the root', (
    tester,
  ) async {
    final fixture = ForumFixture()..replyCount = 61;
    await pumpForum(tester, fixture, size: const Size(390, 640));
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    await jump(tester, '3');
    await pull(tester);
    expect(find.text('2–3 / 4'), findsOneWidget);
    expect(fixture.requests.last.uri.path, '/forum/list');
    expect(fixture.requests.last.queryParameters['page'], 1);
    expect(find.text('讨论正文 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
