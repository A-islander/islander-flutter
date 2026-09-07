import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/features/forum/forum_post_view.dart';
import 'package:islander_flutter/shared/widgets/pixel_shore.dart';

import 'support/forum_fixture.dart';

class DenseForumFixture extends ForumFixture {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path != '/forum/indexLast') {
      return super.fetch(options, stream, cancelFuture);
    }
    requests.add(options);
    final page = options.queryParameters['page'] as int? ?? 0;
    return ResponseBody.fromString(
      jsonEncode({
        'code': 200,
        'data': {
          'count': 60,
          'list': List.generate(20, (index) {
            final id = 100 + page * 20 + index;
            return {
              ...post(id),
              'value': List.filled(index % 3 + 2, '测试长正文，保持可变高度。').join('\n'),
              'lastReplyArr': List.generate(
                5,
                (i) => post(1000 + id * 5 + i, follow: id),
              ),
            };
          }),
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

ScrollController controller(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byKey(const Key('forum-scroll')))
    .controller!;

class DeepReplyFixture extends ForumFixture {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    final target =
        options.uri.path == '/forum/get' &&
        options.queryParameters['postId'] == 115;
    if (!target && options.uri.path != '/forum/list') {
      return super.fetch(options, stream, cancelFuture);
    }
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'code': 200,
        'data': target
            ? post(115, follow: 10)
            : {
                'count': 20,
                'list': [
                  post(10),
                  ...List.generate(19, (i) => post(101 + i, follow: 10)),
                ],
              },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  testWidgets('direct reply links still reveal a deep variable-height target', (
    tester,
  ) async {
    await pumpForum(tester, DeepReplyFixture(), size: const Size(390, 640));
    AppRouter.router.push('/post/115');
    await pumpFrames(tester);
    final target = find.byWidgetPredicate(
      (w) => w is ForumPostView && w.post.id == 115,
    );
    expect(target, findsOneWidget);
    expect(tester.getTopLeft(target).dy, inExclusiveRange(64, 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a full API page builds only visible and nearby posts', (
    tester,
  ) async {
    await pumpForum(tester, DenseForumFixture(), size: const Size(390, 640));
    final rows = find.byType(ForumPostView);
    expect(rows.evaluate().length, inExclusiveRange(0, 10));
    expect(find.byKey(const ValueKey('post-119')), findsNothing);
    final delegate =
        tester
                .widget<SliverList>(
                  find.byKey(const ValueKey('forum-post-list')),
                )
                .delegate
            as SliverChildBuilderDelegate;
    expect(delegate.childCount, 20);
    controller(tester).jumpTo(2500);
    await pumpFrames(tester);
    expect(rows.evaluate().length, lessThan(10));
    expect(find.byKey(const ValueKey('post-100')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'in-bounds list dragging tracks finger displacement without easing',
    (tester) async {
      final fixture = DenseForumFixture();
      await pumpForum(tester, fixture, size: const Size(390, 640));
      final scroll = controller(tester);
      scroll.jumpTo(600);
      await pumpFrames(tester);
      final reads = fixture.requests.length;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('forum-scroll'))),
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      final before = scroll.offset;
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      expect(scroll.offset - before, closeTo(80, .01));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(scroll.offset - before, closeTo(50, .01));
      await gesture.cancel();
      await pumpFrames(tester);
      expect(fixture.requests.length, reads);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('two dense prepends retain the visible row state and position', (
    tester,
  ) async {
    final fixture = DenseForumFixture();
    await pumpForum(tester, fixture, size: const Size(390, 640));
    await tester.tap(find.byKey(const Key('page-jump-trigger')));
    await pumpFrames(tester);
    await tester.enterText(find.byKey(const Key('page-jump-input')), '3');
    await tester.tap(find.byKey(const Key('page-jump-submit')));
    await pumpFrames(tester);
    final row = find.byKey(const ValueKey('post-140'));
    final state = tester.state(row);
    final original = tester.getTopLeft(row).dy;
    for (var i = 0; i < 2; i++) {
      // Exercise layout/state retention independently of scrolling to the
      // previous-page control, which is now far above the visible row.
      final previous = find.byKey(
        const Key('load-previous-button'),
        skipOffstage: false,
      );
      expect(previous, findsOneWidget);
      tester.widget<TextButton>(previous).onPressed!();
      await pumpFrames(tester);
      expect(tester.state(row), same(state));
      expect(tester.getTopLeft(row).dy, closeTo(original, 1));
    }
    expect(find.text('1–3 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shore animation repaints without replacing its painter each frame',
    (tester) async {
      Widget host(bool reduceMotion) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: const Center(child: PixelShore(height: 112)),
        ),
      );
      await tester.pumpWidget(host(false));
      final paint = find.descendant(
        of: find.byType(PixelShore),
        matching: find.byType(CustomPaint),
      );
      final painter = tester.widget<CustomPaint>(paint).painter!;
      var ticks = 0;
      void count() => ticks++;
      painter.addListener(count);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget<CustomPaint>(paint).painter, same(painter));
      }
      expect(ticks, greaterThan(0));
      painter.removeListener(count);
      await tester.pumpWidget(host(true));
      final stillPainter = tester.widget<CustomPaint>(paint).painter!;
      ticks = 0;
      stillPainter.addListener(count);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticks, 0);
      stillPainter.removeListener(count);
      expect(tester.takeException(), isNull);
    },
  );
}
