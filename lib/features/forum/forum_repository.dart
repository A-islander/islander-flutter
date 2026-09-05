import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/dio_client.dart';
import '../../main.dart';
import '../plate/models/plate_model.dart';
import '../plate/models/post_model.dart';
import '../../shared/widgets/media_item.dart';

final forumRepositoryProvider = Provider<ForumRepository>(
  (ref) => ForumRepository(ref.watch(dioClientProvider)),
);

class ForumFailure implements Exception {
  const ForumFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class PostPage {
  const PostPage(this.posts, this.count);
  final List<Post> posts;
  final int count;
}

class ForumRepository {
  ForumRepository(this.client);
  final DioClient client;
  static const pageSize = 20;

  Future<dynamic> _read(Future<Response<dynamic>> request) async {
    try {
      final response = await request;
      final data = response.data;
      if (data is! Map || data['code'] != 200) {
        if (DioClient.authenticationFailed(data)) {
          throw const ForumFailure('饼干无效或已过期，请重新导入饼干');
        }
        throw ForumFailure(
          data is Map ? '${data['msg'] ?? '请求失败，请稍后重试'}' : '服务器返回格式异常',
        );
      }
      return data['data'];
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw const ForumFailure('饼干无效或已过期，请重新导入饼干');
      }
      throw const ForumFailure('连接失败，请检查网络后重试');
    }
  }

  Future<List<Plate>> plates() async {
    final data = await _read(client.getPlates());
    return (data as List? ?? [])
        .map((e) => Plate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Post> post(int id) async {
    final data = await _read(client.getPost(id));
    if (data is! Map) throw const ForumFailure('这条内容不存在或无法查看');
    return Post.fromJson(Map<String, dynamic>.from(data));
  }

  Future<PostPage> page({
    required String kind,
    int boardId = 0,
    int postId = 0,
    int page = 0,
  }) async {
    final request = switch (kind) {
      'board' => client.getForumIndex(plateId: boardId, page: page),
      'thread' => client.getForumList(postId: postId, page: page),
      'sage' => client.getSageList(page: page),
      'mine' => client.getUserList(page: page),
      _ => client.getIndexLast(page: page),
    };
    final data = await _read(request);
    final list = data is Map
        ? data['list'] as List? ?? []
        : data as List? ?? [];
    final count = data is Map
        ? data['count'] as int? ?? list.length
        : list.length;
    return PostPage(
      list
          .map((e) => Post.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      count,
    );
  }

  // postPage is one-based; list endpoints are zero-based and include the OP.
  Future<int> replyPage(int threadId, int replyId) async {
    final data = await _read(
      client.forumDio.get(
        'forum/postPage',
        queryParameters: {
          'postId': threadId,
          'replyId': replyId,
          'size': pageSize,
        },
      ),
    );
    return ((data['page'] as int? ?? 1) - 1).clamp(0, 1000000);
  }

  static List<int> quoteIds(String body) =>
      RegExp(r'No\.(\d+)', caseSensitive: false)
          .allMatches(body)
          .map((m) => int.parse(m[1]!))
          .where((id) => id > 0)
          .toSet()
          .toList();

  Future<void> publish({
    required String body,
    String title = '',
    required int boardId,
    int? threadId,
    List<MediaItem> media = const [],
  }) async {
    if (body.trim().isEmpty || utf8.encode(body).length > 8192) {
      throw const ForumFailure('正文不能为空，且不能超过 8192 字节（约 2700 个汉字）');
    }
    if (utf8.encode(title).length > 128) {
      throw const ForumFailure('标题过长，请缩短后重试');
    }
    final payload = <String, dynamic>{
      'value': body,
      'replyArr': quoteIds(body),
      'mediaUrl': jsonEncode(
        media
            .map(
              (e) => {
                'id': e.id,
                'url': e.url,
                'thumbnailUrl': e.thumbnailUrl,
                'type': e.type,
              },
            )
            .toList(),
      ),
      if (threadId == null) ...{
        'title': title,
        'plateId': boardId,
      } else
        'followId': threadId,
    };
    if (utf8.encode(payload['mediaUrl'] as String).length > 2048) {
      throw const ForumFailure('附件信息过长，请减少附件数量');
    }
    await _read(
      client.forumDio.post(
        threadId == null ? 'forum/post' : 'forum/reply',
        data: payload,
      ),
    );
  }

  Future<Map<String, dynamic>> verifyToken(String token) async {
    final data = await _read(
      client.userDio.get(
        'user/get',
        options: Options(
          headers: {'Authorization': token},
          extra: {'verifyToken': true},
        ),
      ),
    );
    final id = data is Map ? data['id'] ?? data['Id'] : null;
    if (data is! Map || id is! int || id <= 0) {
      throw const ForumFailure('无法验证饼干身份');
    }
    return {'id': id, 'name': data['name'] ?? data['Name'] ?? ''};
  }

  Future<String> register() async {
    final data = await _read(
      client.userDio.get(
        'user/register',
        options: Options(extra: {'verifyToken': true}),
      ),
    );
    final token = data is Map ? data['token']?.toString() ?? '' : '';
    if (token.isEmpty) throw const ForumFailure('暂时无法领取饼干，请稍后再试');
    return token;
  }

  Future<void> vote(int id, bool add) async {
    await _read(add ? client.sageAdd(id) : client.sageSub(id));
  }

  Future<void> changeVisibility(int id, {required bool recover}) async {
    final data = await _read(
      recover ? client.recoverOwnPost(id) : client.deleteOwnPost(id),
    );
    if (data is! Map || data['status'] != true) {
      throw const ForumFailure('操作未成功，可能没有权限');
    }
  }

  Future<MediaItem> upload(
    XFile file,
    String type,
    void Function(int, int) onProgress,
  ) async {
    if (await file.length() > 20 * 1024 * 1024) {
      throw const ForumFailure('单个文件不能超过 20 MB');
    }
    final data = await _read(
      client.forumDio.post(
        'img/upload',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            await file.readAsBytes(),
            filename: file.name,
          ),
        }),
        onSendProgress: onProgress,
      ),
    );
    final url = data is Map
        ? (data['data'] is Map ? data['data']['url'] : data['images'])
        : null;
    if (url is! String || !url.startsWith('https://')) {
      throw const ForumFailure('上传未成功，请重试');
    }
    return MediaItem(
      id: '${data['RequestId'] ?? ''}',
      url: url,
      thumbnailUrl: url,
      type: type,
    );
  }
}
