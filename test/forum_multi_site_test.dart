import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:islander_flutter/app.dart';
import 'package:islander_flutter/main.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';
import 'package:islander_flutter/features/forum/application/site_scope.dart';
import 'package:islander_flutter/features/forum/application/forum_state_store.dart';
import 'package:islander_flutter/features/forum/data/adapters/x_adapter.dart';
import 'package:islander_flutter/features/forum/data/adapters/bog_adapter.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'package:islander_flutter/features/forum/forum_post_view.dart';
import 'package:islander_flutter/shared/widgets/rich_post_text.dart';
import 'external_adapter_test.dart' show ExternalFixture, xPost, bogPage;
import 'support/forum_fixture.dart';

Future<StorageService> pumpSites(
  WidgetTester tester,
  ExternalFixture fixture, {
  String route = '/s/x/plate/0',
  ForumFixture? localFixture,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'token': 'islander-only',
    'name': '原身份',
    'userId': 7,
  });
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.initialize();
  AppRouter.router.go(route);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        dioClientProvider.overrideWithValue(
          (localFixture ?? ForumFixture()).client(),
        ),
        externalRepositoryProvider(
          'x',
        ).overrideWith((ref) => XAdapter(transport: fixture.client())),
        externalRepositoryProvider(
          'bog',
        ).overrideWith((ref) => BogAdapter(transport: fixture.client())),
      ],
      child: const IslanderApp(),
    ),
  );
  await pumpFrames(tester);
  return storage;
}

ExternalFixture fixture({Completer<dynamic>? delayed}) => ExternalFixture((r) {
  if (r.uri.host == 'bog.ac') return bogPage();
  switch (r.uri.pathSegments.last) {
    case 'getForumList':
      return [
        {
          'forums': [
            {'id': 1, 'name': '综合版'},
          ],
        },
      ];
    case 'getTimelineList':
      return [
        {'id': 1, 'max_page': 10},
      ];
    case 'thread':
      return {
        ...xPost(10, replies: 20),
        'Replies': [xPost(r.uri.queryParameters['page'] == '1' ? 11 : 30)],
      };
    case 'ref':
      return xPost(int.parse(r.uri.queryParameters['id']!));
    default:
      return delayed?.future ?? List.generate(20, (i) => xPost(10 + i));
  }
});

void main() {
  for (final site in ForumSite.all) {
    testWidgets(
      '${site.id} fresh timeline ignores saved page and anchor without deleting history',
      (tester) async {
        final api = fixture();
        final local = ForumFixture();
        await pumpSites(
          tester,
          api,
          route: site.route('/post/10'),
          localFixture: local,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(IslanderApp)),
        );
        final store = container.read(forumStateStoreProvider);
        final identity = site.isIslander
            ? container.read(authProvider).activeId!
            : 'anonymous';
        // Seed a legacy record: new screens now put visit timestamps in SQLite.
        await store.save(
          site: site,
          identity: identity,
          route: site.route('/post/10'),
          page: 0,
          threadId: 10,
          historyEpoch: 0,
        );
        await store.save(
          site: site,
          identity: identity,
          route: site.route('/plate/0'),
          page: 3,
          anchor: 999,
          fraction: .6,
          newest: true,
          historyEpoch: 0,
        );
        api.requests.clear();
        local.requests.clear();
        AppRouter.router.go(
          site.route('/plate/0'),
          extra: AppRouter.freshTimeline,
        );
        await pumpFrames(tester);
        if (site.isIslander) {
          final requests = local.requests.where(
            (r) => r.uri.path.endsWith('/forum/indexLast'),
          );
          expect(requests, isNotEmpty);
          expect(requests.every((r) => r.queryParameters['page'] == 0), isTrue);
        } else if (site.id == 'x') {
          final requests = api.requests.where(
            (r) => r.uri.pathSegments.last == 'timeline',
          );
          expect(requests, isNotEmpty);
          expect(
            requests.every((r) => r.uri.queryParameters['page'] == '1'),
            isTrue,
          );
        } else {
          expect(api.requests, isNotEmpty);
          expect(
            api.requests.every((r) => r.uri.pathSegments.last == '1'),
            isTrue,
          );
        }
        expect(find.byKey(const ValueKey('post-10')), findsOneWidget);
        expect(store.history(store.scopeKey(site, identity)), isNotEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('wide hover delays previews and never creates reading history', (
    tester,
  ) async {
    final original = fixture();
    final api = ExternalFixture((r) {
      if (r.uri.pathSegments.last == 'timeline') {
        return List.generate(20, (i) => xPost(10 + i, replies: 6));
      }
      return original.respond(r);
    });
    final storage = await pumpSites(tester, api);
    tester.view.physicalSize = const Size(1200, 900);
    await pumpFrames(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('post-10'))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      api.requests.where((r) => r.uri.pathSegments.last == 'thread'),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await pumpFrames(tester);
    expect(
      api.requests.where((r) => r.uri.pathSegments.last == 'thread'),
      hasLength(1),
    );
    final store = ForumStateStore(storage);
    expect(store.history(store.scopeKey(ForumSite.x, 'anonymous')), isEmpty);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saved thread page and post anchor restore without scanning whole thread',
    (tester) async {
      final api = fixture();
      await pumpSites(tester, api);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(IslanderApp)),
      );
      final store = container.read(forumStateStoreProvider);
      await store.save(
        site: ForumSite.x,
        identity: 'anonymous',
        route: '/s/x/post/10',
        page: 1,
        anchor: 30,
        fraction: .2,
        threadId: 10,
        historyEpoch: 0,
      );
      AppRouter.router.go('/s/x/post/10');
      await pumpFrames(tester);
      expect(
        api.requests
            .where((r) => r.uri.pathSegments.last == 'thread')
            .map((r) => r.uri.queryParameters['page']),
        ['2'],
      );
      expect(
        find.byWidgetPredicate((w) => w is ForumPostView && w.post.id == 30),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'external timeline uses shared shell and hides all unsupported actions',
    (tester) async {
      final api = fixture();
      final storage = await pumpSites(tester, api);
      expect(find.text('X 岛'), findsOneWidget);
      expect(find.byKey(const Key('fab-compose')), findsOneWidget);
      expect(find.byKey(const ValueKey('post-actions-10')), findsNothing);
      expect(find.text('20 条已加载'), findsOneWidget);
      expect(
        api.requests.every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
      expect(storage.cookies.single.token, 'islander-only');
      await tester.tap(find.byKey(const Key('page-jump-trigger')));
      await pumpFrames(tester);
      expect(find.text('跳到末页'), findsNothing);
      expect(find.textContaining('总页数未知'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'thread and nested quote retain site; unknown parent offers no fake jump',
    (tester) async {
      final api = fixture();
      final storage = await pumpSites(tester, api, route: '/s/x/post/10');
      expect(
        find.byWidgetPredicate((w) => w is ForumPostView && w.post.id == 10),
        findsOneWidget,
      );
      final body = find.byType(RichPostText).first;
      final rich = tester.widget<SelectableText>(
        find.descendant(of: body, matching: find.byType(SelectableText)),
      );
      final span = rich.textSpan!.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text?.contains('No.42') == true,
      );
      (span.recognizer as TapGestureRecognizer).onTap!();
      await pumpFrames(tester);
      expect(api.requests.last.uri.path, '/api/ref');
      expect(find.text('前往 No.42 所在串 →'), findsNothing);
      expect(find.byKey(const ValueKey('post-actions-42')), findsNothing);
      final history = ForumStateStore(
        storage,
      ).history(ForumStateStore(storage).scopeKey(ForumSite.x, 'anonymous'));
      expect(history, isEmpty);
      expect(
        ForumStateStore(storage).position(
          ForumStateStore(storage).scopeKey(ForumSite.x, 'anonymous'),
          '/s/x/post/10',
        ),
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('late X responses never replace BOG after switching routes', (
    tester,
  ) async {
    final delayed = Completer<dynamic>();
    final api = fixture(delayed: delayed);
    await pumpSites(tester, api);
    AppRouter.router.go('/s/bog/plate/0');
    await pumpFrames(tester);
    expect(find.text('BOG'), findsOneWidget);
    delayed.complete([xPost(777)]);
    await pumpFrames(tester);
    expect(
      find.byWidgetPredicate((w) => w is ForumPostView && w.post.id == 777),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ForumPostView && w.post.site.id == 'bog',
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'sidebar switches all three sites and Islander still has its composer',
    (tester) async {
      await pumpSites(tester, fixture());
      await tester.tap(find.byTooltip('打开导航'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('site-selector')));
      await pumpFrames(tester);
      await tester.tap(find.text('岛民岛').last);
      await pumpFrames(tester);
      expect(find.byKey(const Key('fab-compose')), findsOneWidget);
      expect(find.text('岛民岛'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
