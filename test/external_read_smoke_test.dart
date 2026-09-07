import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/features/forum/data/adapters/x_adapter.dart';
import 'package:islander_flutter/features/forum/data/adapters/bog_adapter.dart';

class _PublicReadHttp extends HttpOverrides {}

void main() {
  // Explicit opt-in only. No cookies, writes, production secrets or post text in logs.
  test(
    'native anonymous three-step external read smoke',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        for (final repo in [XAdapter(), BogAdapter()]) {
          try {
            final boards = await repo.plates();
            final timeline = await repo.page(kind: 'timeline');
            expect(boards, isNotEmpty);
            expect(timeline.posts, isNotEmpty);
            final id = timeline.posts.first.id;
            final thread = await repo.page(kind: 'thread', postId: id);
            expect(thread.root!.id, id);
            final quote = await repo.post(id);
            expect(quote.id, id);
            // ignore: avoid_print
            print(
              '${repo.site.id}: boards=${boards.length}, timeline=${timeline.posts.length}, thread=${thread.posts.length}, quote=ok',
            );
          } finally {
            repo.dispose();
          }
        }
      }, _PublicReadHttp());
    },
    skip: !const bool.fromEnvironment('RUN_EXTERNAL_READ_SMOKE'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
