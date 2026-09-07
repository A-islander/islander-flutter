import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../plate/models/plate_model.dart';
import '../../../plate/models/post_model.dart';
import '../../forum_repository.dart';
import 'external_adapter.dart';

class XAdapter extends ExternalAdapter {
  XAdapter({ForumSite? site, Dio? transport, String userhash = ''})
    : super(
        site ?? ForumSite.x,
        transport: transport,
        cookie: userhash.isEmpty ? '' : 'userhash=${validateCookie(userhash)}',
      );
  String? _cdn;
  static String validateCookie(String value) {
    if (value.isEmpty || RegExp(r'[\s;\x00-\x1f\x7f]').hasMatch(value)) {
      throw const ForumFailure('请输入完整 userhash 值，不要附加 Cookie 名称或分隔符');
    }
    return value;
  }

  @override
  ForumCapabilities get capabilities => const ForumCapabilities(verify: true);

  Future<dynamic> _json(String path, [Map<String, dynamic>? query]) async {
    final data = await get(path, query: query);
    if (data == null ||
        data is Map && (data['error'] != null || data['success'] == false)) {
      throw const ForumFailure('X 岛拒绝读取，内容可能不存在或需要饼干权限', code: 'response');
    }
    return data;
  }

  Future<String> _imageBase() async {
    if (_cdn != null) return _cdn!;
    final data = await _json('getCDNPath');
    if (data is List) {
      for (final row in data.whereType<Map>()) {
        final url = '${row['url'] ?? ''}';
        if (ExternalAdapter.safeUrl(url)) {
          return _cdn = '${url.replaceAll(RegExp(r'/+$'), '')}/';
        }
      }
    }
    throw const ForumFailure('X 岛未返回有效图片地址', code: 'parse');
  }

  String _name(dynamic value) {
    final name = ExternalAdapter.text('${value ?? ''}');
    return ['无名氏', '无标题'].contains(name) ? '' : name;
  }

  Future<Post> _post(
    Map row, {
    int parent = 0,
    bool unknown = false,
    bool previews = false,
  }) async {
    final id = ExternalAdapter.number(row['id']);
    if (id <= 0 || row['user_hash'] == 'Tips') {
      throw const ForumFailure('X 岛帖子编号缺失或内容不存在', code: 'parse');
    }
    final author = ExternalAdapter.text('${row['user_hash'] ?? ''}');
    final name = _name(row['name']);
    final body = ExternalAdapter.text('${row['content'] ?? ''}');
    final media = <Map<String, String>>[];
    if ('${row['img'] ?? ''}'.isNotEmpty) {
      final base = await _imageBase();
      final path = '${row['img']}${row['ext'] ?? ''}'.replaceFirst(
        RegExp(r'^/+'),
        '',
      );
      media.add({
        'url': '${base}image/$path',
        'thumbnailUrl': '${base}thumb/$path',
        'type': 'image',
      });
    }
    final replies = <Post>[];
    if (previews && row['Replies'] is List) {
      for (final reply
          in (row['Replies'] as List)
              .whereType<Map>()
              .where((r) => r['user_hash'] != 'Tips')
              .take(5)) {
        replies.add(await _post(reply, parent: id));
      }
    }
    return Post(
      id: id,
      source: site,
      sourceId: '$id',
      followId: parent,
      parentUnknown: unknown,
      boardKey: '${row['fid'] ?? ''}',
      plateId: ExternalAdapter.number(row['fid']),
      authorId: author,
      name: name.isEmpty ? author : '$name / $author',
      title: _name(row['title']),
      value: body,
      replyArr: ForumRepository.quoteIds(body),
      time: ExternalAdapter.timestamp('${row['now'] ?? ''}'),
      replyCount: ExternalAdapter.number(row['ReplyCount']),
      status: ExternalAdapter.number(row['sage']) == 0 ? 0 : 1,
      mediaUrl: media.isEmpty ? '' : jsonEncode(media),
      lastReplyArr: replies,
    );
  }

  @override
  Future<List<Plate>> plates() async {
    final data = await _json('getForumList');
    final boards = <int, Plate>{};
    if (data is List) {
      for (final group in data.whereType<Map>()) {
        if (group['forums'] is! List) continue;
        for (final row in (group['forums'] as List).whereType<Map>()) {
          final id = ExternalAdapter.number(row['id']);
          if (id > 0) {
            boards[id] = Plate(
              id: id,
              name: ExternalAdapter.text('${row['name'] ?? ''}'),
              status: 0,
              value: ExternalAdapter.text('${row['msg'] ?? ''}'),
            );
          }
        }
      }
    }
    if (boards.isEmpty) throw const ForumFailure('X 岛板块格式已变化', code: 'parse');
    return boards.values.toList();
  }

  @override
  Future<Post> post(int id) async {
    final data = await _json('ref', {'id': id});
    if (data is! Map || ExternalAdapter.number(data['id']) != id) {
      throw const ForumFailure('X 岛引用不存在', code: 'not_found');
    }
    return _post(data, unknown: true);
  }

  @override
  Future<Post> thread(int id) async =>
      (await page(kind: 'thread', postId: id)).root!;
  @override
  Future<PostPage> page({
    required String kind,
    int boardId = 0,
    String? boardKey,
    int postId = 0,
    int page = 0,
  }) async {
    ExternalAdapter.validPage(page);
    var id = kind == 'thread'
        ? postId
        : int.tryParse(boardKey ?? '') ?? boardId;
    var path = kind == 'thread' ? 'thread' : 'showf';
    int? limit;
    if (kind == 'timeline') {
      path = 'timeline';
      final lines = await _json('getTimelineList');
      if (lines is! List || lines.isEmpty) {
        throw const ForumFailure('X 岛时间线信息缺失', code: 'parse');
      }
      final valid = lines
          .whereType<Map>()
          .where(
            (r) =>
                ExternalAdapter.number(r['id']) > 0 &&
                ExternalAdapter.number(r['max_page']) > 0,
          )
          .toList();
      if (valid.isEmpty) throw const ForumFailure('X 岛时间线信息缺失', code: 'parse');
      final line =
          valid
              .where((r) => ExternalAdapter.number(r['id']) == 1)
              .firstOrNull ??
          valid.first;
      id = ExternalAdapter.number(line['id']);
      limit = ExternalAdapter.number(line['max_page']);
    } else if (!['board', 'thread'].contains(kind)) {
      return unsupported(kind);
    }
    if (id <= 0) throw const ForumFailure('请提供有效的板块或主串编号');
    if (limit != null && page >= limit) {
      throw const ForumFailure('超过此时间线页数上限', code: 'limit');
    }
    final data = await _json(path, {'id': id, 'page': page + 1});
    Post? root;
    late List rows;
    late bool more;
    int? pages;
    if (kind == 'thread') {
      if (data is! Map ||
          ExternalAdapter.number(data['id']) != id ||
          data['Replies'] is! List) {
        throw const ForumFailure('请提供 X 岛主串编号；引用接口无法确定父串', code: 'not_found');
      }
      root = await _post(data);
      pages = ((root.replyCount + 18) ~/ 19).clamp(1, 1000000);
      if (page >= pages) throw const ForumFailure('超过此串回复页数上限', code: 'limit');
      rows = [if (page == 0) data, ...data['Replies'] as List];
      more = page + 1 < pages;
    } else {
      if (data is! List) throw const ForumFailure('X 岛列表格式异常', code: 'parse');
      rows = data;
      more = rows.length >= 20 && (limit == null || page + 1 < limit);
    }
    final posts = <int, Post>{};
    for (final row in rows) {
      if (row is! Map) throw const ForumFailure('X 岛帖子格式异常', code: 'parse');
      if (row['user_hash'] == 'Tips') continue;
      final post = await _post(
        row,
        parent: kind == 'thread' && ExternalAdapter.number(row['id']) != id
            ? id
            : 0,
        previews: kind != 'thread',
      );
      posts[post.id] = post;
    }
    return PostPage(
      posts.values.toList(),
      root == null ? -1 : root.replyCount + 1,
      root: root,
      hasMore: more,
      totalPages: pages,
      nextPage: more ? '${page + 1}' : null,
    );
  }

  @override
  Future<Map<String, dynamic>> verifyToken(String token) async {
    final verifier = XAdapter(site: site, userhash: validateCookie(token));
    try {
      final data = await verifier._json('showf', {'id': 27, 'page': 1});
      if (data is! List) throw const ForumFailure('无法确认饼干访问权限');
      return {'name': 'X 岛饼干', 'verification': 'restricted-board'};
    } finally {
      verifier.dispose();
    }
  }
}
