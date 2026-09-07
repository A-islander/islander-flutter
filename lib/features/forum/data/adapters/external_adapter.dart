import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../../forum_repository.dart';

abstract class ExternalAdapter extends ForumRepository {
  ExternalAdapter(this.site, {Dio? transport, this.cookie = ''})
    : http =
          transport ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 25),
            ),
          ),
      super.base();
  @override
  final ForumSite site;
  final Dio http;
  final String cookie;
  final CancelToken _cancel = CancelToken();
  @override
  ForumCapabilities get capabilities => const ForumCapabilities();

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool json = true,
  }) async {
    final url = Uri.parse(site.endpoint).resolve(path);
    if (url.origin != Uri.parse(site.endpoint).origin) {
      throw const ForumFailure('请求目标与站点不符', code: 'security');
    }
    try {
      final response = await http.getUri<dynamic>(
        url.replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v'))),
        cancelToken: _cancel,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: {if (cookie.isNotEmpty) 'Cookie': cookie},
        ),
      );
      if ((response.statusCode ?? 500) >= 300) {
        throw const ForumFailure('外站拒绝请求或要求跳转', code: 'response');
      }
      final data = response.data;
      if (!json) return data is String ? data : throw const FormatException();
      return data is String ? jsonDecode(data) : data;
    } on DioException catch (_) {
      throw const ForumFailure('外站连接失败或需要访问权限，请重试或打开原站', code: 'network');
    } on FormatException catch (_) {
      throw const ForumFailure('外站返回格式异常，可能需要权限或接口已变化', code: 'parse');
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    http.close(force: true);
  }

  static int number(dynamic value) => int.tryParse('$value') ?? 0;
  static int timestamp(String value) {
    final cleaned = value.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
    return (DateTime.tryParse(
              '${cleaned.replaceFirst(' ', 'T')}+08:00',
            )?.millisecondsSinceEpoch ??
            0) ~/
        1000;
  }

  static bool safeUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        ['https', 'http'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static String text(String input) => nodeText(html.parseFragment(input));
  static String nodeText(dom.Node? root) {
    final result = StringBuffer();
    void visit(dom.Node node) {
      if (node is dom.Element) {
        if ([
              'script',
              'style',
              'noscript',
              'template',
            ].contains(node.localName) ||
            node.classes.contains('item-content-shadow')) {
          return;
        }
        if (node.localName == 'br') {
          result.writeln();
          return;
        }
        if (node.localName == 'img') {
          result.write(node.attributes['alt'] ?? '');
          return;
        }
      }
      if (node is dom.Text) result.write(node.data);
      for (final child in node.nodes) {
        visit(child);
      }
      if (node is dom.Element && ['p', 'div', 'li'].contains(node.localName)) {
        result.writeln();
      }
    }

    if (root != null) visit(root);
    return result
        .toString()
        .replaceAll(
          RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u202A-\u202E\u2066-\u2069]'),
          '',
        )
        .trim();
  }

  static void validPage(int page) {
    if (page < 0 || page >= 1000000) {
      throw const ForumFailure('页码超出范围', code: 'limit');
    }
  }
}
