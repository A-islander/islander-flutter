import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'forum_repository.dart';

final imageSaveProvider = Provider<ImageSaveService>((ref) {
  final service = ImageSaveService();
  ref.onDispose(service.dispose);
  return service;
});

class ImageSaveService {
  ImageSaveService({Dio? transport, this.sink})
    : _dio =
          transport ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
  final Dio _dio;
  final Future<String> Function(Uint8List bytes, String name, String mime)?
  sink;
  static const maxBytes = 40 * 1024 * 1024;
  void dispose() => _dio.close(force: true);

  static String extension(Uint8List bytes) {
    bool starts(List<int> prefix) =>
        bytes.length >= prefix.length &&
        List.generate(
          prefix.length,
          (i) => bytes[i] == prefix[i],
        ).every((x) => x);
    if (starts([0xff, 0xd8, 0xff])) return 'jpg';
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'png';
    if (starts('GIF87a'.codeUnits) || starts('GIF89a'.codeUnits)) return 'gif';
    if (starts('RIFF'.codeUnits) &&
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 12)) == 'ftypavif') {
      return 'avif';
    }
    throw const ForumFailure('返回内容不是支持的原图格式，请打开原图查看');
  }

  Future<String> save({
    required String url,
    required String site,
    required int postId,
    required int index,
    required CancelToken cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const ForumFailure('图片地址无效');
    }
    // A separate, credential-free client: never forward forum cookies to media.
    try {
      final result = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
        ),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (received > maxBytes || total > maxBytes) {
            cancelToken.cancel('image-too-large');
          }
          onProgress?.call(received, total);
        },
      );
      final bytes = Uint8List.fromList(result.data ?? []);
      if (bytes.length > maxBytes) {
        throw const ForumFailure('图片超过 40 MB，请打开原图下载');
      }
      final ext = extension(bytes);
      final safeSite = site.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final name = 'islander-$safeSite-$postId-$index.$ext';
      final mime = 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      if (cancelToken.isCancelled) throw const ForumFailure('已取消保存');
      if (sink != null) return await sink!(bytes, name, mime);
      if (kIsWeb) {
        await XFile.fromData(bytes, name: name, mimeType: mime).saveTo(name);
        return '已交给浏览器下载';
      }
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
          throw const ForumFailure('未获得保存权限，请在系统设置中允许保存图片');
        }
        if (cancelToken.isCancelled) throw const ForumFailure('已取消保存');
        await Gal.putImageBytes(
          bytes,
          name: defaultTargetPlatform == TargetPlatform.android
              ? name.substring(0, name.length - ext.length - 1)
              : name,
        );
        return '已保存到相册';
      }
      final location = await getSaveLocation(suggestedName: name);
      if (location == null) return '已取消保存';
      await XFile.fromData(
        bytes,
        name: name,
        mimeType: mime,
      ).saveTo(location.path);
      return '图片已保存';
    } on GalException catch (error) {
      throw ForumFailure(switch (error.type) {
        GalExceptionType.accessDenied => '没有相册保存权限，请检查系统设置',
        GalExceptionType.notEnoughSpace => '存储空间不足',
        GalExceptionType.notSupportedFormat => '相册不支持此图片格式，请打开原图保存',
        _ => '图片保存失败，请重试',
      });
    } on DioException {
      if (cancelToken.cancelError?.error == 'image-too-large') {
        throw const ForumFailure('图片超过 40 MB，请打开原图下载');
      }
      throw ForumFailure(
        cancelToken.isCancelled ? '已取消保存' : '图片下载失败；可重试或打开原图保存（Web 可能受跨域限制）',
      );
    }
  }
}
