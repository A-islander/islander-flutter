import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../plate/providers/plate_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plateState = ref.watch(plateProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('岛民岛'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome section
          Center(
            child: Column(
              children: [
                Icon(Icons.forum, size: 80, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('欢迎来到岛民岛',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('一个匿名论坛', style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Plate list
          Text('板块列表', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (plateState.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (plateState.plates.isEmpty)
            const Center(child: Text('暂无板块'))
          else
            ...plateState.plates.map((plate) => Card(
                  child: ListTile(
                    title: Text(plate.name),
                    subtitle: Text('ID: ${plate.id}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/plate/${plate.id}'),
                  ),
                )),

          // Timeline entry
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.timeline, color: theme.colorScheme.primary),
              title: const Text('时间线'),
              subtitle: const Text('查看最新帖子'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/plate/0'),
            ),
          ),
        ],
      ),
    );
  }
}
