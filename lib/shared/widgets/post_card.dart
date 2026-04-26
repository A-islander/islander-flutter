import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/plate/models/post_model.dart';
import '../../../main.dart';
import 'media_item.dart';
import 'post_card_header.dart';
import 'rich_post_text.dart';

const int _maxRecursionDepth = 3;

class PostCard extends ConsumerStatefulWidget {
  final Post post;
  final int? currentUserId;
  final int depth;
  final Function(int postId)? onQuoteTap;

  const PostCard({
    super.key,
    required this.post,
    this.currentUserId,
    this.depth = 0,
    this.onQuoteTap,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  final Map<int, Post> _expandedQuotes = {};
  bool _sageAddVoted = false;
  bool _sageSubVoted = false;
  int _localSageAddCount = 0;
  int _localSageSubCount = 0;

  @override
  void initState() {
    super.initState();
    _localSageAddCount = widget.post.sageAddCount;
    _localSageSubCount = widget.post.sageSubCount;
    _sageAddVoted = widget.currentUserId != null &&
        widget.post.sageAddId.contains(widget.currentUserId);
    _sageSubVoted = widget.currentUserId != null &&
        widget.post.sageSubId.contains(widget.currentUserId);
  }

  List<MediaItem> get _mediaItems => MediaItem.parseMediaUrl(widget.post.mediaUrl);

  bool get _canDelete =>
      widget.currentUserId != null &&
      widget.currentUserId == widget.post.userId &&
      widget.post.status == 0;

  bool get _canRecover =>
      widget.currentUserId != null &&
      widget.currentUserId == widget.post.userId &&
      widget.post.status == 2;

  Future<void> _sageAdd() async {
    final dio = ref.read(dioClientProvider);
    final result = await dio.sageAdd(widget.post.id);
    if (result.data['data'] == true) {
      setState(() {
        _localSageAddCount++;
        if (_sageSubVoted) { _localSageSubCount--; _sageSubVoted = false; }
        _sageAddVoted = true;
      });
    } else if (result.data['data'] == false) {
      setState(() {
        _localSageAddCount--;
        _sageAddVoted = false;
      });
    }
  }

  Future<void> _sageSub() async {
    final dio = ref.read(dioClientProvider);
    final result = await dio.sageSub(widget.post.id);
    if (result.data['data'] == true) {
      setState(() {
        _localSageSubCount++;
        if (_sageAddVoted) { _localSageAddCount--; _sageAddVoted = false; }
        _sageSubVoted = true;
      });
    } else if (result.data['data'] == false) {
      setState(() {
        _localSageSubCount--;
        _sageSubVoted = false;
      });
    }
  }

  Future<void> _deletePost() async {
    final dio = ref.read(dioClientProvider);
    final result = await dio.deleteOwnPost(widget.post.id);
    if (result.data['data']?['status'] == true) {
      setState(() {});
    }
  }

  Future<void> _recoverPost() async {
    final dio = ref.read(dioClientProvider);
    final result = await dio.recoverOwnPost(widget.post.id);
    if (result.data['data']?['status'] == true) {
      setState(() {});
    }
  }

  void _toggleQuote(int postId) {
    setState(() {
      if (_expandedQuotes.containsKey(postId)) {
        _expandedQuotes.remove(postId);
      } else {
        _expandedQuotes[postId] = Post(
          id: postId, name: '...', value: '加载中...',
        );
        _fetchQuotePost(postId);
      }
    });
  }

  Future<void> _fetchQuotePost(int postId) async {
    final dio = ref.read(dioClientProvider);
    try {
      final res = await dio.getPost(postId);
      if (res.data['data'] != null) {
        if (mounted) {
          setState(() {
            _expandedQuotes[postId] = Post.fromJson(res.data['data']);
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isQuoted = widget.depth > 0;

    return Container(
      margin: EdgeInsets.only(
        left: isQuoted ? 12.0 : 0,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: isQuoted
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.primary,
          width: isQuoted ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          PostCardHeader(
            post: widget.post,
            onTapPostNumber: () => context.go('/post/${widget.post.id}'),
          ),
          const Divider(height: 1),

          // Expanded quote posts
          ..._expandedQuotes.entries.map((e) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: PostCard(
              post: e.value,
              currentUserId: widget.currentUserId,
              depth: widget.depth + 1,
              onQuoteTap: widget.depth + 1 < _maxRecursionDepth
                  ? _toggleQuote
                  : null,
            ),
          )),

          // Body
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: RichPostText(text: widget.post.value),
          ),

          // Media
          if (_mediaItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _mediaItems.map((item) {
                  if (item.type == 'video') {
                    return _VideoThumbnail(item: item);
                  }
                  return _ImageThumbnail(item: item);
                }).toList(),
              ),
            ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_canDelete)
                    GestureDetector(
                      onTap: _deletePost,
                      child: Text('删除我的串',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
                    ),
                  if (_canRecover)
                    GestureDetector(
                      onTap: _recoverPost,
                      child: Text('恢复我的串',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
                    ),
                  GestureDetector(
                    onTap: _sageAdd,
                    child: Text(
                      '支持SAGE：$_localSageAddCount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: _sageAddVoted
                            ? theme.colorScheme.primary
                            : theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _sageSub,
                    child: Text(
                      '反对SAGE：$_localSageSubCount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: _sageSubVoted
                            ? theme.colorScheme.primary
                            : theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // lastReplyArr (brief preview)
          if (widget.post.lastReplyArr.isNotEmpty && widget.depth == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.post.lastReplyArr.map((reply) {
                  return GestureDetector(
                    onTap: () => context.go('/post/${reply.id}'),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${reply.name}: ${reply.value}${reply.mediaUrl.isNotEmpty ? ' (查看图片)' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  final MediaItem item;
  const _ImageThumbnail({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullScreen(context, item.url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: item.thumbnailUrl,
          width: 150,
          height: 150,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 150, height: 150,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          errorWidget: (_, __, ___) => Container(
            width: 150, height: 150,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image, size: 32),
          ),
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  final MediaItem item;
  const _VideoThumbnail({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showVideoPlayer(context, item.url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            if (item.thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.thumbnailUrl,
                width: 150, height: 100, fit: BoxFit.cover,
              )
            else
              Container(
                width: 150, height: 100,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoPlayer(BuildContext context, String url) {
    // video_player will be used when implementing full PostScreen
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
