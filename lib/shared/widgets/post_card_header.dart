import 'package:flutter/material.dart';
import '../../core/utils/date_format.dart' as date_utils;
import '../../features/plate/models/post_model.dart';

class PostCardHeader extends StatelessWidget {
  final Post post;
  final VoidCallback? onTapPostNumber;

  const PostCardHeader({super.key, required this.post, this.onTapPostNumber});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date_utils.DateUtils.formatTimestamp(post.time),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  post.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: onTapPostNumber,
                child: Text(
                  'No.${post.id}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              if (post.status == 1)
                Text(
                  '已被sage',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.orangeAccent,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on BuildContext {
  ThemeData get theme => Theme.of(this);
}
