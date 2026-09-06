import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/network/dio_client.dart';
import 'core/storage/storage_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'shared/providers/theme_provider.dart';

final dioClientProvider = Provider<DioClient>((ref) {
  final client = DioClient();
  ref.onDispose(client.dispose);
  return client;
});

final storageServiceProvider = Provider<StorageService>(
  (ref) => throw UnimplementedError(),
);

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final dio = ref.watch(dioClientProvider);
  final storage = ref.watch(storageServiceProvider);
  return AuthNotifier(storage, dio);
});

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  final storage = ref.watch(storageServiceProvider);
  return ThemeModeNotifier(storage);
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  await storageService.initialize();

  runApp(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storageService)],
      child: const IslanderApp(),
    ),
  );
}
