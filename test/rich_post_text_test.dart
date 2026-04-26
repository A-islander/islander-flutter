import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:islander_flutter/app.dart';
import 'package:islander_flutter/main.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';
import 'package:islander_flutter/shared/widgets/rich_post_text.dart';
import 'package:islander_flutter/shared/widgets/post_card_header.dart';
import 'package:islander_flutter/shared/widgets/media_item.dart';
import 'package:islander_flutter/features/plate/models/post_model.dart';
import 'package:islander_flutter/core/constants/emoji_constants.dart';

void main() {
  // --- App launch test ---
  testWidgets('App launches and shows home page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storageService)],
        child: const IslanderApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('时间线'), findsOneWidget);
  });

  // --- RichPostText tests ---
  testWidgets('RichPostText renders plain text', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RichPostText(text: 'Hello World'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hello World'), findsOneWidget);
  });

  testWidgets('RichPostText renders empty text as nothing', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RichPostText(text: ''))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('RichPostText detects URL and replaces with link text', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RichPostText(text: 'Visit https://example.com now'))),
    );
    await tester.pumpAndSettle();
    // URL should be replaced, so raw URL text should not appear
    expect(find.textContaining('https://example.com'), findsNothing);
    // Surrounding text should exist
    expect(find.textContaining('Visit'), findsWidgets);
  });

  testWidgets('RichPostText detects No.XXX and renders it', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RichPostText(text: 'See No.123 for details'))),
    );
    await tester.pumpAndSettle();
    // No.123 should be rendered (as a tappable span)
    expect(find.textContaining('No.123'), findsWidgets);
    expect(find.textContaining('See'), findsWidgets);
  });

  testWidgets('RichPostText handles multiple URLs and refs', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RichPostText(text: 'Check https://a.com and No.456 ok http://b.com')),
      ),
    );
    await tester.pumpAndSettle();
    // Raw URLs should be replaced
    expect(find.textContaining('https://a.com'), findsNothing);
    expect(find.textContaining('http://b.com'), findsNothing);
    // No.456 should be rendered
    expect(find.textContaining('No.456'), findsWidgets);
  });

  testWidgets('RichPostText preserves newlines', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RichPostText(text: 'Line1\nLine2\nLine3'))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Line1'), findsOneWidget);
    expect(find.textContaining('Line3'), findsOneWidget);
  });

  // --- PostCardHeader tests ---
  testWidgets('PostCardHeader shows post info', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCardHeaderSample(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TestUser'), findsOneWidget);
    expect(find.text('No.42'), findsOneWidget);
  });

  // --- EmojiPicker data test ---
  test('Emoji list has 99 entries (matching web source)', () {
    expect(emojiList.length, 99);
  });

  // --- MediaItem parsing test ---
  test('MediaItem.parseMediaUrl handles empty string', () {
    expect(MediaItem.parseMediaUrl(''), isEmpty);
  });

  test('MediaItem.parseMediaUrl handles plain URL', () {
    final items = MediaItem.parseMediaUrl('https://example.com/img.png');
    expect(items.length, 1);
    expect(items.first.url, 'https://example.com/img.png');
    expect(items.first.type, 'image');
  });

  test('MediaItem.parseMediaUrl handles JSON array', () {
    const json = '[{"id":"1","url":"https://a.com/img.png","thumbnailUrl":"https://a.com/thumb.png","type":"image"}]';
    final items = MediaItem.parseMediaUrl(json);
    expect(items.length, 1);
    expect(items.first.id, '1');
    expect(items.first.type, 'image');
  });
}

class PostCardHeaderSample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PostCardHeader(
      post: Post(
        id: 42,
        name: 'TestUser',
        time: DateTime(2024, 6, 15, 14, 30).millisecondsSinceEpoch ~/ 1000,
        value: 'Test content',
      ),
    );
  }
}
