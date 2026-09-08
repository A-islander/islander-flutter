import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islander_flutter/features/forum/forum_repository.dart';
import 'package:islander_flutter/features/forum/image_save_service.dart';
import 'package:islander_flutter/features/forum/image_viewer.dart';
import 'package:islander_flutter/shared/widgets/media_item.dart';

class ImageTransport implements HttpClientAdapter {
  List<int> bytes = 'GIF89a-original-animation'.codeUnits;
  int status = 200;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(
      bytes,
      status,
      headers: {
        Headers.contentTypeHeader: ['image/gif'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('permission denial never attempts an album write', () async {
    final calls = <String>[];
    const channel = MethodChannel('gal');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return false;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = ImageSaveService(
      transport: Dio()..httpClientAdapter = ImageTransport(),
    );
    await expectLater(
      service.save(
        url: 'https://media.example/a.gif',
        site: 'bog',
        postId: 10,
        index: 1,
        cancelToken: CancelToken(),
      ),
      throwsA(
        isA<ForumFailure>().having((e) => e.message, 'message', contains('权限')),
      ),
    );
    expect(calls, ['hasAccess', 'requestAccess']);
  });

  test(
    'album receives the untouched GIF bytes with an islander filename',
    () async {
      const channel = MethodChannel('gal');
      final transport = ImageTransport();
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'hasAccess' || call.method == 'requestAccess') {
              return true;
            }
            expect(call.method, 'putImageBytes');
            expect(call.arguments['bytes'], transport.bytes);
            expect(call.arguments['name'], 'islander-islander-10-1');
            writes++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = ImageSaveService(
        transport: Dio()..httpClientAdapter = transport,
      );
      expect(
        await service.save(
          url: 'https://media.example/a.gif',
          site: 'islander',
          postId: 10,
          index: 1,
          cancelToken: CancelToken(),
        ),
        '已保存到相册',
      );
      expect(writes, 1);
    },
  );

  test('cancelled download never reaches the save destination', () async {
    var writes = 0;
    final service = ImageSaveService(
      transport: Dio()..httpClientAdapter = ImageTransport(),
      sink: (_, name, mime) async {
        writes++;
        return 'saved';
      },
    );
    final cancel = CancelToken()..cancel();
    await expectLater(
      service.save(
        url: 'https://media.example/a.gif',
        site: 'x',
        postId: 10,
        index: 1,
        cancelToken: cancel,
      ),
      throwsA(isA<ForumFailure>()),
    );
    expect(writes, 0);
  });
  test(
    'downloads original bytes without credentials and uses the naming convention',
    () async {
      final transport = ImageTransport();
      final service = ImageSaveService(
        transport: Dio()..httpClientAdapter = transport,
        sink: (bytes, name, mime) async {
          expect(bytes, transport.bytes);
          expect(name, 'islander-x-123-2.gif');
          expect(mime, 'image/gif');
          return 'saved';
        },
      );
      expect(
        await service.save(
          url: 'https://media.example/original.gif',
          site: 'x',
          postId: 123,
          index: 2,
          cancelToken: CancelToken(),
        ),
        'saved',
      );
      expect(
        transport.requests.single.headers.keys.map((x) => x.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(
        transport.requests.single.headers.keys.map((x) => x.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(transport.requests.single.followRedirects, isFalse);
    },
  );

  test(
    'invalid addresses and non-images never reach the save destination',
    () async {
      final transport = ImageTransport();
      var saves = 0;
      final service = ImageSaveService(
        transport: Dio()..httpClientAdapter = transport,
        sink: (_, name, mime) async {
          saves++;
          return 'saved';
        },
      );
      Future<String> save(String url) => service.save(
        url: url,
        site: 'islander',
        postId: 10,
        index: 1,
        cancelToken: CancelToken(),
      );
      for (final url in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'https://secret@media.example/a',
      ]) {
        await expectLater(save(url), throwsA(isA<ForumFailure>()));
      }
      expect(transport.requests, isEmpty);
      transport.bytes = '<html>Not an image</html>'.codeUnits;
      await expectLater(
        save('https://media.example/a'),
        throwsA(isA<ForumFailure>()),
      );
      transport.status = 403;
      await expectLater(
        save('https://media.example/a'),
        throwsA(isA<ForumFailure>()),
      );
      expect(saves, 0);
    },
  );

  testWidgets('viewer offers save with visible success and failure status', (
    tester,
  ) async {
    final transport = ImageTransport();
    var saves = 0;
    final service = ImageSaveService(
      transport: Dio()..httpClientAdapter = transport,
      sink: (_, name, mime) async {
        saves++;
        return '已保存到相册';
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageSaveProvider.overrideWithValue(service)],
        child: const MaterialApp(
          home: Scaffold(
            body: ForumImageViewer(
              item: MediaItem(
                id: '1',
                url: 'https://media.example/a.gif',
                thumbnailUrl: 'https://media.example/thumb.gif',
                type: 'image',
              ),
              site: 'islander',
              postId: 10,
              index: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('image-save')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('已保存到相册'), findsOneWidget);
    transport.status = 403;
    await tester.tap(find.byKey(const Key('image-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('image-save-status')), findsOneWidget);
    expect(find.textContaining('图片下载失败'), findsOneWidget);
    expect(saves, 1);
  });
}
