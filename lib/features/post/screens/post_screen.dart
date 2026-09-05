import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../main.dart';
import '../../../shared/widgets/post_card.dart';
import '../../../shared/widgets/media_item.dart';
import '../../../shared/widgets/emoji_picker.dart';
import '../providers/post_provider.dart';

class PostScreen extends ConsumerStatefulWidget {
  final int postId;

  const PostScreen({super.key, required this.postId});

  @override
  ConsumerState<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends ConsumerState<PostScreen> {
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  List<MediaItem> _mediaItems = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(postDetailProvider.notifier).fetchPost(widget.postId);
      ref.read(replyListProvider.notifier).fetchReplies(postId: widget.postId, page: 1, refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(replyListProvider.notifier).loadNext(postId: widget.postId);
    }
  }

  Future<void> _submitReply() async {
    final value = _replyController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('总得说点什么吧')),
      );
      return;
    }

    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.go('/login');
      return;
    }

    final dio = ref.read(dioClientProvider);
    final mediaUrl = _mediaItems.isEmpty
        ? '[]'
        : '[${_mediaItems.map((m) => '{"id":"${m.id}","url":"${m.url}","thumbnailUrl":"${m.thumbnailUrl}","type":"${m.type}"}').join(',')}]';

    try {
      final res = await dio.replyPost(value: value, followId: widget.postId, mediaUrl: mediaUrl);
      if (res.data['code'] == 200) {
        _replyController.clear();
        setState(() => _mediaItems = []);
        // Reload replies to get updated list
        ref.read(replyListProvider.notifier).fetchReplies(postId: widget.postId, page: 1, refresh: true);
        // Also refresh post detail to update replyCount
        ref.read(postDetailProvider.notifier).fetchPost(widget.postId);
      } else if (res.data['code'] == 403) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请领取饼干')),
          );
        }
      } else if (res.data['code'] == 404) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('总得说点什么吧')),
          );
        }
      }
    } catch (_) {}
  }

  void _insertQuote(int postId) {
    final text = 'No.$postId';
    final currentText = _replyController.text;
    final selection = _replyController.selection;
    final newText = currentText.replaceRange(selection.start, selection.end, text);
    _replyController.text = newText;
    final newCursorPos = selection.start + text.length;
    _replyController.selection = TextSelection.collapsed(offset: newCursorPos);
  }

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage();
    for (final img in images) {
      if (_mediaItems.length >= 4) break;
      setState(() {
        _mediaItems.add(MediaItem(id: '', url: img.path, thumbnailUrl: img.path, type: 'image'));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(postDetailProvider);
    final replies = ref.watch(replyListProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('看串中'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: detail.isLoading
          ? const Center(child: CircularProgressIndicator())
          : detail.error != null
              ? Center(child: Text('Error: ${detail.error}'))
              : detail.post == null
                  ? const Center(child: Text('帖子不存在'))
                  : RefreshIndicator(
                      onRefresh: () async {
                        await Future.wait([
                          ref.read(postDetailProvider.notifier).fetchPost(widget.postId),
                          ref.read(replyListProvider.notifier).fetchReplies(postId: widget.postId, page: 1, refresh: true),
                        ]);
                      },
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        children: [
                          PostCard(
                            post: detail.post!,
                            currentUserId: auth.isLoggedIn ? auth.userId : null,
                            onInsertQuote: () => _insertQuote(detail.post!.id),
                          ),
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            child: Text(
                              '回复 (${detail.post!.replyCount})',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (replies.replies.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: Text('暂无回复')),
                            )
                          else
                            ...replies.replies.map((reply) => PostCard(
                                  post: reply,
                                  currentUserId: auth.isLoggedIn ? auth.userId : null,
                                  onInsertQuote: () => _insertQuote(reply.id),
                                )),
                          if (replies.isLoading)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_mediaItems.isNotEmpty)
                SizedBox(
                  height: 60,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: _mediaItems.asMap().entries.map((e) {
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 50, height: 50,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: e.value.type == 'video'
                                    ? const Icon(Icons.videocam, size: 24)
                                    : const Icon(Icons.image, size: 24),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0, right: 4,
                            child: GestureDetector(
                              onTap: () => setState(() => _mediaItems.removeAt(e.key)),
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                    onPressed: () => EmojiPicker.show(context, _replyController),
                  ),
                  IconButton(
                    icon: const Icon(Icons.image_outlined, size: 20),
                    onPressed: _pickImages,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      decoration: InputDecoration(
                        hintText: '说点什么...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitReply(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _submitReply,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
