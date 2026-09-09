import 'dart:async';
import 'package:flutter/material.dart';
import 'forum_preview_text.dart';
import 'image_viewer.dart';
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
import '../local_cache/cache_providers.dart';
import '../local_cache/cache_widgets.dart';
import '../local_cache/cache_backup.dart';
import '../local_cache/cached_post.dart';

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
    this.ancestors = const {},
    this.threadRoot,
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
  final Set<PostKey> ancestors;
  final Post? threadRoot;
  @override
  ConsumerState<ForumPostView> createState() => _ForumPostViewState();
}

class _ForumPostViewState extends ConsumerState<ForumPostView> {
  final _quotes = <int, Future<Post>>{};
  final _quoteRoots = <PostKey, Future<Post>>{};
  Timer? _previewTimer;
  int _previewGeneration = 0;
  List<Post>? _hoverReplies;
  bool _previewBusy = false;
  bool _busy = false;
  late Post _post = widget.post;

  Widget _quotedPost(Post quoted) {
    Widget view(Post? root) => ForumPostView(
      post: quoted,
      threadRoot: root,
      boardName: '',
      depth: widget.depth + 1,
      ancestors: {...widget.ancestors, _post.key},
      onReply: widget.onReply,
    );
    if (quoted.isRoot || quoted.parentUnknown) {
      return view(quoted.isRoot ? quoted : null);
    }
    final root = _post.isRoot ? _post : widget.threadRoot;
    if (root != null &&
        quoted.followId == root.id &&
        quoted.site.instanceKey == root.site.instanceKey) {
      return view(root);
    }
    final key = PostKey(quoted.site.instanceKey, '${quoted.followId}');
    return FutureBuilder<Post>(
      future: _quoteRoots.putIfAbsent(
        key,
        () => ref.read(cachedForumRepositoryProvider).thread(quoted.followId),
      ),
      builder: (_, snapshot) => view(snapshot.data),
    );
  }

  @override
  void didUpdateWidget(covariant ForumPostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      _post = widget.post;
      _previewTimer?.cancel();
      _previewGeneration++;
      _previewBusy = false;
      _hoverReplies = null;
      if (oldWidget.post.key != widget.post.key) {
        _quotes.clear();
        _quoteRoots.clear();
      }
    }
  }

  void _preview() {
    if (!widget.preview ||
        MediaQuery.sizeOf(context).width < 1024 ||
        _hoverReplies != null ||
        _previewBusy ||
        _post.lastReplyArr.length >= 5 ||
        _post.replyCount <= _post.lastReplyArr.length) {
      return;
    }
    final generation = ++_previewGeneration;
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted || generation != _previewGeneration) return;
      _previewBusy = true;
      final repo = ref.read(cachedForumRepositoryProvider);
      final identity = ref.read(authProvider).token;
      try {
        final page = await repo.page(kind: 'thread', postId: _post.id);
        if (!mounted ||
            generation != _previewGeneration ||
            repo.site.isIslander && identity != ref.read(authProvider).token) {
          return;
        }
        setState(
          () => _hoverReplies = page.posts
              .where((p) => p.id != _post.id)
              .take(5)
              .toList(),
        );
      } catch (_) {
        // A preview failure never replaces the readable row or writes history.
      } finally {
        if (mounted && generation == _previewGeneration) _previewBusy = false;
      }
    });
  }

  void _leavePreview() {
    _previewTimer?.cancel();
    _previewGeneration++;
    _previewBusy = false;
  }

  @override
  void dispose() {
    _leavePreview();
    super.dispose();
  }

  void _quote(int id) {
    final target = PostKey(_post.site.instanceKey, '$id');
    if (widget.depth >= 3 ||
        target == _post.key ||
        widget.ancestors.contains(target)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已到引用层级上限或遇到循环引用')));
      return;
    }
    setState(() {
      if (_quotes.containsKey(id)) {
        _quotes.remove(id);
      } else {
        _quotes[id] = ref.read(cachedForumRepositoryProvider).post(id);
      }
    });
  }

  Future<void> _action(String action) async {
    if (!ref.read(forumRepositoryProvider).capabilities.manage &&
        !ref.read(forumRepositoryProvider).capabilities.sage) {
      return;
    }
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

  Future<void> _cacheAction(String action) async {
    final post = _post;
    final store = ref.read(cacheStoreProvider);
    final identity = ref.read(cacheIdentityProvider(post.site));
    setState(() => _busy = true);
    try {
      var row = await store.find(post.site, identity, post.id);
      if (!mounted) return;
      if (action == 'cache-delete') {
        if (row == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('这条内容未保存在本地')));
          return;
        }
        if (!await confirmCacheAction(
          context,
          '删除 No.${post.id} 的本地缓存？',
          '仅删除本机正文和对应浏览记录，不删除服务器帖子或阅读位置。${row.pinned ? '这条内容已永久保留，本次也会删除。' : ''}',
        )) {
          return;
        }
        if (!mounted ||
            identity != ref.read(cacheIdentityProvider(post.site))) {
          return;
        }
        await store.remove(ids: [row.rowId], includePinned: true);
      } else if (action == 'cache-unpin') {
        if (row != null) await store.pin([row.rowId], false);
      } else {
        if (identity != ref.read(cacheIdentityProvider(post.site))) return;
        if (action == 'cache-pin') {
          await store.capture(
            post.site,
            identity,
            [post],
            force: true,
            pin: true,
          );
          row = await store.find(post.site, identity, post.id);
        }
        if (action == 'cache-export') {
          final message = await saveCacheBackup([
            row ?? CachedPost.snapshot(post),
          ]);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (action) {
              'cache-pin' => '已永久保留；不会被自动清理',
              'cache-unpin' => '已取消永久保留',
              _ => '已删除本地缓存；再次联网加载可能重新保存',
            }),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message : '本地缓存操作失败，请重试',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _actions(Post post, int userId) {
    final capabilities = ref.read(forumRepositoryProvider).capabilities;
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
          } else if (action.startsWith('cache-')) {
            _cacheAction(action);
          } else {
            _action(action);
          }
        },
        itemBuilder: (_) => [
          item('cache-pin', '永久保留', Icons.bookmark_add_outlined),
          item('cache-unpin', '取消永久保留', Icons.bookmark_remove_outlined),
          item('cache-export', '导出这条内容', Icons.file_upload_outlined),
          item('cache-delete', '删除这条本地缓存', Icons.delete_sweep_outlined),
          if (!widget.preview) ...[
            if (widget.onReply != null)
              item('reply', '引用回复', Icons.reply_outlined),
            if (capabilities.sage)
              item(
                'sage',
                'SAGE ${post.sageAddCount}',
                Icons.arrow_downward_rounded,
                selected: userId > 0 && post.sageAddId.contains(userId),
              ),
            if (capabilities.sage)
              item(
                'unsage',
                '反对 SAGE ${post.sageSubCount}',
                Icons.arrow_upward_rounded,
                selected: userId > 0 && post.sageSubId.contains(userId),
              ),
          ],
          if (capabilities.manage && userId > 0 && userId == post.userId) ...[
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
    final userId = p.site.isIslander ? ref.watch(authProvider).userId : 0;
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
    final replies = _hoverReplies ?? p.lastReplyArr;
    return MouseRegion(
      onEnter: (_) => _preview(),
      onExit: (_) => _leavePreview(),
      child: Material(
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
                          if (p.isOriginalPosterOf(
                            p.isRoot ? p : widget.threadRoot,
                          ))
                            _PoBadge(postId: p.id),
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
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.errorContainer
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
                    widget.preview ? forumPreviewText(p.title) : p.title,
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
                    forumPreviewText(p.value),
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
                          .indexed
                          .map(
                            (entry) => _MediaPreview(
                              item: entry.$2,
                              site: p.site.id,
                              postId: p.id,
                              index: entry.$1 + 1,
                            ),
                          )
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
                  if (replies.isNotEmpty)
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
                          children: replies
                              .take(5)
                              .map(
                                (reply) => InkWell(
                                  onTap: () => context.push(
                                    p.site.route(
                                      '/post/${p.site.isIslander ? reply.id : p.id}',
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 5),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          if (reply.isOriginalPosterOf(p))
                                            TextSpan(
                                              text: 'PO ',
                                              style: TextStyle(
                                                color: ForumPalette.of(
                                                  context,
                                                ).accent,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          TextSpan(
                                            text: forumPreviewText(
                                              '${reply.name}: ${reply.value}',
                                            ),
                                          ),
                                        ],
                                      ),
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
                                        .read(cachedForumRepositoryProvider)
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
                            if (!snapshot.data!.parentUnknown)
                              TextButton(
                                onPressed: () => context.push(
                                  _post.site.route(
                                    '/post/${snapshot.data!.followId == 0 ? entry.key : snapshot.data!.followId}',
                                  ),
                                ),
                                child: Text('前往 No.${entry.key} 所在串 →'),
                              ),
                            _quotedPost(snapshot.data!),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (widget.depth == 0 &&
                    (!widget.preview ||
                        (userId > 0 && userId == p.userId))) ...[
                  SizedBox(height: 6),
                  _actions(p, userId),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PoBadge extends StatelessWidget {
  const _PoBadge({required this.postId});
  final int postId;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '串主',
    child: Container(
      key: ValueKey('post-po-$postId'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: ForumPalette.of(context).soft,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'PO',
        style: TextStyle(
          color: ForumPalette.of(context).accent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.item,
    required this.site,
    required this.postId,
    required this.index,
  });
  final MediaItem item;
  final String site;
  final int postId, index;
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
                    : ForumImageViewer(
                        item: item,
                        site: site,
                        postId: postId,
                        index: index,
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
