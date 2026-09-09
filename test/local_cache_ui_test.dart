import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:islander_flutter/app.dart';
import 'package:islander_flutter/main.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';
import 'package:islander_flutter/features/local_cache/cache_store.dart';
import 'package:islander_flutter/features/local_cache/cache_providers.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'package:islander_flutter/features/forum/forum_post_view.dart';
import 'package:islander_flutter/features/forum/forum_motion.dart';
import 'package:islander_flutter/features/forum/application/site_scope.dart';
import 'package:islander_flutter/features/plate/models/post_model.dart';
import 'local_cache_test.dart' show CacheRemote;
import 'support/memory_cache_fixture.dart';
import 'support/forum_fixture.dart' show ForumFixture;

// Native SQLite completes on the real event loop, outside the widget fake clock.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 160));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

void main() {
  late CacheStore store;
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    await storage.initialize();
    store = MemoryCacheFixture();
    for (final site in ForumSite.all) {
      await store.capture(
        site,
        'anonymous',
        [
          Post(id: 10, source: site, title: '${site.name} 的海滩', value: '本地主贴'),
          Post(id: 11, source: site, followId: 10, value: '海风回复 😀'),
        ],
        threadId: 10,
        page: 2,
      );
    }
  });
  Future<void> pump(
    WidgetTester tester, {
    String route = '/local-search',
    bool offline = true,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await pumpFrames(tester);
      await tester.runAsync(() => store.flushed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(store.close);
    });
    AppRouter.router.go(route);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          cacheStoreProvider.overrideWith((ref) => store),
          dioClientProvider.overrideWithValue(ForumFixture().client()),
          forumRepositoryProvider.overrideWithValue(
            CacheRemote(ForumSite.islander)..fail = offline,
          ),
          externalRepositoryProvider(
            'x',
          ).overrideWith((ref) => CacheRemote(ForumSite.x)..fail = offline),
          externalRepositoryProvider(
            'bog',
          ).overrideWith((ref) => CacheRemote(ForumSite.bog)..fail = offline),
        ],
        child: const IslanderApp(),
      ),
    );
    await pumpFrames(tester);
  }

  testWidgets(
    'local search finds three islands and Chinese short text without network search',
    (tester) async {
      await pump(tester);
      expect(find.text('浏览搜索'), findsOneWidget);
      expect(find.text('关键字/no号'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('local-search-query')), '海风');
      await pumpFrames(tester);
      for (final site in ForumSite.all) {
        expect(
          find.byKey(ValueKey('cache-result-${site.id}-11')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('cache-result-islander-10')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final site in ForumSite.all) {
    testWidgets(
      '${site.id} local result opens corresponding thread and highlights offline reply',
      (tester) async {
        await pump(tester);
        await tester.enterText(
          find.byKey(const Key('local-search-query')),
          '海风',
        );
        await pumpFrames(tester);
        await tester.tap(find.byKey(ValueKey('cache-result-${site.id}-11')));
        await pumpFrames(tester);
        expect(
          AppRouter
              .router
              .routerDelegate
              .currentConfiguration
              .last
              .matchedLocation,
          site.route('/post/10'),
        );
        final views = tester.widgetList<ForumPostView>(
          find.byType(ForumPostView),
        );
        expect(
          views.any(
            (w) =>
                w.post.id == 11 && w.highlighted && w.post.site.id == site.id,
          ),
          true,
        );
        expect(find.textContaining('本地缓存 · 内容可能不完整'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'unknown parent is a local-only preview, never guesses a thread',
    (tester) async {
      await store.capture(ForumSite.x, 'anonymous', [
        Post(id: 99, source: ForumSite.x, parentUnknown: true, value: '未知所属串'),
      ]);
      await pump(tester);
      await tester.enterText(
        find.byKey(const Key('local-search-query')),
        '未知所属串',
      );
      await pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('cache-result-x-99')));
      await pumpFrames(tester);
      expect(find.textContaining('尚不知道所属串'), findsOneWidget);
      expect(find.text('未知所属串'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'bulk local delete requires confirmation, cancel preserves cache',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('local-search-query')), '海风');
      await pumpFrames(tester);
      await tester.longPress(find.byKey(const ValueKey('cache-result-bog-11')));
      await pumpFrames(tester);
      await tester.tap(find.text('删除本地缓存'));
      await pumpFrames(tester);
      expect(find.text('删除 1 条本地缓存？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await pumpFrames(tester);
      expect(await store.find(ForumSite.bog, 'anonymous', 11), isNotNull);
      await tester.tap(find.text('删除本地缓存'));
      await pumpFrames(tester);
      await tester.tap(find.text('确认'));
      await pumpFrames(tester);
      expect(await store.find(ForumSite.bog, 'anonymous', 11), isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('settings reflect database stats, theme and auto cache toggle', (
    tester,
  ) async {
    await pump(tester, route: '/settings/cache', size: const Size(320, 844));
    expect(find.text('缓存配置'), findsOneWidget);
    expect(find.textContaining('6 条 · 永久保留 0 条'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await pumpFrames(tester);
    expect(store.enabled, false);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpFrames(tester);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'only sidebar browse search entry remains; loaded posts are not visits',
    (tester) async {
      await pump(tester, route: '/plate/0', offline: false);
      expect(find.byKey(const Key('local-search-entry')), findsNothing);
      await tester.tap(find.byTooltip('打开导航'));
      await pumpFrames(tester);
      expect(find.text('最近浏览'), findsNothing);
      await tester.tap(find.text('浏览搜索'));
      await pumpFrames(tester);
      expect(find.byKey(const Key('local-search-query')), findsOneWidget);
      expect(find.text('还没有浏览记录'), findsNothing);
      expect(find.byKey(const ValueKey('cache-result-bog-11')), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      await tester.enterText(find.byKey(const Key('local-search-query')), '海风');
      await pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('cache-result-islander-11')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'opened roots and merely loaded replies both appear without a query',
    (tester) async {
      await pump(tester, route: '/post/10');
      expect(
        (await store.find(ForumSite.islander, 'anonymous', 10))!.browsedAt,
        isNotNull,
      );
      expect(
        (await store.find(ForumSite.islander, 'anonymous', 11))!.browsedAt,
        isNull,
      );
      AppRouter.router.push('/local-search');
      await pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('cache-result-islander-10')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cache-result-islander-11')),
        180,
        scrollable: find.descendant(
          of: find.byKey(const Key('local-search-results')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.byKey(const ValueKey('cache-result-islander-11')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'right-aligned multi-select enters empty selection and supports deselection',
    (tester) async {
      await pump(tester, size: const Size(320, 844));
      final button = find.byKey(const Key('browse-multiselect'));
      expect(find.text('多选'), findsOneWidget);
      expect(find.text('选择已展示内容'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(tester.getRect(button).right, closeTo(300, 1));
      await tester.tap(button);
      await pumpFrames(tester);
      expect(find.text('已选 0 条'), findsOneWidget);
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((c) => c.value == false),
        isTrue,
      );
      final row = find.byKey(const ValueKey('cache-result-bog-11'));
      await tester.tap(row);
      await pumpFrames(tester);
      expect(find.text('已选 1 条'), findsOneWidget);
      await tester.tap(row);
      await pumpFrames(tester);
      expect(find.text('已选 0 条'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      await tester.tap(find.text('完成'));
      await pumpFrames(tester);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('浏览搜索'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final route in ['/local-search', '/settings', '/settings/cache']) {
    testWidgets(
      '$route slides from left on entry and shrinks to center on pop',
      (tester) async {
        await pump(tester, route: '/plate/0', offline: false);
        AppRouter.router.push(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final slide = find.byKey(const ValueKey('forum-auxiliary-slide')).last;
        expect(
          tester.widget<FractionalTranslation>(slide).translation.dx,
          lessThan(0),
        );
        await pumpFrames(tester);
        final pane = find.descendant(
          of: find.byType(ForumAuxiliaryTransition).last,
          matching: find.byKey(const ValueKey('forum-reading-scale')),
        );
        final original = tester.getRect(pane);
        AppRouter.router.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          tester.widget<FractionalTranslation>(slide).translation,
          Offset.zero,
        );
        expect(
          tester.widget<Transform>(pane).transform.entry(0, 0),
          lessThan(1),
        );
        expect(
          tester.getRect(pane).center.dx,
          closeTo(original.center.dx, .01),
        );
        expect(
          tester.getRect(pane).center.dy,
          closeTo(original.center.dy, .01),
        );
        await pumpFrames(tester);
        expect(find.byType(ForumAuxiliaryTransition), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
