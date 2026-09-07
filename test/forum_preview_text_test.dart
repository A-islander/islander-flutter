import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/features/forum/forum_preview_text.dart';
import 'package:islander_flutter/shared/widgets/rich_post_text.dart';

import 'support/forum_fixture.dart';

class PreviewFixture extends ForumFixture {
  PreviewFixture({this.long = false});
  final bool long;
  String get body => long
      ? List.filled(100, '换行后的预览内容').join('\r\n')
      : '第一段\r\n第二段\n\n(  ´▽｀)';

  @override
  Map<String, dynamic> post(int id, {int follow = 0, int status = 0}) => {
    ...super.post(id, follow: follow, status: status),
    'title': follow == 0 ? '标题\n续行' : '',
    'value': body,
    if (follow == 0)
      'lastReplyArr': [
        {...super.post(11, follow: id), 'value': body},
      ],
  };
}

RenderParagraph paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

void main() {
  test(
    'all explicit line endings collapse without changing kaomoji spacing',
    () {
      expect(
        forumPreviewText('甲\r\n乙\r丙\n\n丁\u0085戊\u2028己\u2029庚'),
        '甲 乙 丙 丁 戊 己 庚',
      );
      expect(forumPreviewText('(  ´▽｀)  No.10'), '(  ´▽｀)  No.10');
      expect(forumPreviewText(''), '');
    },
  );

  for (final long in [false, true]) {
    testWidgets(
      'preview only ellipsizes when its line limit is exceeded: $long',
      (tester) async {
        final fixture = PreviewFixture(long: long);
        await pumpForum(tester, fixture, size: const Size(390, 844));
        expect(find.text('标题 续行'), findsOneWidget);
        final body = find.text(forumPreviewText(fixture.body));
        final reply = find.text('测试岛民: ${forumPreviewText(fixture.body)}');
        expect(body, findsOneWidget);
        expect(reply, findsOneWidget);
        expect(tester.widget<Text>(body).maxLines, 3);
        expect(tester.widget<Text>(reply).maxLines, 1);
        expect(tester.widget<Text>(body).overflow, TextOverflow.ellipsis);
        expect(tester.widget<Text>(reply).overflow, TextOverflow.ellipsis);
        expect(paragraph(tester, body).didExceedMaxLines, long);
        expect(paragraph(tester, reply).didExceedMaxLines, long);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('thread detail keeps the original line breaks', (tester) async {
    final fixture = PreviewFixture();
    await pumpForum(tester, fixture, size: const Size(390, 844));
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    expect(find.text('标题\n续行'), findsOneWidget);
    final bodies = tester.widgetList<RichPostText>(find.byType(RichPostText));
    expect(bodies, isNotEmpty);
    expect(bodies.every((body) => body.text == fixture.body), isTrue);
    expect(fixture.body, contains('\r\n'));
  });
}
