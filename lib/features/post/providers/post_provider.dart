import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../main.dart';
import '../../plate/models/post_model.dart';

class PostDetailState {
  final Post? post;
  final bool isLoading;
  final String? error;

  const PostDetailState({this.post, this.isLoading = false, this.error});

  PostDetailState copyWith({Post? post, bool? isLoading, String? error}) {
    return PostDetailState(
      post: post ?? this.post,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PostDetailNotifier extends StateNotifier<PostDetailState> {
  final DioClient _dio;

  PostDetailNotifier(this._dio) : super(const PostDetailState());

  Future<void> fetchPost(int postId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _dio.getPost(postId);
      final data = res.data;
      if (data is Map && data['code'] == 200 && data['data'] != null) {
        state = state.copyWith(post: Post.fromJson(data['data']), isLoading: false);
      } else {
        state = state.copyWith(isLoading: false, error: 'Failed to load post');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void updatePost(Post updatedPost) {
    state = state.copyWith(post: updatedPost);
  }
}

class ReplyListState {
  final List<Post> replies;
  final bool isLoading;
  final String? error;
  final int totalCount;

  const ReplyListState({
    this.replies = const [],
    this.isLoading = false,
    this.error,
    this.totalCount = 0,
  });

  ReplyListState copyWith({
    List<Post>? replies,
    bool? isLoading,
    String? error,
    int? totalCount,
  }) {
    return ReplyListState(
      replies: replies ?? this.replies,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}

class ReplyListNotifier extends StateNotifier<ReplyListState> {
  final DioClient _dio;
  int _currentPage = 1;
  bool _hasMore = true;

  ReplyListNotifier(this._dio) : super(const ReplyListState());

  bool get hasMore => _hasMore;

  Future<void> fetchReplies({required int postId, required int page, bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      state = state.copyWith(replies: [], isLoading: true, error: null);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final res = await _dio.getForumList(postId: postId, page: page);
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
        _currentPage = page;
        _hasMore = list.length >= 20;
        state = state.copyWith(
          replies: refresh ? list : [...state.replies, ...list],
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false, error: data?['msg']?.toString() ?? 'Failed');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadNext({required int postId}) async {
    if (!_hasMore || state.isLoading) return;
    await fetchReplies(postId: postId, page: _currentPage + 1);
  }

  void addReply(Post reply) {
    state = state.copyWith(replies: [...state.replies, reply], totalCount: state.totalCount + 1);
  }
}

final postDetailProvider =
    StateNotifierProvider<PostDetailNotifier, PostDetailState>((ref) {
  return PostDetailNotifier(ref.watch(dioClientProvider));
});

final replyListProvider =
    StateNotifierProvider<ReplyListNotifier, ReplyListState>((ref) {
  return ReplyListNotifier(ref.watch(dioClientProvider));
});
