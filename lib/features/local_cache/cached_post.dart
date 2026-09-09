import 'dart:convert';
import '../plate/models/post_model.dart';
import '../forum/domain/forum_site.dart';

/// No credentials or nested reply blobs. Every loaded reply is its own row.
Map<String, Object?> cachePostJson(Post p) => {
  'id': p.id,
  'followId': p.followId,
  'plateId': p.plateId,
  'status': p.status,
  'userId': p.userId,
  'time': p.time,
  'replyCount': p.replyCount,
  'topStatus': p.topStatus,
  'lastReplyTime': p.lastReplyTime,
  'title': p.title,
  'value': p.value,
  'mediaUrl': p.mediaUrl,
  'name': p.name,
  'replyArr': p.replyArr,
  'sageAddId': p.sageAddId,
  'sageSubId': p.sageSubId,
  'sageAddCount': p.sageAddCount,
  'sageSubCount': p.sageSubCount,
  'sageAddUser': p.sageAddUser,
  'sageSubUser': p.sageSubUser,
  'sourceId': p.sourceId,
  'boardKey': p.boardKey,
  'parentUnknown': p.parentUnknown,
  'authorId': p.authorId,
};

Post cachePostFromJson(Map<String, dynamic> j, ForumSite site) {
  final p = Post.fromJson(j);
  return Post(
    fromCache: true,
    id: p.id,
    source: site,
    sourceId: j['sourceId'] as String?,
    boardKey: j['boardKey'] as String?,
    parentUnknown: j['parentUnknown'] == true,
    authorId: j['authorId'] as String? ?? '',
    followId: p.followId,
    plateId: p.plateId,
    status: p.status,
    userId: p.userId,
    time: p.time,
    replyCount: p.replyCount,
    topStatus: p.topStatus,
    lastReplyTime: p.lastReplyTime,
    title: p.title,
    value: p.value,
    mediaUrl: p.mediaUrl,
    name: p.name,
    replyArr: p.replyArr,
    sageAddId: p.sageAddId,
    sageSubId: p.sageSubId,
    sageAddCount: p.sageAddCount,
    sageSubCount: p.sageSubCount,
    sageAddUser: p.sageAddUser,
    sageSubUser: p.sageSubUser,
  );
}

class CachedPost {
  factory CachedPost.snapshot(Post post) => CachedPost({
    'rowid': 0,
    'site': post.site.id,
    'identity': 'anonymous',
    'pinned': 0,
    'accessed': DateTime.now().microsecondsSinceEpoch,
    'page': null,
    'thread_id': post.parentUnknown
        ? null
        : (post.isRoot ? post.id : post.followId),
    'payload': jsonEncode(cachePostJson(post)),
  });
  CachedPost(Map<String, Object?> row)
    : rowId = row['rowid'] as int,
      site = ForumSite.byId(row['site'] as String),
      identity = row['identity'] as String,
      pinned = row['pinned'] == 1,
      accessed = row['accessed'] as int,
      browsedAt = row['browsed_at'] as int?,
      page = row['page'] as int?,
      threadId = row['thread_id'] as int?,
      payload = row['payload'] as String;
  final int rowId, accessed;
  final ForumSite site;
  final String identity, payload;
  final bool pinned;
  final int? page, threadId, browsedAt;
  int get displayTime => browsedAt ?? accessed;
  late final Post post = cachePostFromJson(
    Map<String, dynamic>.from(jsonDecode(payload) as Map),
    site,
  );
  String get route {
    final target = threadId ?? post.id;
    final query = threadId == null
        ? 'localOnly=1'
        : 'focus=${post.id}&page=${page ?? 0}';
    return '${site.route('/post/$target')}?$query';
  }
}
