class ApiConstants {
  static const String forumBaseUrl = String.fromEnvironment(
    'FORUM_API_URL',
    defaultValue: 'https://forum-api.islander.top/',
  );
  static const String userBaseUrl = String.fromEnvironment(
    'USER_API_URL',
    defaultValue: 'https://user-api.islander.top/',
  );

  // Forum API
  static const String plateGet = 'plate/get';
  static const String forumGet = 'forum/get';
  static const String forumIndex = 'forum/index';
  static const String forumIndexLast = 'forum/indexLast';
  static const String forumList = 'forum/list';
  static const String forumListCount = 'forum/listCount';
  static const String forumUserList = 'forum/userList';
  static const String forumPost = 'forum/post';
  static const String forumReply = 'forum/reply';
  static const String forumSageAdd = 'forum/sage/add';
  static const String forumSageSub = 'forum/sage/sub';
  static const String forumSageList = 'forum/sage/list';
  static const String forumDeleteOwnPost = 'forum/delete/ownPost';
  static const String forumRecoverOwnPost = 'forum/recover/ownPost';
  static const String imgToken = 'img/token';
  static const String imgUpload = 'img/upload';

  // User API
  static const String userRegister = 'user/register';
  static const String userGet = 'user/get';

  static const int pageSize = 20;
  static const int maxUploadSize = 20 * 1024 * 1024; // 20MB
}
