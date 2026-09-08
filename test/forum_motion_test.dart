import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/features/forum/forum_motion.dart';
import 'package:islander_flutter/features/forum/forum_screen.dart';
import 'package:islander_flutter/shared/widgets/pixel_shore.dart';
import 'forum_back_transition_test.dart' show backEvent;
import 'support/forum_fixture.dart';

Finder fab(String label) => find.widgetWithText(FloatingActionButton, label);
Finder thread(int id) =>
    find.byWidgetPredicate((w) => w is ForumScreen && w.postId == id);

void main() {
  testWidgets(
    'waves share a phase across navigation and remain visible behind dialogs',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      Animation<double> phase() {
        final paint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(PixelShore),
            matching: find.byType(CustomPaint),
          ),
        );
        return (paint.painter as dynamic).animation as Animation<double>;
      }

      final first = phase();
      AppRouter.router.push('/post/10');
      await pumpFrames(tester);
      expect(identical(phase(), first), isTrue);
      final context = tester.element(thread(10));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('测试确认')),
      );
      await pumpFrames(tester);
      expect(find.byType(PixelShore), findsOneWidget);
      expect(identical(phase(), first), isTrue);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      AppRouter.router.pop();
      await pumpFrames(tester);
      expect(identical(phase(), first), isTrue);
    },
  );

  testWidgets('reduced motion disables button spring and reading transforms', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
    AppRouter.router.push('/post/10');
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(fab('回复')).right, closeTo(374, .1));
    expect(find.byKey(const ValueKey('forum-reading-scale')), findsNothing);
    await pumpFrames(tester);
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: .6);
    expect(tester.getRect(fab('回复')).right, closeTo(374, .1));
    await backEvent(tester, 'cancelBackGesture');
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });
  test('spring peaks have a linear amplitude envelope and stop exactly', () {
    expect(forumFabBounce(0), 0);
    expect(forumFabBounce(1), 0);
    for (final t in [.125, .375, .625, .875]) {
      expect(forumFabBounce(t).abs(), closeTo(6 * (1 - t), .000001));
    }
  });

  testWidgets(
    'predictive cancellation moves only reading, not chrome or action',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      AppRouter.router.push('/post/10');
      await pumpFrames(tester);
      final reading = find.descendant(
        of: thread(10),
        matching: find.byKey(const Key('forum-scroll')),
      );
      final bar = find.descendant(
        of: thread(10),
        matching: find.byType(AppBar),
      );
      final shore = find.descendant(
        of: thread(10),
        matching: find.byType(ForumCurrentShore),
      );
      final before = tester.getRect(reading);
      final top = tester.getRect(bar);
      final bottom = tester.getRect(shore);
      final button = tester.getRect(fab('回复'));
      for (final edge in [0, 1]) {
        await backEvent(tester, 'startBackGesture', edge: edge);
        await backEvent(
          tester,
          'updateBackGestureProgress',
          edge: edge,
          progress: .6,
        );
        final current = tester.getRect(reading);
        expect(current.width, closeTo(before.width * .952, .1));
        expect(current.height, closeTo(before.height * .952, .1));
        expect(current.center, before.center);
        expect(tester.getRect(bar), top);
        expect(tester.getRect(shore), bottom);
        expect(tester.getRect(fab('回复')), button);
        await backEvent(tester, 'cancelBackGesture');
        await pumpFrames(tester);
        expect(tester.getRect(reading), before);
        expect(tester.getRect(fab('回复')), button);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actions leave downward and enter from the right on push and pop',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      final home = tester.getRect(fab('发新串'));
      AppRouter.router.push('/post/10');
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getRect(fab('发新串')).top, greaterThan(home.top));
      expect(tester.getRect(fab('回复')).left, greaterThan(390));
      await pumpFrames(tester);
      expect(fab('发新串'), findsNothing);
      final reply = tester.getRect(fab('回复'));
      expect(reply.right, closeTo(374, .1));
      await backEvent(tester, 'startBackGesture');
      await backEvent(tester, 'updateBackGestureProgress', progress: .6);
      await backEvent(tester, 'commitBackGesture');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getRect(fab('回复')).top, greaterThan(reply.top));
      expect(tester.getRect(fab('发新串')).left, greaterThan(390));
      await pumpFrames(tester);
      expect(fab('回复'), findsNothing);
      expect(tester.getRect(fab('发新串')), home);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dialogs and drawer hide overlay actions without changing their resting position',
    (tester) async {
      await pumpForum(
        tester,
        ForumFixture(),
        authenticated: true,
        size: const Size(390, 844),
      );
      final original = tester.getRect(fab('发新串'));
      await tester.tap(find.byTooltip('打开导航'));
      await pumpFrames(tester);
      expect(fab('发新串'), findsNothing);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(tester.getRect(fab('发新串')), original);
      await tester.tap(fab('发新串'));
      await pumpFrames(tester);
      expect(fab('发新串'), findsNothing);
      expect(find.byTooltip('关闭编辑'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭编辑'));
      await pumpFrames(tester);
      expect(tester.getRect(fab('发新串')), original);
    },
  );

  testWidgets(
    'quick repeated navigation settles to exactly one current action',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      AppRouter.router.push('/post/10');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      AppRouter.router.push('/post/20');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      AppRouter.router.pop();
      await pumpFrames(tester);
      expect(find.byKey(const Key('fab-compose')), findsOneWidget);
      expect(fab('回复'), findsOneWidget);
      expect(tester.widget<ForumScreen>(find.byType(ForumScreen)).postId, 10);
      expect(tester.takeException(), isNull);
    },
  );
}
