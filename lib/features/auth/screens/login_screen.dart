import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../main.dart';
import '../../plate/models/post_model.dart';
import '../../../shared/widgets/post_card.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _tokenController = TextEditingController();
  bool _isLoading = false;
  List<Post> _userPosts = [];
  bool _isLoadingPosts = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    if (auth.isLoggedIn) {
      _tokenController.text = auth.token;
      Future.microtask(() => _fetchUserPosts());
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadNext();
    }
  }

  Future<void> _register() async {
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.register();
      final data = res.data;
      if (data is Map && data['code'] == 200 && data['data'] != null) {
        final token = data['data']['token']?.toString() ?? '';
        if (token.isNotEmpty) {
          await ref.read(authProvider.notifier).setToken(token);
          setState(() => _tokenController.text = token);
          await _fetchUserInfo();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loginWithToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;

    setState(() => _isLoading = true);
    await ref.read(authProvider.notifier).setToken(token);
    await _fetchUserInfo();
    if (mounted) {
      setState(() => _isLoading = false);
      _fetchUserPosts();
    }
  }

  Future<void> _fetchUserInfo() async {
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.getUserInfo();
      final data = res.data;
      if (data is Map && data['code'] == 200 && data['data'] != null) {
        final d = data['data'] as Map;
        final name = d['name']?.toString() ?? '';
        final userId = d['id'] is int ? d['id'] as int : int.tryParse(d['id']?.toString() ?? '') ?? 0;
        await ref.read(authProvider.notifier).setToken(
              ref.read(authProvider).token,
              name: name,
              userId: userId,
            );
      }
    } catch (_) {}
  }

  Future<void> _fetchUserPosts({bool refresh = false}) async {
    if (!ref.read(authProvider).isLoggedIn) return;

    setState(() {
      if (refresh) {
        _userPosts = [];
        _currentPage = 1;
        _hasMore = true;
      }
      _isLoadingPosts = true;
    });

    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.getUserList(page: _currentPage - 1);
      final data = res.data;
      if (data is Map && data['code'] == 200) {
        final rawData = data['data'];
        final List<dynamic> rawList;
        if (rawData is Map) {
          rawList = (rawData['list'] as List?) ?? [];
        } else if (rawData is List) {
          rawList = rawData;
        } else {
          rawList = [];
        }
        final newPosts = rawList.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
        setState(() {
          _userPosts = refresh ? newPosts : [..._userPosts, ...newPosts];
          _hasMore = newPosts.length >= 20;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingPosts = false);
  }

  Future<void> _loadNext() async {
    if (!_hasMore || _isLoadingPosts) return;
    _currentPage++;
    await _fetchUserPosts();
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    setState(() {
      _tokenController.clear();
      _userPosts = [];
      _currentPage = 1;
      _hasMore = true;
    });
  }

  void _gotoPost(Post post) {
    final targetId = post.followId != 0 ? post.followId : post.id;
    context.go('/post/$targetId');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('在？看看饼？'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: Stack(
        children: [
          Column(
        children: [
          // Top info section (fixed)
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // User info card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('饼干信息', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        if (auth.isLoggedIn) ...[
                          Text('饼干名: ${auth.name}'),
                          Text('ID: ${auth.userId}'),
                          Text('Token: ${auth.token.substring(0, 8)}...'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: _logout,
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('登出'),
                              ),
                            ],
                          ),
                        ] else ...[
                          const Text('未登录'),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _register,
                            child: _isLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('注册获取饼干'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Token input
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('饼干管理', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _tokenController,
                          decoration: InputDecoration(
                            hintText: '输入Token',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                if (auth.isLoggedIn) {
                                  Clipboard.setData(ClipboardData(text: auth.token));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制Token')),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _loginWithToken,
                            child: const Text('使用Token登录'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Post list header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('发帖历史', style: theme.textTheme.titleSmall),
            ),
          ),

          // Post list (scrollable)
          Expanded(
            child: auth.isLoggedIn
                ? _userPosts.isEmpty && !_isLoadingPosts
                    ? const Center(child: Text('暂无发帖记录'))
                    : RefreshIndicator(
                        onRefresh: () => _fetchUserPosts(refresh: true),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _userPosts.length + (_isLoadingPosts ? 1 : 0),
                          itemBuilder: (_, index) {
                            if (index >= _userPosts.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            final post = _userPosts[index];
                            return InkWell(
                              onTap: () => _gotoPost(post),
                              child: PostCard(
                                post: post,
                                currentUserId: auth.isLoggedIn ? auth.userId : null,
                              ),
                            );
                          },
                        ),
                      )
                : const Center(child: Text('请先登录查看发帖历史')),
          ),
        ],
      ),
        ],
      ),
    );
  }
}
