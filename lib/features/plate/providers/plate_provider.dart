import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../main.dart';
import '../models/plate_model.dart';
import '../models/post_model.dart';

class PlateState {
  final List<Plate> plates;
  final bool isLoading;
  final String? error;

  const PlateState({this.plates = const [], this.isLoading = false, this.error});

  PlateState copyWith({List<Plate>? plates, bool? isLoading, String? error}) {
    return PlateState(
      plates: plates ?? this.plates,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PlateNotifier extends StateNotifier<PlateState> {
  final DioClient _dio;

  PlateNotifier(this._dio) : super(const PlateState());

  Future<void> fetchPlates() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _dio.getPlates();
      final data = res.data;
      if (data is Map && data['code'] == 200) {
        final list = (data['data'] as List?)
                ?.map((e) => Plate.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        state = state.copyWith(plates: list, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false, error: data?['msg']?.toString() ?? 'Failed');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  String getPlateName(int id) {
    try {
      return state.plates.firstWhere((p) => p.id == id).name;
    } catch (_) {
      return 'Unknown';
    }
  }
}

class PostListState {
  final List<Post> posts;
  final bool isLoading;
  final String? error;

  const PostListState({this.posts = const [], this.isLoading = false, this.error});

  PostListState copyWith({List<Post>? posts, bool? isLoading, String? error}) {
    return PostListState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PostListNotifier extends StateNotifier<PostListState> {
  final DioClient _dio;
  int _currentPage = 1;
  bool _hasMore = true;

  PostListNotifier(this._dio) : super(const PostListState());

  bool get hasMore => _hasMore;

  Future<void> fetchPosts({required int plateId, required int page, bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      state = state.copyWith(posts: [], isLoading: true, error: null);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final res = plateId == 0
          ? await _dio.getIndexLast(page: page)
          : await _dio.getForumIndex(plateId: plateId, page: page);

      final data = res.data;
      if (data is Map && data['code'] == 200) {
        final list = (data['data'] as List?)
                ?.map((e) => Post.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _currentPage = page;
        _hasMore = list.length >= 20;
        state = state.copyWith(
          posts: refresh ? list : [...state.posts, ...list],
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false, error: data?['msg']?.toString() ?? 'Failed');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadNext({required int plateId}) async {
    if (!_hasMore || state.isLoading) return;
    await fetchPosts(plateId: plateId, page: _currentPage + 1);
  }

  void addPost(Post post) {
    state = state.copyWith(posts: [post, ...state.posts]);
  }
}

final plateProvider = StateNotifierProvider<PlateNotifier, PlateState>((ref) {
  return PlateNotifier(ref.watch(dioClientProvider));
});

final postListProvider = StateNotifierProvider.autoDispose<PostListNotifier, PostListState>((ref) {
  return PostListNotifier(ref.watch(dioClientProvider));
});
