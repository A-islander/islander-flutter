import 'package:flutter/material.dart';

abstract final class ForumColors {
  static const accent = Color(0xFF007A73);
  static const soft = Color(0xFFE1F2F0);
  static const canvas = Color(0xFFF2F3F1);
  static const ink = Color(0xFF171918);
  static const muted = Color(0xFF626765);
  static const line = Color(0xFFDFE2DF);
}

ThemeData forumTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: ForumColors.canvas,
  colorScheme: const ColorScheme.light(
    primary: ForumColors.accent,
    secondary: ForumColors.accent,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: ForumColors.ink,
    outline: ForumColors.line,
  ),
  fontFamilyFallback: const [
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'PingFang SC',
  ],
  dividerTheme: const DividerThemeData(
    color: ForumColors.line,
    thickness: 1,
    space: 1,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: ForumColors.accent,
    foregroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
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
      side: const BorderSide(color: ForumColors.line),
    ),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: EdgeInsets.all(12),
    border: OutlineInputBorder(borderRadius: BorderRadius.zero),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: ForumColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: ForumColors.accent, width: 2),
    ),
  ),
  snackBarTheme: const SnackBarThemeData(backgroundColor: ForumColors.ink),
);

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
      color: Colors.white,
      child: Container(
        key: const Key('forum-sheet-surface'),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ForumColors.accent, width: 2)),
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
