import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:islander_flutter/app.dart';
import 'package:islander_flutter/main.dart';
import 'package:islander_flutter/core/network/dio_client.dart';
import 'package:islander_flutter/core/router/app_router.dart';
import 'package:islander_flutter/core/storage/storage_service.dart';

class ForumFixture implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool failPublish = false;
  bool failRead = false;
  bool failAuth = false;
  bool deleted = false;
  Map<String, dynamic>? overrideResponse;
  Map<String, dynamic> post(int id, {int follow = 0, int status = 0}) => {
    'id': id,
    'followId': follow,
    'plateId': 1,
    'userId': 7,
    'name': '测试岛民',
    'title': follow == 0 ? '测试主串 $id' : '',
    'value': follow == 0 ? '讨论正文 $id' : '回复正文 $id No.10',
    'time': 1700000000,
    'replyCount': 1,
    'status': deleted ? 2 : status,
    'mediaUrl': '[]',
    'replyArr': [],
    'lastReplyArr': [],
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    dynamic data;
    var code = 200;
    var msg = 'ok';
    if (path == '/plate/get') {
      data = [
        {'id': 1, 'name': '综合版', 'status': 0, 'value': '岛民的日常'},
        {'id': 2, 'name': '技术版', 'status': 0, 'value': '开发交流'},
      ];
    } else if (path == '/user/get') {
      if (failAuth) {
        code = 403;
        msg = 'token is field';
      } else {
        data = {'id': 7, 'name': '测试岛民'};
      }
    } else if (path == '/forum/get') {
      final id = options.queryParameters['postId'] as int;
      data = post(id, follow: id == 11 ? 10 : 0);
    } else if (path == '/forum/postPage') {
      data = {'page': 1, 'floor': 2};
    } else if (path == '/forum/post' || path == '/forum/reply') {
      if (failPublish) {
        code = 500;
        msg = '发布失败，请重试';
      }
    } else if (path.contains('/forum/sage/') && !path.endsWith('list')) {
      data = true;
    } else if (path.contains('/forum/delete/') ||
        path.contains('/forum/recover/')) {
      data = {'status': true};
    } else if (path == '/img/upload') {
      data = {
        'success': true,
        'RequestId': 'image-1',
        'data': {'url': 'https://media.example/test.png'},
      };
    } else {
      if (failRead) {
        code = 500;
        msg = '加载失败，请重试';
      }
      data = path == '/forum/list'
          ? {
              'count': 2,
              'list': [post(10), post(11, follow: 10)],
            }
          : {
              'count': 21,
              'list': [post(options.queryParameters['page'] == 1 ? 20 : 10)],
            };
    }
    return ResponseBody.fromString(
      jsonEncode(overrideResponse ?? {'code': code, 'data': data, 'msg': msg}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  DioClient client() {
    final forum = Dio(BaseOptions(baseUrl: 'https://forum.test/'))
      ..httpClientAdapter = this;
    final user = Dio(BaseOptions(baseUrl: 'https://user.test/'))
      ..httpClientAdapter = this;
    return DioClient(forumDio: forum, userDio: user);
  }
}

Future<void> pumpForum(
  WidgetTester tester,
  ForumFixture fixture, {
  bool authenticated = false,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(
    authenticated ? {'token': 'test-cookie', 'name': '测试岛民', 'userId': 7} : {},
  );
  final storage = StorageService(await SharedPreferences.getInstance());
  AppRouter.router.go('/plate/0');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        dioClientProvider.overrideWithValue(fixture.client()),
      ],
      child: const IslanderApp(),
    ),
  );
  await pumpFrames(tester);
}

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
