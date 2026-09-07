import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../../../plate/models/plate_model.dart';
import '../../../plate/models/post_model.dart';
import '../../forum_repository.dart';
import 'external_adapter.dart';

class BogAdapter extends ExternalAdapter {
  BogAdapter({ForumSite? site, Dio? transport, String cookie = ''})
    : super(
        site ?? ForumSite.bog,
        transport: transport,
        cookie: cookie.isEmpty ? '' : validateCookie(cookie),
      );
  static String validateCookie(String value) {
    final pairs = <String, String>{};
    for (final part in value.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) throw const ForumFailure('BOG 饼干格式不完整');
      final name = part.substring(0, index).trim();
      final entry = part.substring(index + 1).trim();
      if (!['bog_master', 'bog_sel', 'bog_list'].contains(name) ||
          pairs.containsKey(name) ||
          entry.isEmpty ||
          RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(entry)) {
        throw const ForumFailure('BOG 饼干包含无效字段');
      }
      pairs[name] = entry;
    }
    if (!pairs.containsKey('bog_master') || !pairs.containsKey('bog_sel')) {
      throw const ForumFailure('需要 bog_master 和 bog_sel');
    }
    return pairs.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<dom.Document> _document(String path) async {
    final doc = html.parse(await get(path, json: false) as String);
    if (doc.querySelector('.item-list') == null ||
        doc.querySelector('.pages .page-main') == null) {
      throw const ForumFailure('BOG 未返回论坛页面，可能需要权限或网页结构已变化', code: 'parse');
    }
    return doc;
  }

  @override
  Future<List<Plate>> plates() async {
    final doc = await _document('f/${Uri.encodeComponent('时间线')}/1');
    final nav = doc.querySelector('.forum-list');
    if (nav == null) throw const ForumFailure('BOG 板块导航结构已变化', code: 'parse');
    final boards = <String, Plate>{};
    for (final link in nav.querySelectorAll('a[href]')) {
      final uri = Uri.tryParse(link.attributes['href']!);
      final parts = uri?.pathSegments.where((e) => e.isNotEmpty).toList() ?? [];
      if (parts.length != 2 || parts[0] != 'f' || parts[1] == '时间线') continue;
      final name = parts[1];
      boards[name] = Plate(
        id: 0,
        sourceKey: name,
        name: name,
        status: 0,
        value: '',
      );
    }
    if (boards.isEmpty) {
      throw const ForumFailure('BOG 板块导航为空或格式已变化', code: 'parse');
    }
    return boards.values.toList();
  }

  dom.Element? _own(dom.Element root, String name) {
    dom.Element? visit(dom.Element element) {
      if (element != root &&
          (element.classes.contains('item-main') ||
              element.classes.contains('item-reply'))) {
        return null;
      }
      if (element.classes.contains(name)) return element;
      for (final child in element.children) {
        final found = visit(child);
        if (found != null) return found;
      }
      return null;
    }

    return visit(root);
  }

  Post _post(dom.Element node, {int parent = 0, String? board}) {
    String ownText(String cls) => ExternalAdapter.nodeText(_own(node, cls));
    final match = RegExp(r'^\s*#(\d+)').firstMatch(ownText('item-pop'));
    final content = _own(node, 'item-content');
    if (match == null || content == null) {
      throw const ForumFailure('BOG 帖子编号或正文结构已变化', code: 'parse');
    }
    final id = int.parse(match[1]!);
    if (id <= 0) throw const ForumFailure('BOG 帖子编号无效', code: 'parse');
    final body = ExternalAdapter.nodeText(content);
    final media = <Map<String, String>>[];
    for (final img in node.querySelectorAll('img[data-img]')) {
      var owner = img.parent;
      while (owner != null &&
          !owner.classes.contains('item-main') &&
          !owner.classes.contains('item-reply')) {
        owner = owner.parent;
      }
      if (owner != node) continue;
      final full = Uri.parse(
        site.endpoint,
      ).resolve(img.attributes['data-img']!).toString();
      final thumb = Uri.parse(
        site.endpoint,
      ).resolve(img.attributes['src'] ?? '').toString();
      if (ExternalAdapter.safeUrl(full)) {
        media.add({
          'url': full,
          'thumbnailUrl': ExternalAdapter.safeUrl(thumb) ? thumb : full,
          'type': 'image',
        });
      }
    }
    final count = RegExp(
      r'查看全部\s*(\d+)\s*条回复',
    ).firstMatch(ownText('item-footer'));
    final preview = parent == 0
        ? node
              .querySelectorAll('.item-reply')
              .take(5)
              .map((e) => _post(e, parent: id, board: board))
              .toList()
        : <Post>[];
    return Post(
      id: id,
      source: site,
      sourceId: '$id',
      followId: parent,
      boardKey: board ?? ownText('item-fname'),
      name: ownText('item-id'),
      authorId: ownText('item-id'),
      title: ownText('item-title'),
      value: body,
      replyArr: ForumRepository.quoteIds(body),
      time: ExternalAdapter.timestamp(ownText('item-time')),
      replyCount: count == null ? preview.length : int.parse(count[1]!),
      mediaUrl: media.isEmpty ? '' : jsonEncode(media),
      lastReplyArr: preview,
    );
  }

  @override
  Future<Post> post(int id) async {
    final data = await get('api/thread/$id');
    if (data is! Map ||
        ExternalAdapter.number(data['code']) != 6001 ||
        data['info'] is! Map) {
      throw const ForumFailure('BOG 引用不存在或需要访问权限', code: 'not_found');
    }
    final row = data['info'] as Map;
    if (ExternalAdapter.number(row['id']) != id || id <= 0) {
      throw const ForumFailure('BOG 引用编号不符', code: 'parse');
    }
    final author = ExternalAdapter.text('${row['cookie'] ?? ''}');
    final name = ExternalAdapter.text('${row['name'] ?? ''}');
    final body = ExternalAdapter.text('${row['content'] ?? ''}');
    final images = <Map<String, String>>[];
    if (row['images'] != null && row['images'] is! List) {
      throw const ForumFailure('BOG 附件结构已变化', code: 'parse');
    }
    for (final img in (row['images'] as List? ?? []).whereType<Map>()) {
      final path = Uri.encodeComponent('${img['url'] ?? ''}');
      images.add({
        'url': '${site.endpoint}image/large/$path${img['ext'] ?? ''}',
        'thumbnailUrl': '${site.endpoint}image/thumb/$path.jpg',
        'type': 'image',
      });
    }
    return Post(
      id: id,
      source: site,
      sourceId: '$id',
      followId: ExternalAdapter.number(row['res']),
      parentUnknown: row['res'] == null,
      name: name.isEmpty ? author : '$name / $author',
      authorId: author,
      value: body,
      title: ExternalAdapter.text('${row['title'] ?? ''}'),
      time: ExternalAdapter.number(row['time']),
      replyArr: ForumRepository.quoteIds(body),
      mediaUrl: images.isEmpty ? '' : jsonEncode(images),
    );
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
    if (!['timeline', 'board', 'thread'].contains(kind)) {
      return unsupported(kind);
    }
    if (kind == 'board' && (boardKey == null || boardKey.isEmpty) ||
        kind == 'thread' && postId <= 0) {
      throw const ForumFailure('需要原始板块名称或有效主串编号');
    }
    final path = kind == 'thread'
        ? 't/$postId'
        : 'f/${Uri.encodeComponent(kind == 'timeline' ? '时间线' : boardKey!)}';
    final doc = await _document('$path/${page + 1}');
    final pager = doc.querySelector('.pages')!;
    final current = pager
        .querySelectorAll('.page-main span')
        .map((e) => int.tryParse(e.text.trim()))
        .whereType<int>();
    if (!current.contains(page + 1)) {
      throw const ForumFailure('BOG 返回页码与请求不符，或分页结构已变化', code: 'parse');
    }
    final expected = Uri.parse(site.endpoint).resolve('$path/${page + 2}');
    final more = pager.querySelectorAll('a[href]').any((a) {
      final uri = Uri.tryParse(a.attributes['href']!);
      if (uri == null) return false;
      final resolved = Uri.parse(site.endpoint).resolveUri(uri);
      if (!ExternalAdapter.safeUrl(resolved.toString())) return false;
      return resolved.origin == expected.origin &&
          resolved.path == expected.path;
    });
    final posts = <int, Post>{};
    Post? root;
    for (final node
        in doc
            .querySelector('.item-list')!
            .querySelectorAll('.item-main, .item-reply')) {
      final isRoot = node.classes.contains('item-main');
      if (!isRoot && kind != 'thread') continue;
      final post = _post(
        node,
        parent: isRoot ? 0 : postId,
        board: kind == 'board' ? boardKey : null,
      );
      if (isRoot && kind == 'thread') {
        if (post.id != postId) {
          throw const ForumFailure('BOG 返回了其他主串', code: 'parse');
        }
        root = post;
      }
      if (kind != 'thread' || !isRoot || page == 0) posts[post.id] = post;
    }
    if (kind == 'thread' && root == null) {
      throw const ForumFailure('BOG 未返回主串', code: 'parse');
    }
    return PostPage(
      posts.values.toList(),
      -1,
      root: root,
      hasMore: more,
      nextPage: more ? '${page + 1}' : null,
    );
  }
}
