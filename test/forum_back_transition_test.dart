import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/features/forum/forum_theme.dart';
import 'package:islander_flutter/features/forum/forum_motion.dart';

Future<void> backEvent(
  WidgetTester tester,
  String method, {
  int edge = 0,
  double progress = 0,
  double y = 300,
}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, {
        'touchOffset': [edge == 0 ? 5.0 : 795.0, y],
        'progress': progress,
        'swipeEdge': edge,
      }),
    ),
    (_) {},
  );
  await tester.pump();
}

Future<GlobalKey<NavigatorState>> launch(
  WidgetTester tester, {
  bool blockPop = false,
  bool reduceMotion = false,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: forumTheme().copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: const Scaffold(body: Text('list-page')),
    ),
  );
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => PopScope(
        canPop: !blockPop,
        child: Scaffold(
          key: const Key('detail-shell'),
          appBar: AppBar(title: const Text('detail-title')),
          body: ForumReadingTransition(
            child: SizedBox.expand(
              key: const Key('detail-page'),
              child: ListView.builder(
                itemCount: 50,
                itemBuilder: (_, index) =>
                    SizedBox(height: 80, child: Text('row $index')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

void main() {
  testWidgets('an open dialog does not drag or pop the page behind it', (
    tester,
  ) async {
    final navigator = await launch(tester);
    final page = find.byKey(const Key('detail-page'));
    final original = tester.getRect(page);
    showDialog<void>(
      context: navigator.currentState!.context,
      builder: (_) => const AlertDialog(title: Text('confirmation')),
    );
    await tester.pumpAndSettle();
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: .6, y: 500);
    expect(tester.getRect(page), original);
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('forum-reading-scale')))
          .transform
          .getMaxScaleOnAxis(),
      1,
    );
    await backEvent(tester, 'cancelBackGesture');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(page, findsOneWidget);
    expect(find.text('confirmation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both edges shrink toward the same fixed center', (tester) async {
    await launch(tester);
    final page = find.byKey(const Key('detail-page'));
    final original = tester.getRect(page);
    final shrunkRects = <Rect>[];
    for (final edge in [0, 1]) {
      await backEvent(tester, 'startBackGesture', edge: edge);
      await backEvent(
        tester,
        'updateBackGestureProgress',
        edge: edge,
        progress: .55,
        y: 150,
      );
      final first = tester.getRect(page);
      expect(first.width, lessThan(original.width));
      expect(first.height, lessThan(original.height));
      expect(first.center.dx, closeTo(original.center.dx, .01));
      expect(first.center.dy, closeTo(original.center.dy, .01));
      shrunkRects.add(first);
      await backEvent(
        tester,
        'updateBackGestureProgress',
        edge: edge,
        progress: .55,
        y: 550,
      );
      expect(tester.getRect(page), first);
      await backEvent(tester, 'cancelBackGesture');
      await tester.pump(const Duration(milliseconds: 50));
      final returning = tester.getRect(page);
      expect(returning.center.dx, closeTo(original.center.dx, .01));
      expect(returning.center.dy, closeTo(original.center.dy, .01));
      await tester.pumpAndSettle();
      expect(tester.getRect(page), original);
    }
    expect(shrunkRects.last, shrunkRects.first);
    expect(tester.takeException(), isNull);
  });

  for (final edge in [0, 1]) {
    testWidgets(
      'edge $edge scales only reading down to 92% with a fixed topbar',
      (tester) async {
        await launch(tester);
        final page = find.byKey(const Key('detail-page'));
        final title = find.text('detail-title');
        final original = tester.getRect(page);
        final originalTitle = tester.getRect(title);
        await backEvent(tester, 'startBackGesture', edge: edge);
        for (final progress in [0.0, .25, .6, 1.0]) {
          await backEvent(
            tester,
            'updateBackGestureProgress',
            edge: edge,
            progress: progress,
          );
          final current = tester.getRect(page);
          final scale = 1 - .08 * progress;
          expect(current.width, closeTo(original.width * scale, .01));
          expect(current.height, closeTo(original.height * scale, .01));
          expect(current.center.dx, closeTo(original.center.dx, .01));
          expect(current.center.dy, closeTo(original.center.dy, .01));
          final currentTitle = tester.getRect(title);
          expect(currentTitle, originalTitle);
        }
        await backEvent(tester, 'cancelBackGesture');
        await tester.pump(const Duration(milliseconds: 156));
        await tester.pump();
        expect(tester.getRect(page), original);
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('forum-reading-scale')),
              )
              .transform
              .getMaxScaleOnAxis(),
          1,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final releaseProgress in [.6, 1.0]) {
      testWidgets(
        'edge $edge at $releaseProgress shrinks into the center on commit',
        (tester) async {
          await launch(tester);
          final page = find.byKey(const Key('detail-page'));
          final original = tester.getRect(page);
          await backEvent(tester, 'startBackGesture', edge: edge);
          await backEvent(
            tester,
            'updateBackGestureProgress',
            edge: edge,
            progress: releaseProgress,
          );
          final width = tester.getRect(page).width;
          await backEvent(tester, 'commitBackGesture');
          expect(tester.getRect(page).width, closeTo(width, .01));
          await tester.pump(const Duration(milliseconds: 50));
          final leaving = tester.getRect(page);
          expect(leaving.center.dx, closeTo(original.center.dx, .01));
          expect(leaving.center.dy, closeTo(original.center.dy, .01));
          expect(leaving.width, lessThan(width * .6));
          await tester.pump(const Duration(milliseconds: 100));
          final nearlyGone = tester.getRect(page);
          expect(nearlyGone.width, lessThan(original.width * .1));
          expect(nearlyGone.height, lessThan(original.height * .1));
          expect(nearlyGone.center.dx, closeTo(original.center.dx, .01));
          expect(nearlyGone.center.dy, closeTo(original.center.dy, .01));
          await tester.pump(const Duration(milliseconds: 60));
          expect(page, findsNothing);
          expect(find.text('list-page'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('normal vertical scrolling never starts a return transition', (
    tester,
  ) async {
    await launch(tester);
    final original = tester.getRect(find.byKey(const Key('detail-page')));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('detail-page'))), original);
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('forum-reading-scale')))
          .transform
          .getMaxScaleOnAxis(),
      1,
    );
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('PopScope prevents the custom predictive gesture', (
    tester,
  ) async {
    await launch(tester, blockPop: true);
    final page = find.byKey(const Key('detail-page'));
    final original = tester.getRect(page);
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: .8);
    expect(tester.getRect(page), original);
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('forum-reading-scale')))
          .transform
          .getMaxScaleOnAxis(),
      1,
    );
    await backEvent(tester, 'cancelBackGesture');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips transforms but still returns', (
    tester,
  ) async {
    await launch(tester, reduceMotion: true);
    final page = find.byKey(const Key('detail-page'));
    final original = tester.getRect(page);
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: .8);
    expect(tester.getRect(page), original);
    await backEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(find.text('list-page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
