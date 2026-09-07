import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/features/forum/forum_screen.dart';

import 'forum_scroll_rendering_test.dart' show DenseForumFixture, controller;
import 'support/forum_fixture.dart';

ScaffoldState forumScaffold(WidgetTester tester) => tester.state<ScaffoldState>(
  find
      .ancestor(
        of: find.byKey(const Key('forum-scroll')),
        matching: find.byType(Scaffold),
      )
      .first,
);

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'desktop $kind opens navigation from the right half of the content',
      (tester) async {
        await pumpForum(
          tester,
          DenseForumFixture(),
          size: const Size(600, 844),
        );
        final scaffold = forumScaffold(tester);
        await tester.dragFrom(
          const Offset(410, 400),
          const Offset(-100, 0),
          kind: kind,
        );
        await pumpFrames(tester);
        expect(scaffold.isDrawerOpen, isFalse);
        await tester.dragFrom(
          const Offset(410, 500),
          const Offset(0, -200),
          kind: kind,
        );
        await pumpFrames(tester);
        // Desktop lists scroll with the wheel, not a held mouse button.
        if (kind == PointerDeviceKind.touch) {
          expect(controller(tester).offset, greaterThan(0));
        }
        expect(scaffold.isDrawerOpen, isFalse);
        await tester.dragFrom(
          const Offset(410, 400),
          const Offset(100, 0),
          kind: kind,
        );
        await pumpFrames(tester);
        expect(scaffold.isDrawerOpen, isTrue);
        await tester.tapAt(const Offset(560, 400));
        await pumpFrames(tester);
        expect(scaffold.isDrawerOpen, isFalse);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );
  }

  testWidgets('right drag from the middle opens the drawer interactively', (
    tester,
  ) async {
    await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
    final scaffold = forumScaffold(tester);
    final gesture = await tester.startGesture(const Offset(160, 400));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    final drawer = tester.getRect(find.byType(Drawer));
    expect(drawer.right, greaterThan(0));
    expect(drawer.right, lessThan(304));
    await gesture.moveBy(const Offset(100, 0));
    await gesture.up();
    await pumpFrames(tester);
    expect(scaffold.isDrawerOpen, isTrue);
    expect(tester.getRect(find.byType(Drawer)).left, closeTo(0, 0.1));

    await tester.tapAt(const Offset(360, 400));
    await pumpFrames(tester);
    expect(scaffold.isDrawerOpen, isFalse);
  });

  testWidgets('vertical list scrolling and left drags do not open navigation', (
    tester,
  ) async {
    await pumpForum(tester, DenseForumFixture(), size: const Size(390, 844));
    final scaffold = forumScaffold(tester);
    await tester.dragFrom(const Offset(195, 500), const Offset(0, -240));
    await pumpFrames(tester);
    expect(controller(tester).offset, greaterThan(100));
    expect(scaffold.isDrawerOpen, isFalse);
    await tester.dragFrom(const Offset(280, 400), const Offset(-180, 0));
    await pumpFrames(tester);
    expect(scaffold.isDrawerOpen, isFalse);
  });

  testWidgets(
    'post taps work and back closes navigation without leaving thread',
    (tester) async {
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      await tester.tap(find.text('测试主串 10').first);
      await pumpFrames(tester);
      expect(tester.widget<ForumScreen>(find.byType(ForumScreen)).postId, 10);
      final scaffold = forumScaffold(tester);
      await tester.dragFrom(const Offset(150, 400), const Offset(210, 0));
      await pumpFrames(tester);
      expect(scaffold.isDrawerOpen, isTrue);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(scaffold.isDrawerOpen, isFalse);
      expect(tester.widget<ForumScreen>(find.byType(ForumScreen)).postId, 10);
    },
  );

  testWidgets('a modal does not open the navigation behind it', (tester) async {
    await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
    final scaffold = forumScaffold(tester);
    showModalBottomSheet<void>(
      context: scaffold.context,
      builder: (_) => const SizedBox(height: 500, child: Text('测试抽屉')),
    );
    await pumpFrames(tester);
    await tester.dragFrom(const Offset(150, 500), const Offset(210, 0));
    await pumpFrames(tester);
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.text('测试抽屉'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await pumpFrames(tester);
  });

  testWidgets('wide layouts retain the permanent sidebar', (tester) async {
    await pumpForum(tester, ForumFixture());
    final scaffold = forumScaffold(tester);
    expect(scaffold.widget.drawer, isNull);
    expect(find.byKey(const Key('site-selector')), findsOneWidget);
    await tester.dragFrom(const Offset(600, 400), const Offset(210, 0));
    await pumpFrames(tester);
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.byType(Drawer), findsNothing);
  });
}
