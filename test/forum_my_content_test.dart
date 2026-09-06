import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'support/forum_fixture.dart';

class VisibilityFixture extends ForumFixture {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) {
    if (options.uri.path == '/forum/delete/ownPost') deleted = true;
    if (options.uri.path == '/forum/recover/ownPost') deleted = false;
    return super.fetch(options, stream, cancelFuture);
  }
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'my content labels both states in $brightness on narrow phones',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fixture = ForumFixture();
        await pumpForum(
          tester,
          fixture,
          authenticated: true,
          size: const Size(320, 844),
        );
        fixture.overrideResponse = {
          'code': 200,
          'data': {
            'count': 2,
            'list': [fixture.post(10), fixture.post(11, follow: 10, status: 2)],
          },
        };
        AppRouter.router.go('/mine');
        await pumpFrames(tester);
        for (final entry in {10: '未删除', 11: '已删除'}.entries) {
          final tag = find.byKey(ValueKey('post-deletion-status-${entry.key}'));
          await tester.ensureVisible(tag);
          await pumpFrames(tester);
          expect(
            find.descendant(of: tag, matching: find.text(entry.value)),
            findsOneWidget,
          );
        }
        expect(find.text('已删除'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('deletion and recovery update the tag only after confirmation', (
    tester,
  ) async {
    final fixture = VisibilityFixture();
    await pumpForum(tester, fixture, authenticated: true);
    // Normal timelines do not gain a new status tag.
    expect(find.byKey(const ValueKey('post-deletion-status-10')), findsNothing);
    AppRouter.router.go('/mine');
    await pumpFrames(tester);
    expect(find.text('未删除'), findsOneWidget);
    for (final entry in {'删除内容': '删除', '恢复内容': '恢复'}.entries) {
      final trigger = find.byKey(const ValueKey('post-actions-10'));
      await tester.ensureVisible(trigger);
      await tester.tap(trigger);
      await pumpFrames(tester);
      await tester.tap(find.text(entry.key));
      await pumpFrames(tester);
      expect(find.text(entry.value == '删除' ? '未删除' : '已删除'), findsOneWidget);
      await tester.tap(find.text(entry.value));
      await pumpFrames(tester);
      expect(find.text(entry.value == '删除' ? '已删除' : '未删除'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
