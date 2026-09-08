import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/features/forum/domain/forum_site.dart';
import 'package:islander_flutter/features/plate/models/post_model.dart';
import 'package:islander_flutter/shared/widgets/rich_post_text.dart';
import 'support/forum_fixture.dart';

class CrossQuoteFixture extends ForumFixture {
  @override
  Map<String, dynamic> post(int id, {int follow = 0, int status = 0}) => {
    ...super.post(id, follow: follow, status: status),
    'userId': id >= 20 ? 8 : 7,
    if (id == 21) 'followId': 20,
    if (id == 11) 'value': 'No.21',
  };
}

void main() {
  testWidgets('a cross-thread quote uses its own root for PO', (tester) async {
    final fixture = CrossQuoteFixture();
    await pumpForum(tester, fixture);
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    final body = tester.widget<RichPostText>(
      find.byWidgetPredicate((w) => w is RichPostText && w.text == 'No.21'),
    );
    body.onQuote!(21);
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('post-po-21')), findsOneWidget);
    expect(
      fixture.requests.where(
        (r) => r.uri.path == '/forum/get' && r.queryParameters['postId'] == 20,
      ),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });
  test('PO requires the matching root, site and a usable author identity', () {
    const root = Post(id: 10, userId: 7, name: '同名');
    expect(root.isOriginalPosterOf(root), isTrue);
    expect(
      const Post(id: 11, followId: 10, userId: 7).isOriginalPosterOf(root),
      isTrue,
    );
    expect(
      const Post(
        id: 11,
        followId: 10,
        userId: 8,
        name: '同名',
      ).isOriginalPosterOf(root),
      isFalse,
    );
    expect(
      const Post(id: 11, followId: 20, userId: 7).isOriginalPosterOf(root),
      isFalse,
    );
    expect(
      const Post(
        id: 11,
        followId: 10,
        userId: 7,
        parentUnknown: true,
      ).isOriginalPosterOf(root),
      isFalse,
    );
    expect(
      const Post(id: 11, followId: 10).isOriginalPosterOf(const Post(id: 10)),
      isFalse,
    );
    expect(root.isOriginalPosterOf(null), isFalse);
    for (final site in [ForumSite.byId('x'), ForumSite.byId('bog')]) {
      final externalRoot = Post(id: 10, source: site, authorId: 'HASH1234');
      expect(
        Post(
          id: 11,
          source: site,
          followId: 10,
          authorId: 'HASH1234',
        ).isOriginalPosterOf(externalRoot),
        isTrue,
      );
      expect(
        Post(
          id: 11,
          source: site,
          followId: 10,
          name: 'HASH1234',
        ).isOriginalPosterOf(externalRoot),
        isFalse,
      );
      expect(
        Post(
          id: 11,
          source: site,
          followId: 10,
          userId: 7,
        ).isOriginalPosterOf(root),
        isFalse,
      );
      expect(
        Post(
          id: 11,
          source: site,
          followId: 10,
          authorId: '管理员',
        ).isOriginalPosterOf(Post(id: 10, source: site, authorId: '管理员')),
        isFalse,
      );
    }
  });

  testWidgets('root, OP replies and preview replies show PO', (tester) async {
    final fixture = ForumFixture();
    fixture.lastReplies = [fixture.post(11, follow: 10)];
    await pumpForum(tester, fixture, size: const Size(390, 844));
    expect(find.byKey(const ValueKey('post-po-10')), findsOneWidget);
    expect(find.text('PO 测试岛民: 回复正文 11 No.10'), findsOneWidget);
    AppRouter.router.push('/post/10');
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('post-po-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-po-11')), findsOneWidget);
  });
}
