import 'dart:async';
import 'package:image_picker/image_picker.dart';
import '../../shared/widgets/media_item.dart';
import '../plate/models/plate_model.dart';
import '../plate/models/post_model.dart';
import '../forum/forum_repository.dart';
import 'cache_store.dart';

/// Read-through cache only. Writes always go to the existing authenticated adapter.
class CachedForumRepository extends ForumRepository {
  CachedForumRepository(this.remote, this.store, this.identity) : super.base();
  final ForumRepository remote;
  final CacheStore store;
  final String identity;
  bool _disposed = false;
  @override
  ForumSite get site => remote.site;
  @override
  ForumCapabilities get capabilities => remote.capabilities;
  @override
  Future<List<Plate>> plates() => remote.plates();

  Future<void> _capture(
    Iterable<Post> posts,
    int generation, {
    int? thread,
    int? page,
  }) async {
    if (_disposed) return;
    try {
      await store.capture(
        site,
        identity,
        posts,
        threadId: thread,
        page: page,
        expectedGeneration: generation,
      );
    } catch (_) {
      /* Cache failure must not hide successful online content. */
    }
  }

  Future<Post> _read(int id, Future<Post> Function() fetch) async {
    final generation = store.generation;
    try {
      final p = await fetch();
      unawaited(_capture([p], generation));
      return p;
    } catch (error) {
      if (_disposed) rethrow;
      try {
        final row = await store.find(site, identity, id);
        if (row != null) {
          await store.touch([row.rowId]);
          return row.post;
        }
        final replies = await store.thread(site, identity, id);
        if (replies.isNotEmpty) {
          return Post(
            id: id,
            source: site,
            fromCache: true,
            value: '主贴尚未缓存，仅展示本机已有回复。',
          );
        }
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<Post> post(int id) => _read(id, () => remote.post(id));
  @override
  Future<Post> thread(int id) => _read(id, () => remote.thread(id));

  Future<PostPage> localThread(int id, {int page = 0}) async {
    final rows = await store.thread(site, identity, id);
    if (rows.isEmpty) throw const ForumFailure('本机没有缓存该串内容');
    final root = rows.where((r) => r.post.id == id).firstOrNull;
    final replies = rows.where((r) => r.post.id != id).toList();
    // Cached pages can be sparse. Do not imply uncached gaps are complete.
    final available = replies.map((r) => r.page ?? 0).toSet().toList()..sort();
    final resolved = available.contains(page)
        ? page
        : available.where((p) => p >= page).firstOrNull ??
              available.lastOrNull ??
              0;
    final selected = replies.where((r) => (r.page ?? 0) == resolved).toList();
    final maxPage = replies.fold(
      0,
      (n, r) => n > (r.page ?? 0) ? n : (r.page ?? 0),
    );
    await store.touch([
      if (root != null) root.rowId,
      ...selected.map((r) => r.rowId),
    ]);
    return PostPage(
      selected.map((r) => r.post).toList(),
      -1,
      hasMore: resolved < maxPage,
      resolvedPage: resolved,
      root:
          root?.post ??
          Post(
            id: id,
            source: site,
            fromCache: true,
            value: '主贴尚未缓存，仅展示本机已有回复。',
          ),
      fromCache: true,
    );
  }

  @override
  Future<PostPage> page({
    required String kind,
    int boardId = 0,
    String? boardKey,
    int postId = 0,
    int page = 0,
  }) async {
    final generation = store.generation;
    try {
      final data = await remote.page(
        kind: kind,
        boardId: boardId,
        boardKey: boardKey,
        postId: postId,
        page: page,
      );
      unawaited(
        _capture(
          [if (data.root != null) data.root!, ...data.posts],
          generation,
          thread: kind == 'thread' ? postId : null,
          page: kind == 'thread' ? page : null,
        ),
      );
      return data;
    } catch (error) {
      if (kind != 'thread' || _disposed) rethrow;
      try {
        return await localThread(postId, page: page);
      } catch (_) {
        throw error;
      }
    }
  }

  @override
  Future<int> replyPage(int threadId, int replyId) async {
    try {
      return await remote.replyPage(threadId, replyId);
    } catch (_) {
      final row = await store.find(site, identity, replyId);
      if (row?.threadId == threadId && row?.page != null) return row!.page!;
      rethrow;
    }
  }

  @override
  Future<void> publish({
    required String body,
    String title = '',
    required int boardId,
    String? boardKey,
    int? threadId,
    List<MediaItem> media = const [],
    List<XFile> files = const [],
    String? expectedToken,
  }) => remote.publish(
    body: body,
    title: title,
    boardId: boardId,
    boardKey: boardKey,
    threadId: threadId,
    media: media,
    files: files,
    expectedToken: expectedToken,
  );
  @override
  Future<void> vote(int id, bool add, {String? expectedToken}) =>
      remote.vote(id, add, expectedToken: expectedToken);
  @override
  Future<void> changeVisibility(
    int id, {
    required bool recover,
    String? expectedToken,
  }) => remote.changeVisibility(
    id,
    recover: recover,
    expectedToken: expectedToken,
  );
  @override
  Future<MediaItem> upload(
    XFile file,
    String type,
    void Function(int, int) onProgress, {
    String? expectedToken,
  }) => remote.upload(file, type, onProgress, expectedToken: expectedToken);
  @override
  Future<Map<String, dynamic>> verifyToken(String token) =>
      remote.verifyToken(token);
  @override
  Future<String> register() => remote.register();
  @override
  void dispose() {
    _disposed = true;
  }
}
