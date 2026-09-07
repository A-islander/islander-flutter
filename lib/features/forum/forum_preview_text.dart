final _previewLineBreaks = RegExp(r'[\r\n\u0085\u2028\u2029]+');

/// Flatten explicit line breaks only for previews. Keep the source, spacing in
/// kaomoji, and full thread text intact; Text handles ellipsis at its line limit.
String forumPreviewText(String text) =>
    text.replaceAll(_previewLineBreaks, ' ');
