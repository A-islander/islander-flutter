import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/forum/forum_screen.dart';
import '../../features/forum/application/site_scope.dart';
import '../../features/forum/forum_motion.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static String initialLocation = '/plate/0';
  static final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [forumMotionObserver],
    initialLocation: initialLocation,
    routes: [
      for (final site in ['x', 'bog']) ...[
        GoRoute(
          path: '/s/$site/plate/:boardKey',
          builder: (context, state) {
            final key = state.pathParameters['boardKey']!;
            return ExternalForumScope(
              siteId: site,
              child: ForumScreen(
                key: ValueKey('$site-board-$key'),
                kind: key == '0' ? 'timeline' : 'board',
                boardId: int.tryParse(key) ?? 0,
                boardKey: key,
              ),
            );
          },
        ),
        GoRoute(
          path: '/s/$site/post/:postId',
          builder: (context, state) => ExternalForumScope(
            siteId: site,
            child: ForumScreen(
              key: ValueKey('$site-post-${state.pathParameters['postId']}'),
              kind: 'thread',
              postId: int.tryParse(state.pathParameters['postId']!) ?? 0,
            ),
          ),
        ),
      ],
      GoRoute(path: '/', redirect: (_, state) => '/plate/0'),
      GoRoute(path: '/home', redirect: (context, state) => '/plate/0'),
      GoRoute(
        path: '/plate/:plateId',
        builder: (context, state) {
          final plateId =
              int.tryParse(state.pathParameters['plateId'] ?? '0') ?? 0;
          return ForumScreen(
            key: ValueKey('board-$plateId'),
            kind: plateId == 0 ? 'timeline' : 'board',
            boardId: plateId,
          );
        },
      ),
      GoRoute(
        path: '/post/:postId',
        builder: (context, state) {
          final postId =
              int.tryParse(state.pathParameters['postId'] ?? '0') ?? 0;
          return ForumScreen(
            key: ValueKey('post-$postId'),
            kind: 'thread',
            postId: postId,
          );
        },
      ),
      GoRoute(path: '/login', redirect: (context, state) => '/mine'),
      GoRoute(
        path: '/sage',
        builder: (context, state) => const ForumScreen(kind: 'sage'),
      ),
      GoRoute(
        path: '/mine',
        builder: (context, state) => const ForumScreen(kind: 'mine'),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('404')),
      body: const Center(
        child: Text('你想看什么辣！', style: TextStyle(fontSize: 18)),
      ),
    ),
  );
}
