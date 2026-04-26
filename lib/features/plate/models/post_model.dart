import 'dart:convert';

class Post {
  final int id;
  final int followId;
  final int plateId;
  final int status;
  final int userId;
  final int time;
  final int replyCount;
  final int topStatus;
  final int lastReplyTime;
  final String title;
  final String value;
  final String mediaUrl;
  final String name;
  final List<int> replyArr;
  final List<int> sageAddId;
  final List<int> sageSubId;
  final int sageAddCount;
  final int sageSubCount;
  final List<Post> lastReplyArr;
  final List<String> sageAddUser;
  final List<String> sageSubUser;

  const Post({
    required this.id,
    this.followId = 0,
    this.plateId = 0,
    this.status = 0,
    this.userId = 0,
    this.time = 0,
    this.replyCount = 0,
    this.topStatus = 0,
    this.lastReplyTime = 0,
    this.title = '',
    this.value = '',
    this.mediaUrl = '',
    this.name = '',
    this.replyArr = const [],
    this.sageAddId = const [],
    this.sageSubId = const [],
    this.sageAddCount = 0,
    this.sageSubCount = 0,
    this.lastReplyArr = const [],
    this.sageAddUser = const [],
    this.sageSubUser = const [],
  });

  List<String> get mediaList {
    if (mediaUrl.isEmpty) return [];
    try {
      final list = jsonDecode(mediaUrl);
      if (list is List) return list.cast<String>();
    } catch (_) {}
    return mediaUrl.isNotEmpty ? [mediaUrl] : [];
  }

  bool get isSaged => status == 1;
  bool get isDeleted => status == 2;

  factory Post.fromJson(Map<String, dynamic> json) {
    List<int> _parseIntList(dynamic val) {
      if (val == null) return [];
      if (val is List) return val.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0).toList();
      return [];
    }

    List<String> _parseStringList(dynamic val) {
      if (val == null) return [];
      if (val is List) return val.map((e) => e.toString()).toList();
      return [];
    }

    List<Post> _parsePostList(dynamic val) {
      if (val == null) return [];
      if (val is List) return val.whereType<Map<String, dynamic>>().map(Post.fromJson).toList();
      return [];
    }

    return Post(
      id: json['Id'] as int? ?? 0,
      followId: json['FollowId'] as int? ?? 0,
      plateId: json['PlateId'] as int? ?? 0,
      status: json['Status'] as int? ?? 0,
      userId: json['UserId'] as int? ?? 0,
      time: json['Time'] as int? ?? 0,
      replyCount: json['ReplyCount'] as int? ?? 0,
      topStatus: json['TopStatus'] as int? ?? 0,
      lastReplyTime: json['LastReplyTime'] as int? ?? 0,
      title: json['Title'] as String? ?? '',
      value: json['Value'] as String? ?? '',
      mediaUrl: json['MediaUrl'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      replyArr: _parseIntList(json['ReplyArr']),
      sageAddId: _parseIntList(json['SageAddId']),
      sageSubId: _parseIntList(json['SageSubId']),
      sageAddCount: json['SageAddCount'] as int? ?? 0,
      sageSubCount: json['SageSubCount'] as int? ?? 0,
      lastReplyArr: _parsePostList(json['LastReplyArr']),
      sageAddUser: _parseStringList(json['SageAddUser']),
      sageSubUser: _parseStringList(json['SageSubUser']),
    );
  }
}
