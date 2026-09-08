import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'features/forum/forum_theme.dart';
import 'features/forum/forum_motion.dart';

class IslanderApp extends ConsumerWidget {
  const IslanderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '岛民岛',
      debugShowCheckedModeBanner: false,
      theme: forumTheme(),
      darkTheme: forumTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      themeAnimationDuration: Duration.zero,
      routerConfig: AppRouter.router,
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: ForumMotionHost(child: child!),
      ),
    );
  }
}
