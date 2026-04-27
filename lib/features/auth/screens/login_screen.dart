import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../main.dart';
import '../../plate/models/post_model.dart';

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

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    if (auth.isLoggedIn) {
      _tokenController.text = auth.token;
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
          _fetchUserInfo();
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
    if (mounted) setState(() => _isLoading = false);
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

  Future<void> _fetchUserPosts() async {
    setState(() => _isLoadingPosts = true);
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.getUserList(page: 0);
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
        setState(() {
          _userPosts = rawList.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingPosts = false);
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    setState(() {
      _tokenController.clear();
      _userPosts = [];
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
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
      body: SingleChildScrollView(
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
                    Text('当前状态', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (auth.isLoggedIn) ...[
                      Text('用户名: ${auth.name}'),
                      Text('ID: ${auth.userId}'),
                      Text('Token: ${auth.token.substring(0, 8)}...'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _fetchUserPosts,
                            child: const Text('查看发帖历史'),
                          ),
                          const SizedBox(width: 8),
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

            const SizedBox(height: 16),

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

            // User posts
            if (_userPosts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('发帖历史', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._userPosts.map((post) => Card(
                    child: InkWell(
                      onTap: () => context.go('/post/${post.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.value,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No.${post.id}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.secondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],

            if (_isLoadingPosts)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }
}
