import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class RichPostText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;

  const RichPostText({super.key, required this.text, this.style, this.maxLines});

  static final _urlOrNoRegex = RegExp(
    r'(http|ftp|https)://[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&:/~\+#]*[\w\-\@?^=%&/~\+#])?|No\.[0-9]+',
  );

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final defaultStyle = style ?? DefaultTextStyle.of(context).style;
    final matches = _urlOrNoRegex.allMatches(text);
    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final match in matches) {
      // plain text before this match
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }

      final matched = match.group(0)!;

      if (matched.startsWith('http')) {
        spans.add(TextSpan(
          text: '链接',
          style: defaultStyle.copyWith(
            color: Theme.of(context).colorScheme.secondary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => launchUrl(Uri.parse(matched), mode: LaunchMode.externalApplication),
        ));
      } else if (matched.startsWith('No.')) {
        final postId = matched.replaceFirst('No.', '');
        spans.add(TextSpan(
          text: '$matched ',
          style: defaultStyle.copyWith(
            color: Theme.of(context).colorScheme.secondary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => context.go('/post/$postId'),
        ));
      }

      cursor = match.end;
    }

    // remaining plain text
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return SelectableText.rich(
      TextSpan(style: defaultStyle, children: spans),
      maxLines: maxLines,
    );
  }
}
