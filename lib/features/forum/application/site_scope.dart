import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/adapters/bog_adapter.dart';
import '../data/adapters/x_adapter.dart';
import '../forum_repository.dart';
import '../forum_screen.dart';
import 'external_identity.dart';

final externalRepositoryProvider = Provider.autoDispose
    .family<ForumRepository, String>((ref, id) {
      final cookie =
          ref
              .watch(externalIdentityProvider(ForumSite.byId(id)))
              .asData
              ?.value
              .token ??
          '';
      final ForumRepository repo = switch (id) {
        'x' => XAdapter(userhash: kIsWeb ? '' : cookie),
        'bog' => BogAdapter(cookie: kIsWeb ? '' : cookie),
        _ => throw const ForumFailure('未知站点'),
      };
      ref.onDispose(repo.dispose);
      return repo;
    });

/// A route owns its source for its entire lifetime, including nested quotes.
/// No global mutable baseUrl or Islander auth interceptor crosses this scope.
class ExternalForumScope extends ConsumerWidget {
  const ExternalForumScope({
    super.key,
    required this.siteId,
    required this.child,
  });
  final String siteId;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(
      externalIdentityProvider(ForumSite.byId(siteId)),
    );
    if (identity.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repo = ref.watch(externalRepositoryProvider(siteId));
    return ProviderScope(
      key: ValueKey(repo),
      overrides: [
        forumRepositoryProvider.overrideWithValue(repo),
        forumBoardsProvider.overrideWith((ref) => repo.plates()),
      ],
      child: child,
    );
  }
}
