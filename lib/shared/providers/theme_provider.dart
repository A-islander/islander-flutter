import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/storage_service.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final StorageService _storage;

  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    final theme = _storage.getTheme();
    if (theme == 'light') {
      state = ThemeMode.light;
    } else if (theme == 'dark') {
      state = ThemeMode.dark;
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    switch (mode) {
      case ThemeMode.light:
        _storage.setTheme('light');
        break;
      case ThemeMode.dark:
        _storage.setTheme('dark');
        break;
      case ThemeMode.system:
        _storage.setTheme('system');
        break;
    }
  }

  void toggle() {
    if (state == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }
}
