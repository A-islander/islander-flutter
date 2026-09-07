import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class RichPostText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final ValueChanged<int>? onQuote;

  const RichPostText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.onQuote,
  });

  @override
  State<RichPostText> createState() => _RichPostTextState();
}

class _RichPostTextState extends State<RichPostText> {
  final _recognizers = <TapGestureRecognizer>[];
  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  static final _urlOrNoRegex = RegExp(
    r'https?://[^\s<>]+|(?:>>)?(?:No\.|Po\.)[0-9]+|>>[0-9]+',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final text = widget.text;
    final style = widget.style;
    final maxLines = widget.maxLines;
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
        spans.add(
          TextSpan(
            text: '链接',
            style: defaultStyle.copyWith(
              color: Theme.of(context).colorScheme.secondary,
              decoration: TextDecoration.underline,
            ),
            recognizer: _tap(
              () => launchUrl(
                Uri.parse(matched),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        );
      } else {
        final postId = RegExp(r'\d+$').firstMatch(matched)![0]!;
        spans.add(
          TextSpan(
            text: '$matched ',
            style: defaultStyle.copyWith(
              color: Theme.of(context).colorScheme.secondary,
              decoration: TextDecoration.underline,
            ),
            recognizer: _tap(() {
              if (widget.onQuote != null) {
                widget.onQuote!(int.parse(postId));
              } else {
                context.push('/post/$postId');
              }
            }),
          ),
        );
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
