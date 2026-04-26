import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:islander_flutter/app.dart';
import 'package:islander_flutter/main.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';

void main() {
  testWidgets('App launches and shows home page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
        child: const IslanderApp(),
      ),
    );
    await tester.pumpAndSettle();
    // GoRouter redirects / to /plate/0, PlateScreen shows "时间线"
    expect(find.text('时间线'), findsOneWidget);
  });
}
