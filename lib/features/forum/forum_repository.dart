import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/dio_client.dart';
import '../../main.dart';
import '../../shared/widgets/media_item.dart';
import '../plate/models/plate_model.dart';
import '../plate/models/post_model.dart';
import 'data/adapters/islander_adapter.dart';
import 'domain/forum_site.dart';
export 'domain/forum_site.dart';

final forumRepositoryProvider = Provider<ForumRepository>(
  (ref) => ForumRepository(ref.watch(dioClientProvider)),
);

class ForumFailure implements Exception {
  const ForumFailure(this.message, {this.code = 'request'});
  final String message;
  final String code;
  @override
  String toString() => message;
}

class PostPage {
  const PostPage(
    this.posts,
    this.count, {
    required this.hasMore,
    this.totalPages,
    this.nextPage,
    this.root,
    this.offset,
  });
  final List<Post> posts;

  /// Legacy UI bridge only. Unknown totals are null in [totalCount].
  final int count;
  int? get totalCount => count < 0 ? null : count;
  final bool hasMore;
  final int? totalPages;

  /// Adapter-owned zero-based cursor for the existing paged UI.
  final String? nextPage;
  final Post? root;
  final int? offset;
}

/// Shared contract with numeric entrypoints as a temporary legacy route bridge.
/// Content/cache identity uses endpoint-bound PostKey, not these numeric IDs.
abstract class ForumRepository {
  factory ForumRepository(DioClient client) = IslanderAdapter;
  ForumRepository.base();
  static const pageSize = 20;
  ForumSite get site => ForumSite.islander;
  ForumCapabilities get capabilities => ForumCapabilities.islander;
  Future<List<Plate>> plates();
  Future<Post> post(int id);
  Future<Post> thread(int id) => post(id);
  Future<PostPage> page({
    required String kind,
    int boardId = 0,
    String? boardKey,
    int postId = 0,
    int page = 0,
  });
  Future<int> replyPage(int threadId, int replyId) => unsupported('回复定位');
  Future<T> unsupported<T>(String action) =>
      Future.error(ForumFailure('当前站点尚未支持：$action', code: 'unsupported'));
  Future<void> publish({
    required String body,
    String title = '',
    required int boardId,
    int? threadId,
    List<MediaItem> media = const [],
    String? expectedToken,
  }) => unsupported('发布');
  Future<Map<String, dynamic>> verifyToken(String token) => unsupported('身份验证');
  Future<String> register() => unsupported('领取饼干');
  Future<void> vote(int id, bool add, {String? expectedToken}) =>
      unsupported('SAGE');
  Future<void> changeVisibility(
    int id, {
    required bool recover,
    String? expectedToken,
  }) => unsupported('删除或恢复');
  Future<MediaItem> upload(
    XFile file,
    String type,
    void Function(int, int) onProgress, {
    String? expectedToken,
  }) => unsupported('上传');
  void dispose() {}
  static List<int> quoteIds(String body) =>
      RegExp(r'(?:No\.|Po\.|>>)(\d+)', caseSensitive: false)
          .allMatches(body)
          .map((m) => int.parse(m[1]!))
          .where((id) => id > 0)
          .toSet()
          .toList();
}
