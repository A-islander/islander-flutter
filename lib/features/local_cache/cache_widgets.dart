import 'package:flutter/material.dart';
import '../forum/forum_theme.dart';

String cacheSize(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

Future<bool> confirmCacheAction(
  BuildContext context,
  String title,
  String detail,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ==
    true;

class CacheSection extends StatelessWidget {
  const CacheSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: ForumPalette.of(context).accent,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ),
        ...children,
      ],
    ),
  );
}
