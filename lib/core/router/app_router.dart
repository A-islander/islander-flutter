import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/plate/screens/plate_screen.dart';
import '../../features/post/screens/post_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/sage/screens/sage_list_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/plate/0',
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/plate/0',
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/plate/:plateId',
        builder: (context, state) {
          final plateId = int.tryParse(state.pathParameters['plateId'] ?? '0') ?? 0;
          return PlateScreen(plateId: plateId);
        },
      ),
      GoRoute(
        path: '/post/:postId',
        builder: (context, state) {
          final postId = int.tryParse(state.pathParameters['postId'] ?? '0') ?? 0;
          return PostScreen(postId: postId);
        },
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/sage',
        builder: (context, state) => const SageListScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('404')),
      body: const Center(child: Text('你想看什么辣！', style: TextStyle(fontSize: 18))),
    ),
  );
}
