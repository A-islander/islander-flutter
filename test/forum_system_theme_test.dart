import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/features/forum/forum_post_view.dart';
import 'package:islander_flutter/features/forum/forum_theme.dart';
import 'support/forum_fixture.dart';

void main() {
  testWidgets('forum and open sheet follow live system brightness changes', (
    tester,
  ) async {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    final post = find.byType(ForumPostView).first;
    expect(
      ForumPalette.of(tester.element(post)).surface,
      ForumPalette.light.surface,
    );
    await tester.tap(find.byKey(const Key('page-jump-trigger')));
    await pumpFrames(tester);
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    await pumpFrames(tester);
    expect(Theme.of(tester.element(post)).brightness, Brightness.dark);
    final sheet = find.byType(SheetSurface);
    final material = find
        .descendant(of: sheet, matching: find.byType(Material))
        .first;
    expect(tester.widget<Material>(material).color, ForumPalette.dark.surface);
    expect(ForumPalette.of(tester.element(post)).ink, ForumPalette.dark.ink);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    await pumpFrames(tester);
    expect(tester.widget<Material>(material).color, ForumPalette.light.surface);
    expect(Theme.of(tester.element(post)).brightness, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cold launch in system dark mode uses dark surfaces and readable text',
    (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      await pumpForum(tester, ForumFixture(), size: const Size(390, 844));
      final context = tester.element(find.byType(ForumPostView).first);
      final theme = Theme.of(context);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, ForumPalette.dark.canvas);
      expect(
        tester.widget<Text>(find.text('全岛最近有回应的串')).style!.color,
        ForumPalette.dark.muted,
      );
      expect(
        tester.widget<Text>(find.text('LATEST ACTIVITY')).style!.color,
        ForumPalette.dark.accent,
      );
      final contrast =
          (theme.colorScheme.onSurface.computeLuminance() + .05) /
          (theme.colorScheme.surface.computeLuminance() + .05);
      expect(contrast, greaterThan(4.5));
      expect(tester.takeException(), isNull);
    },
  );
}
