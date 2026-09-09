import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/forum/forum_screen.dart';
import '../../features/forum/application/site_scope.dart';
import '../../features/forum/forum_motion.dart';
import '../../features/local_cache/local_search_screen.dart';
import '../../features/local_cache/cache_settings_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static String initialLocation = '/plate/0';
  static const freshTimeline = {'freshTimeline': true};
  static bool _restorePosition(GoRouterState state) =>
      state.extra is! Map || (state.extra as Map)['freshTimeline'] != true;
  static final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [forumMotionObserver],
    initialLocation: initialLocation,
    initialExtra: freshTimeline,
    routes: [
      GoRoute(
        path: '/local-search',
        builder: (_, state) => ForumAuxiliaryTransition(
          child: LocalSearchScreen(
            pinnedOnly: state.uri.queryParameters['pinned'] == '1',
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) =>
            const ForumAuxiliaryTransition(child: LocalSettingsScreen()),
      ),
      GoRoute(
        path: '/settings/cache',
        builder: (_, _) =>
            const ForumAuxiliaryTransition(child: CacheSettingsScreen()),
      ),
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
                restorePosition: key != '0' || _restorePosition(state),
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
              key: ValueKey('$site-post-${state.uri}'),
              kind: 'thread',
              postId: int.tryParse(state.pathParameters['postId']!) ?? 0,
              focusId: int.tryParse(state.uri.queryParameters['focus'] ?? ''),
              initialPage: int.tryParse(
                state.uri.queryParameters['page'] ?? '',
              )?.clamp(0, 1000000),
              localOnly: state.uri.queryParameters['localOnly'] == '1',
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
            restorePosition: plateId != 0 || _restorePosition(state),
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
            key: ValueKey('post-${state.uri}'),
            kind: 'thread',
            postId: postId,
            focusId: int.tryParse(state.uri.queryParameters['focus'] ?? ''),
            initialPage: int.tryParse(
              state.uri.queryParameters['page'] ?? '',
            )?.clamp(0, 1000000),
            localOnly: state.uri.queryParameters['localOnly'] == '1',
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
