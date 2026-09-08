import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'forum_back_transition.dart';

abstract final class ForumColors {
  static const accent = Color(0xFF007A73);
  static const soft = Color(0xFFE1F2F0);
  static const canvas = Color(0xFFF2F3F1);
  static const ink = Color(0xFF171918);
  static const muted = Color(0xFF626765);
  static const line = Color(0xFFDFE2DF);
}

class ForumPalette {
  const ForumPalette({
    required this.accent,
    required this.soft,
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
  });
  final Color accent, soft, canvas, surface, ink, muted, line;
  static const light = ForumPalette(
    accent: ForumColors.accent,
    soft: ForumColors.soft,
    canvas: ForumColors.canvas,
    surface: Colors.white,
    ink: ForumColors.ink,
    muted: ForumColors.muted,
    line: ForumColors.line,
  );
  static const dark = ForumPalette(
    accent: Color(0xFF79D5CB),
    soft: Color(0xFF203C39),
    canvas: Color(0xFF101715),
    surface: Color(0xFF18211F),
    ink: Color(0xFFE4ECE8),
    muted: Color(0xFFA5B6AF),
    line: Color(0xFF35443E),
  );
  static ForumPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData forumTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? ForumPalette.dark : ForumPalette.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.canvas,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const ForumBackTransitionsBuilder(),
      },
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: ForumColors.accent,
      brightness: brightness,
      primary: colors.accent,
      secondary: colors.accent,
      onPrimary: dark ? colors.canvas : Colors.white,
      surface: colors.surface,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      outline: colors.line,
      outlineVariant: colors.line,
    ),
    fontFamilyFallback: const [
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'PingFang SC',
    ],
    dividerTheme: DividerThemeData(color: colors.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF12504B) : ForumColors.accent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: colors.canvas,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: const RoundedRectangleBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: const RoundedRectangleBorder(),
        side: BorderSide(color: colors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.all(12),
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.surface),
    ),
  );
}

Future<T?> forumSheet<T>(
  BuildContext context,
  Widget child, {
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: false,
  isDismissible: dismissible,
  enableDrag: dismissible,
  backgroundColor: Colors.transparent,
  barrierColor: ForumColors.ink.withValues(alpha: .42),
  constraints: BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width),
  builder: (_) => child,
);

class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Material(
      color: ForumPalette.of(context).surface,
      child: Container(
        key: const Key('forum-sheet-surface'),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: ForumPalette.of(context).accent, width: 2),
          ),
        ),
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      MediaQuery.paddingOf(context).top -
                      24)
                  .clamp(0, 720),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
