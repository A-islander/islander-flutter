import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../core/utils/date_format.dart' as dates;
import '../../main.dart';
import '../../shared/widgets/media_item.dart';
import '../../shared/widgets/rich_post_text.dart';
import '../plate/models/post_model.dart';
import 'cookie_sheet.dart';
import 'forum_repository.dart';
import 'forum_theme.dart';

class ForumPostView extends ConsumerStatefulWidget {
  const ForumPostView({
    super.key,
    required this.post,
    required this.boardName,
    this.preview = false,
    this.showDeletionStatus = false,
    this.onOpen,
    this.onReply,
    this.onChanged,
    this.highlighted = false,
    this.depth = 0,
  });
  final Post post;
  final String boardName;
  final bool preview;
  final bool showDeletionStatus;
  final bool highlighted;
  final VoidCallback? onOpen;
  final ValueChanged<int>? onReply;
  final VoidCallback? onChanged;
  final int depth;
  @override
  ConsumerState<ForumPostView> createState() => _ForumPostViewState();
}

class _ForumPostViewState extends ConsumerState<ForumPostView> {
  final _quotes = <int, Future<Post>>{};
  bool _busy = false;
  late Post _post = widget.post;
  @override
  void didUpdateWidget(covariant ForumPostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) _post = widget.post;
  }

  void _quote(int id) {
    if (widget.depth >= 3) {
      context.push('/post/$id');
      return;
    }
    setState(() {
      if (_quotes.containsKey(id)) {
        _quotes.remove(id);
      } else {
        _quotes[id] = ref.read(forumRepositoryProvider).post(id);
      }
    });
  }

  Future<void> _action(String action) async {
    if (_busy) return;
    final actionToken = ref.read(authProvider).token;
    if (!ref.read(authProvider).isLoggedIn) {
      await forumSheet(context, CookieSheet());
      return;
    }
    if (action == 'delete' || action == 'recover') {
      final recovering = action == 'recover';
      final kind = _post.followId == 0 ? '串' : '回复';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text('${recovering ? '恢复' : '删除'} No.${_post.id}？'),
          content: recovering
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('恢复后，这条$kind将重新对其他岛民可见。确认恢复吗？'),
                    if (_post.title.isNotEmpty || _post.value.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _post.title.isNotEmpty ? _post.title : _post.value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ForumPalette.of(context).muted),
                      ),
                    ],
                  ],
                )
              : Text('可以在“我的内容”中恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(recovering ? '恢复' : '删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (ref.read(authProvider).token != actionToken) return;
    setState(() => _busy = true);
    final repo = ref.read(forumRepositoryProvider);
    try {
      if (action == 'delete' || action == 'recover') {
        await repo.changeVisibility(
          _post.id,
          recover: action == 'recover',
          expectedToken: actionToken,
        );
        if (mounted && ref.read(authProvider).token == actionToken) {
          widget.onChanged?.call();
        }
      } else {
        await repo.vote(_post.id, action == 'sage', expectedToken: actionToken);
        if (!mounted || ref.read(authProvider).token != actionToken) return;
        final updated = await repo.post(_post.id);
        if (mounted && ref.read(authProvider).token == actionToken) {
          setState(() => _post = updated);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _actions(Post post, int userId) {
    final palette = ForumPalette.of(context);
    PopupMenuItem<String> item(
      String value,
      String label,
      IconData icon, {
      bool selected = false,
      bool destructive = false,
    }) {
      final color = destructive
          ? Theme.of(context).colorScheme.error
          : selected
          ? palette.accent
          : palette.ink;
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(color: color)),
            ),
            if (selected) Icon(Icons.check, size: 18, color: palette.accent),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<String>(
        key: ValueKey('post-actions-${post.id}'),
        tooltip: '更多操作 · No.${post.id}',
        enabled: !_busy,
        constraints: BoxConstraints(minWidth: 220, maxWidth: 260),
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.line),
        ),
        onSelected: (action) {
          if (action == 'reply') {
            widget.onReply?.call(post.id);
          } else {
            _action(action);
          }
        },
        itemBuilder: (_) => [
          if (!widget.preview) ...[
            if (widget.onReply != null)
              item('reply', '引用回复', Icons.reply_outlined),
            item(
              'sage',
              'SAGE ${post.sageAddCount}',
              Icons.arrow_downward_rounded,
              selected: userId > 0 && post.sageAddId.contains(userId),
            ),
            item(
              'unsage',
              '反对 SAGE ${post.sageSubCount}',
              Icons.arrow_upward_rounded,
              selected: userId > 0 && post.sageSubId.contains(userId),
            ),
          ],
          if (userId > 0 && userId == post.userId) ...[
            if (!widget.preview) PopupMenuDivider(),
            item(
              post.isDeleted ? 'recover' : 'delete',
              post.isDeleted ? '恢复内容' : '删除内容',
              post.isDeleted ? Icons.restore_rounded : Icons.delete_outline,
              destructive: !post.isDeleted,
            ),
          ],
        ],
        icon: _busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.more_horiz, color: palette.muted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final userId = ref.watch(authProvider).userId;
    if (p.isDeleted && (userId <= 0 || userId != p.userId)) {
      return Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No.${p.id} · 该内容已删除',
          style: TextStyle(color: ForumPalette.of(context).muted),
        ),
      );
    }
    final horizontal = widget.depth > 0
        ? 12.0
        : MediaQuery.sizeOf(context).width < 600
        ? 20.0
        : 36.0;
    final media = MediaItem.parseMediaUrl(p.mediaUrl);
    return Material(
      color: widget.highlighted
          ? ForumPalette.of(context).soft
          : ForumPalette.of(context).surface,
      child: InkWell(
        onTap: widget.preview ? widget.onOpen : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: widget.depth > 0 ? 14 : 24,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ForumPalette.of(context).line),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (widget.boardName.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            color: ForumPalette.of(context).soft,
                            child: Text(
                              widget.boardName,
                              style: TextStyle(
                                fontSize: 10,
                                color: ForumPalette.of(context).accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Text(
                          p.name.isEmpty ? '匿名岛民' : p.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          dates.DateUtils.formatTimestamp(p.time),
                          style: TextStyle(
                            fontSize: 10,
                            color: ForumPalette.of(context).muted,
                          ),
                        ),
                        if (p.topStatus != 0)
                          Text(
                            '置顶',
                            style: TextStyle(
                              color: ForumPalette.of(context).accent,
                              fontSize: 11,
                            ),
                          ),
                        if (p.isSaged)
                          Text(
                            'SAGE',
                            style: TextStyle(
                              color: ForumPalette.of(context).muted,
                              fontSize: 11,
                            ),
                          ),
                        if (widget.showDeletionStatus)
                          Container(
                            key: ValueKey('post-deletion-status-${p.id}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: p.isDeleted
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : ForumPalette.of(context).soft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              p.isDeleted ? '已删除' : '未删除',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: p.isDeleted
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer
                                    : ForumPalette.of(context).accent,
                              ),
                            ),
                          )
                        else if (p.isDeleted)
                          Text(
                            '已删除',
                            style: TextStyle(
                              color: ForumPalette.of(context).muted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.preview
                        ? widget.onOpen
                        : () => widget.onReply?.call(p.id),
                    style: TextButton.styleFrom(
                      minimumSize: Size(48, 36),
                      padding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      'No.${p.id}',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              if (p.title.isNotEmpty) ...[
                SizedBox(height: 10),
                Text(
                  p.title,
                  maxLines: widget.preview ? 2 : null,
                  overflow: widget.preview ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    fontSize: widget.depth > 0 ? 16 : 20,
                    height: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              SizedBox(height: 8),
              if (widget.preview)
                Text(
                  p.value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.8,
                    color: ForumPalette.of(context).muted,
                  ),
                )
              else
                RichPostText(
                  text: p.value,
                  onQuote: _quote,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.85,
                    color: ForumPalette.of(context).ink,
                  ),
                ),
              if (media.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: media
                        .take(widget.preview ? 3 : 5)
                        .map((m) => _MediaPreview(item: m))
                        .toList(),
                  ),
                ),
              if (widget.preview) ...[
                SizedBox(height: 16),
                Text(
                  '${p.replyCount} 个回复${p.sageAddCount > 0 ? '     SAGE ${p.sageAddCount}' : ''}',
                  style: TextStyle(
                    color: ForumPalette.of(context).muted,
                    fontSize: 11,
                  ),
                ),
                if (p.lastReplyArr.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Container(
                      padding: EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: ForumPalette.of(context).line,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: p.lastReplyArr
                            .take(5)
                            .map(
                              (reply) => InkWell(
                                onTap: () => context.push('/post/${reply.id}'),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 5),
                                  child: Text(
                                    '${reply.name}: ${reply.value}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: ForumPalette.of(context).muted,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
              ],
              ..._quotes.entries.map(
                (entry) => Container(
                  margin: EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: ForumPalette.of(context).accent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: FutureBuilder<Post>(
                    future: entry.value,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Padding(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No.${entry.key}：${snapshot.error}'),
                              TextButton(
                                onPressed: () => setState(() {
                                  _quotes[entry.key] = ref
                                      .read(forumRepositoryProvider)
                                      .post(entry.key);
                                }),
                                child: Text('重试'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return Padding(
                          padding: EdgeInsets.all(16),
                          child: LinearProgressIndicator(),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton(
                            onPressed: () => context.push('/post/${entry.key}'),
                            child: Text('前往 No.${entry.key} 所在串 →'),
                          ),
                          ForumPostView(
                            post: snapshot.data!,
                            boardName: '',
                            depth: widget.depth + 1,
                            onReply: widget.onReply,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (widget.depth == 0 &&
                  (!widget.preview || (userId > 0 && userId == p.userId))) ...[
                SizedBox(height: 6),
                _actions(p, userId),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.item});
  final MediaItem item;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.all(12),
        child: SizedBox(
          width: 1000,
          height: MediaQuery.sizeOf(context).height * .8,
          child: Stack(
            children: [
              Positioned.fill(
                child: item.type == 'video'
                    ? _VideoViewer(url: item.url)
                    : InteractiveViewer(
                        minScale: .5,
                        maxScale: 5,
                        child: Image.network(
                          item.url,
                          errorBuilder: (_, error, stack) => Center(
                            child: Text(
                              '图片加载失败',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: '关闭媒体',
                  icon: Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    child: SizedBox(
      width: 112,
      height: 84,
      child: item.type == 'video'
          ? ColoredBox(
              color: ForumPalette.of(context).soft,
              child: Icon(
                Icons.play_circle_outline,
                color: ForumPalette.of(context).accent,
                size: 32,
              ),
            )
          : Image.network(
              item.thumbnailUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : ColoredBox(color: ForumPalette.of(context).soft),
              errorBuilder: (_, error, stack) => ColoredBox(
                color: ForumPalette.of(context).soft,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
    ),
  );
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.url});
  final String url;
  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final _controller = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
  );
  late final _ready = _controller.initialize();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text('视频无法播放，请稍后重试', style: TextStyle(color: Colors.white)),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return Center(child: CircularProgressIndicator());
      }
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          VideoProgressIndicator(_controller, allowScrubbing: true),
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, value, _) => IconButton(
              onPressed: () =>
                  value.isPlaying ? _controller.pause() : _controller.play(),
              tooltip: value.isPlaying ? '暂停' : '播放',
              icon: Icon(
                value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    },
  );
}
