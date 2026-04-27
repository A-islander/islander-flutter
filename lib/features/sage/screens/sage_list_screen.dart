import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../main.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/widgets/post_card.dart';
import '../../plate/models/post_model.dart';

class SageListState {
  final List<Post> posts;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final bool hasMore;

  const SageListState({
    this.posts = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = true,
  });

  SageListState copyWith({
    List<Post>? posts,
    bool? isLoading,
    String? error,
    int? currentPage,
    bool? hasMore,
  }) {
    return SageListState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class SageListNotifier extends StateNotifier<SageListState> {
  final DioClient _dio;

  SageListNotifier(this._dio) : super(const SageListState());

  Future<void> fetchSageList({int page = 1, bool refresh = false}) async {
    if (refresh) {
      state = state.copyWith(posts: [], isLoading: true, error: null, currentPage: 1, hasMore: true);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final res = await _dio.getSageList(page: page - 1);
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
        final list = rawList.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
        state = state.copyWith(
          posts: refresh ? list : [...state.posts, ...list],
          isLoading: false,
          currentPage: page,
          hasMore: list.length >= 20,
        );
      } else {
        state = state.copyWith(isLoading: false, error: data?['msg']?.toString() ?? 'Failed');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadNext() async {
    if (!state.hasMore || state.isLoading) return;
    await fetchSageList(page: state.currentPage + 1);
  }
}

final sageListProvider = StateNotifierProvider<SageListNotifier, SageListState>((ref) {
  return SageListNotifier(ref.watch(dioClientProvider));
});

class SageListScreen extends ConsumerStatefulWidget {
  const SageListScreen({super.key});

  @override
  ConsumerState<SageListScreen> createState() => _SageListScreenState();
}

class _SageListScreenState extends ConsumerState<SageListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sageListProvider.notifier).fetchSageList(refresh: true));
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(sageListProvider.notifier).loadNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sageState = ref.watch(sageListProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('看看你都干了什么？'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: sageState.isLoading && sageState.posts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : sageState.error != null && sageState.posts.isEmpty
              ? Center(child: Text('Error: ${sageState.error}'))
              : RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(sageListProvider.notifier).fetchSageList(refresh: true);
                  },
                  child: sageState.posts.isEmpty
                      ? const Center(child: Text('暂无sage帖子'))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: sageState.posts.length + (sageState.isLoading ? 1 : 0),
                          itemBuilder: (_, index) {
                            if (index >= sageState.posts.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return InkWell(
                              onTap: () => context.go('/post/${sageState.posts[index].id}'),
                              child: PostCard(
                                post: sageState.posts[index],
                                currentUserId: auth.isLoggedIn ? auth.userId : null,
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
