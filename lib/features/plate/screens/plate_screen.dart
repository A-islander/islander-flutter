import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../main.dart';
import '../../../shared/widgets/post_card.dart';
import '../../../shared/widgets/media_upload.dart';
import '../../../shared/widgets/media_item.dart';
import '../../../shared/widgets/emoji_picker.dart';
import '../providers/plate_provider.dart';
import '../models/post_model.dart';

class PlateScreen extends ConsumerStatefulWidget {
  final int plateId;

  const PlateScreen({super.key, required this.plateId});

  @override
  ConsumerState<PlateScreen> createState() => _PlateScreenState();
}

class _PlateScreenState extends ConsumerState<PlateScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _scrollController = ScrollController();
  List<MediaItem> _mediaItems = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(plateProvider.notifier).fetchPlates());
    Future.microtask(() {
      ref.read(postListProvider.notifier).fetchPosts(plateId: widget.plateId, page: 1, refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(postListProvider.notifier).loadNext(plateId: widget.plateId);
    }
  }

  Future<void> _createPost() async {
    final value = _contentController.text.trim();
    if (value.isEmpty) return;

    final dio = ref.read(dioClientProvider);
    final mediaUrl = _mediaItems.isEmpty
        ? ''
        : '[${_mediaItems.map((m) => '{"id":"${m.id}","url":"${m.url}","thumbnailUrl":"${m.thumbnailUrl}","type":"${m.type}"}').join(',')}]';

    try {
      final res = await dio.createPost(
        title: _titleController.text.trim(),
        value: value,
        plateId: widget.plateId,
        mediaUrl: mediaUrl,
      );
      if (res.data['code'] == 200 && res.data['data'] != null) {
        final newPost = Post.fromJson(res.data['data']);
        ref.read(postListProvider.notifier).addPost(newPost);
        _titleController.clear();
        _contentController.clear();
        setState(() => _mediaItems = []);
        Navigator.pop(context);
      }
    } catch (_) {}
  }

  void _showCreateDialog() {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.go('/login');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text('发布新串', style: Theme.of(context).textTheme.titleMedium),
                        ElevatedButton(
                          onPressed: _createPost,
                          child: const Text('发布'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(hintText: '标题（可选）'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contentController,
                      maxLines: 5,
                      decoration: const InputDecoration(hintText: '内容'),
                    ),
                    const SizedBox(height: 8),
                    MediaUploadWidget(
                      mediaItems: _mediaItems,
                      onChanged: (items) => setState(() => _mediaItems = items),
                    ),
                    TextButton.icon(
                      onPressed: () => EmojiPicker.show(context, _contentController),
                      icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                      label: const Text('颜文字'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plateState = ref.watch(plateProvider);
    final postState = ref.watch(postListProvider);
    final auth = ref.watch(authProvider);
    final plateName = widget.plateId == 0
        ? '时间线'
        : ref.read(plateProvider.notifier).getPlateName(widget.plateId);

    return Scaffold(
      appBar: AppBar(
        title: Text(plateName),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: plateState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : plateState.error != null && postState.posts.isEmpty
              ? Center(child: Text('Error: ${plateState.error}'))
              : RefreshIndicator(
                  onRefresh: () async {
                    await ref
                        .read(postListProvider.notifier)
                        .fetchPosts(plateId: widget.plateId, page: 1, refresh: true);
                  },
                  child: postState.posts.isEmpty
                      ? const Center(child: Text('暂无帖子'))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: postState.posts.length + (postState.isLoading ? 1 : 0),
                          itemBuilder: (_, index) {
                            if (index >= postState.posts.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return InkWell(
                              onTap: () => context.go('/post/${postState.posts[index].id}'),
                              child: PostCard(
                                post: postState.posts[index],
                                currentUserId: auth.isLoggedIn ? auth.userId : null,
                              ),
                            );
                          },
                        ),
                ),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        onPressed: _showCreateDialog,
        child: const Icon(Icons.edit),
      ),
    );
  }
}
