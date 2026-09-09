import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import '../forum/application/external_identity.dart';
import '../forum/forum_repository.dart';
import 'cache_store.dart';
import 'cached_repository.dart';

final cacheStoreProvider = ChangeNotifierProvider<CacheStore>(
  (ref) => CacheStore(),
);

final cacheIdentityProvider = Provider.family<String, ForumSite>(
  (ref, site) => site.isIslander
      ? ref.watch(authProvider.select((s) => s.activeId)) ?? 'anonymous'
      : ref.watch(externalIdentityProvider(site)).asData?.value.activeId ??
            'anonymous',
);

final cacheScopesProvider = Provider<Map<String, String>>(
  (ref) => {
    for (final site in ForumSite.all)
      site.instanceKey: ref.watch(cacheIdentityProvider(site)),
  },
);

final cachedForumRepositoryProvider = Provider<CachedForumRepository>((ref) {
  final repo = ref.watch(forumRepositoryProvider);
  final wrapper = CachedForumRepository(
    repo,
    ref.read(cacheStoreProvider),
    ref.watch(cacheIdentityProvider(repo.site)),
  );
  ref.onDispose(wrapper.dispose);
  return wrapper;
}, dependencies: [forumRepositoryProvider]);
