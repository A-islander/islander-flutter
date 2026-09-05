import 'package:dio/dio.dart';
import '../constants/api_constants.dart';

class DioClient {
  late final Dio _forumDio;
  late final Dio _userDio;
  String? _token;
  void Function()? onUnauthorized;

  static bool authenticationFailed(dynamic data) {
    if (data is! Map) return false;
    if (data['code'] == 401) return true;
    final message = '${data['msg'] ?? ''}'.toLowerCase();
    return data['code'] == 403 &&
        (message.contains('token') ||
            message.contains('authorization') ||
            message.contains('record not found'));
  }

  DioClient({Dio? forumDio, Dio? userDio}) {
    _forumDio =
        forumDio ??
        Dio(
          BaseOptions(
            baseUrl: ApiConstants.forumBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

    _userDio =
        userDio ??
        Dio(
          BaseOptions(
            baseUrl: ApiConstants.userBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

    _setupInterceptors(_forumDio);
    _setupInterceptors(_userDio);
  }

  void _setupInterceptors(Dio dio) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.extra['verifyToken'] != true &&
              _token != null &&
              _token!.isNotEmpty) {
            options.headers['Authorization'] = _token;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          final data = response.data;
          if (response.requestOptions.extra['verifyToken'] != true &&
              authenticationFailed(data)) {
            onUnauthorized?.call();
          }
          handler.next(response);
        },
        onError: (error, handler) {
          if (error.requestOptions.extra['verifyToken'] != true &&
              (error.response?.statusCode == 401 ||
                  error.response?.statusCode == 403)) {
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;
  void dispose() {
    _forumDio.close();
    _userDio.close();
  }

  // Forum API methods
  Future<Response> getPlates() => _forumDio.get(ApiConstants.plateGet);
  Future<Response> getPost(int postId) =>
      _forumDio.get(ApiConstants.forumGet, queryParameters: {'postId': postId});
  Future<Response> getForumIndex({
    required int plateId,
    required int page,
    int size = ApiConstants.pageSize,
  }) => _forumDio.get(
    ApiConstants.forumIndex,
    queryParameters: {'plateId': plateId, 'page': page, 'size': size},
  );
  Future<Response> getIndexLast({
    required int page,
    int size = ApiConstants.pageSize,
  }) => _forumDio.get(
    ApiConstants.forumIndexLast,
    queryParameters: {'page': page, 'size': size},
  );
  Future<Response> getForumList({
    required int postId,
    required int page,
    int size = ApiConstants.pageSize,
  }) => _forumDio.get(
    ApiConstants.forumList,
    queryParameters: {'postId': postId, 'page': page, 'size': size},
  );
  Future<Response> getForumListCount(int postId) => _forumDio.get(
    ApiConstants.forumListCount,
    queryParameters: {'postId': postId},
  );
  Future<Response> getUserList({
    required int page,
    int size = ApiConstants.pageSize,
  }) => _forumDio.get(
    ApiConstants.forumUserList,
    queryParameters: {'page': page, 'size': size},
  );
  Future<Response> createPost({
    required String title,
    required String value,
    required int plateId,
    String mediaUrl = '',
  }) => _forumDio.post(
    ApiConstants.forumPost,
    data: {
      'title': title,
      'value': value,
      'plateId': plateId,
      'replyArr': [],
      'mediaUrl': mediaUrl,
    },
  );
  Future<Response> replyPost({
    required String value,
    required int followId,
    String mediaUrl = '',
  }) => _forumDio.post(
    ApiConstants.forumReply,
    data: {
      'value': value,
      'followId': followId,
      'replyArr': [],
      'mediaUrl': mediaUrl,
    },
  );
  Future<Response> sageAdd(int postId) =>
      _forumDio.get('${ApiConstants.forumSageAdd}?postId=$postId');
  Future<Response> sageSub(int postId) =>
      _forumDio.get('${ApiConstants.forumSageSub}?postId=$postId');
  Future<Response> getSageList({
    required int page,
    int size = ApiConstants.pageSize,
  }) => _forumDio.get(
    ApiConstants.forumSageList,
    queryParameters: {'page': page, 'size': size},
  );
  Future<Response> deleteOwnPost(int postId) =>
      _forumDio.get('${ApiConstants.forumDeleteOwnPost}?postId=$postId');
  Future<Response> recoverOwnPost(int postId) =>
      _forumDio.get('${ApiConstants.forumRecoverOwnPost}?postId=$postId');
  Future<Response> getImgToken() => _forumDio.get(ApiConstants.imgToken);
  Future<Response> uploadImage(String filePath) {
    return _forumDio.post(
      ApiConstants.imgUpload,
      data: FormData.fromMap({'file': MultipartFile.fromFileSync(filePath)}),
    );
  }

  // User API methods
  Future<Response> register() => _userDio.get(ApiConstants.userRegister);
  Future<Response> getUserInfo() => _userDio.get(ApiConstants.userGet);

  // Raw Dio instances for custom requests
  Dio get forumDio => _forumDio;
  Dio get userDio => _userDio;
}
