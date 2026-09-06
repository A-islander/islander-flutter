import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/shared/widgets/rich_post_text.dart';
import 'support/forum_fixture.dart';

class ActionsFixture extends ForumFixture {
  int ownerId = 7;

  @override
  Map<String, dynamic> post(int id, {int follow = 0, int status = 0}) => {
    ...super.post(id, follow: follow, status: status),
    'userId': ownerId,
    'replyArr': follow == 0 ? [] : [10],
    'sageAddCount': 3,
    'sageSubCount': 1,
    'sageAddId': [7],
  };
}

Future<void> openActions(WidgetTester tester, int id) async {
  final trigger = find.byKey(ValueKey('post-actions-$id'));
  await tester.ensureVisible(trigger);
  await pumpFrames(tester);
  await tester.tap(trigger);
  await pumpFrames(tester);
}

void main() {
  testWidgets('phone hides actions in a bottom-right menu and quotes a reply', (
    tester,
  ) async {
    final fixture = ActionsFixture();
    await pumpForum(
      tester,
      fixture,
      authenticated: true,
      size: const Size(320, 844),
    );
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    expect(find.text('引用回复'), findsNothing);
    expect(find.text('SAGE 3'), findsNothing);
    expect(find.text('反对 SAGE 1'), findsNothing);
    expect(find.text('删除内容'), findsNothing);
    await openActions(tester, 11);
    expect(find.text('引用回复'), findsOneWidget);
    expect(find.text('SAGE 3'), findsOneWidget);
    expect(find.text('反对 SAGE 1'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('删除内容'), findsOneWidget);
    await tester.tap(find.text('引用回复'));
    await pumpFrames(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-body')))
          .controller!
          .text,
      'No.11 ',
    );
    expect(find.byKey(const Key('composer-title')), findsNothing);
    final sheet = tester.getRect(find.byKey(const Key('forum-sheet-surface')));
    expect(sheet.left, 0);
    expect(sheet.right, 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SAGE and opposing SAGE use the selected post ID', (
    tester,
  ) async {
    final fixture = ActionsFixture();
    await pumpForum(tester, fixture, authenticated: true);
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    for (final entry in {'SAGE 3': 'add', '反对 SAGE 1': 'sub'}.entries) {
      await openActions(tester, 11);
      await tester.tap(find.text(entry.key));
      await pumpFrames(tester);
      final sent = fixture.requests.where(
        (r) => r.uri.path == '/forum/sage/${entry.value}',
      );
      expect(sent.length, 1);
      expect(sent.single.uri.queryParameters['postId'], '11');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('anonymous menu gates voting and excludes owner actions', (
    tester,
  ) async {
    final fixture = ActionsFixture();
    await pumpForum(tester, fixture);
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    await openActions(tester, 10);
    expect(find.text('删除内容'), findsNothing);
    expect(find.text('恢复内容'), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(find.text('SAGE 3'));
    await pumpFrames(tester);
    expect(find.byKey(const Key('cookie-token')), findsOneWidget);
    expect(
      fixture.requests.where((r) => r.uri.path == '/forum/sage/add'),
      isEmpty,
    );
  });

  testWidgets('signed-in readers cannot manage someone else’s posts', (
    tester,
  ) async {
    await pumpForum(tester, ActionsFixture()..ownerId = 8, authenticated: true);
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    await openActions(tester, 10);
    expect(find.text('引用回复'), findsOneWidget);
    expect(find.text('删除内容'), findsNothing);
    expect(find.text('恢复内容'), findsNothing);
  });

  testWidgets(
    'reply deletion still requires confirmation and supports cancel',
    (tester) async {
      final fixture = ActionsFixture();
      await pumpForum(tester, fixture, authenticated: true);
      AppRouter.router.push('/post/10');
      await pumpFrames(tester);
      await openActions(tester, 11);
      await tester.tap(find.text('删除内容'));
      await pumpFrames(tester);
      expect(find.text('删除 No.11？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await pumpFrames(tester);
      expect(
        fixture.requests.where((r) => r.uri.path == '/forum/delete/ownPost'),
        isEmpty,
      );
      await openActions(tester, 11);
      await tester.tap(find.text('删除内容'));
      await pumpFrames(tester);
      await tester.tap(find.text('删除'));
      await pumpFrames(tester);
      final sent = fixture.requests.where(
        (r) => r.uri.path == '/forum/delete/ownPost',
      );
      expect(sent.length, 1);
      expect(sent.single.uri.queryParameters['postId'], '11');
    },
  );

  testWidgets('deleted own replies and list previews expose recovery in menu', (
    tester,
  ) async {
    final fixture = ActionsFixture()..deleted = true;
    await pumpForum(tester, fixture, authenticated: true);
    expect(find.text('恢复内容'), findsNothing);
    await openActions(tester, 10);
    expect(find.text('恢复内容'), findsOneWidget);
    expect(find.text('引用回复'), findsNothing);
    await tester.tap(find.text('恢复内容'));
    await pumpFrames(tester);
    expect(find.text('恢复 No.10？'), findsOneWidget);
    expect(
      fixture.requests.where((r) => r.uri.path == '/forum/recover/ownPost'),
      isEmpty,
    );
    await tester.tap(find.text('恢复'));
    await pumpFrames(tester);
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    await openActions(tester, 11);
    expect(find.text('删除内容'), findsNothing);
    await tester.tap(find.text('恢复内容'));
    await pumpFrames(tester);
    expect(find.text('恢复 No.11？'), findsOneWidget);
    expect(find.textContaining('这条回复将重新对其他岛民可见'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await pumpFrames(tester);
    expect(
      fixture.requests
          .where((r) => r.uri.path == '/forum/recover/ownPost')
          .map((r) => r.uri.queryParameters['postId']),
      ['10', '11'],
    );
  });

  testWidgets('recovery cancellation and system back never send a request', (
    tester,
  ) async {
    final fixture = ActionsFixture()..deleted = true;
    await pumpForum(
      tester,
      fixture,
      authenticated: true,
      size: const Size(320, 720),
    );
    for (final cancelWithBack in [false, true]) {
      await openActions(tester, 10);
      await tester.tap(find.text('恢复内容'));
      await pumpFrames(tester);
      expect(find.textContaining('这条串将重新对其他岛民可见'), findsOneWidget);
      if (cancelWithBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('取消'));
      }
      await pumpFrames(tester);
      expect(find.text('恢复 No.10？'), findsNothing);
      expect(
        fixture.requests.where((r) => r.uri.path == '/forum/recover/ownPost'),
        isEmpty,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline No link expands and collapses without duplicate buttons',
    (tester) async {
      final fixture = ActionsFixture();
      await pumpForum(tester, fixture);
      AppRouter.router.push('/post/10');
      await pumpFrames(tester);
      expect(find.text('引用 No.10'), findsNothing);
      final body = find.byWidgetPredicate(
        (w) => w is RichPostText && w.text.startsWith('回复正文 11'),
      );
      TapGestureRecognizer quoteLink() {
        final rich = tester.widget<SelectableText>(
          find.descendant(of: body, matching: find.byType(SelectableText)),
        );
        final span = rich.textSpan!.children!.whereType<TextSpan>().singleWhere(
          (span) => span.text!.trim() == 'No.10',
        );
        expect(
          span.style!.color,
          Theme.of(tester.element(body)).colorScheme.secondary,
        );
        return span.recognizer! as TapGestureRecognizer;
      }

      quoteLink().onTap!();
      await pumpFrames(tester);
      expect(find.text('前往 No.10 所在串 →'), findsOneWidget);
      expect(find.text('讨论正文 10'), findsNWidgets(2));
      expect(find.text('引用 No.10'), findsNothing);
      quoteLink().onTap!();
      await pumpFrames(tester);
      expect(find.text('前往 No.10 所在串 →'), findsNothing);
      expect(find.text('讨论正文 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
