import 'dart:convert';
import 'dart:io' show Cookie;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:image_picker/image_picker.dart';
import '../../../../shared/widgets/media_item.dart';
import '../../../plate/models/plate_model.dart';
import '../../forum_repository.dart';

/// One submission, one in-memory session. Never uses Islander's Dio/auth.
class ExternalWriter {
  ExternalWriter(this.site, this.http, String cookie, this.cancel)
    : base = writeBase(site) {
    for (final pair in cookie.split(';')) {
      final at = pair.indexOf('=');
      if (at <= 0) throw const ForumFailure('发帖饼干格式无效', code: 'auth');
      final value = Cookie(
        pair.substring(0, at).trim(),
        pair.substring(at + 1).trim(),
      )..path = '/';
      _cookies['${value.name}|/'] = value;
      _identityNames.add(value.name);
    }
  }
  final ForumSite site;
  final Dio http;
  final CancelToken cancel;
  final Uri base;
  final _cookies = <String, Cookie>{};
  final _identityNames = <String>{};
  Uri? _referer;
  static const maxImageBytes = 20 * 1024 * 1024;
  static const _maxResponse = 8 * 1024 * 1024;

  static Uri writeBase(ForumSite site) => Uri.parse(
    site.id == 'x' && site.endpoint == ForumSite.x.endpoint
        ? 'https://www.nmbxd1.com/'
        : site.endpoint,
  );

  static const unknownResult = ForumFailure(
    '未能确认提交结果，草稿已保留。请先到原站核对，避免重复发送',
    code: 'unknown_result',
  );

  static Future<({Uint8List bytes, String mime})> image(XFile file) async {
    try {
      if (await file.length() > maxImageBytes) {
        throw const ForumFailure('图片不能超过 20 MB', code: 'invalid');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxImageBytes) {
        throw const ForumFailure('图片不能超过 20 MB', code: 'invalid');
      }
      bool starts(List<int> prefix) =>
          bytes.length >= prefix.length &&
          Iterable.generate(prefix.length).every((i) => bytes[i] == prefix[i]);
      final mime = starts([0xff, 0xd8, 0xff])
          ? 'image/jpeg'
          : starts([137, 80, 78, 71, 13, 10, 26, 10])
          ? 'image/png'
          : starts('GIF87a'.codeUnits) || starts('GIF89a'.codeUnits)
          ? 'image/gif'
          : starts([66, 77])
          ? 'image/bmp'
          : null;
      if (mime == null) {
        throw const ForumFailure('外站图片仅支持 JPEG、PNG、GIF、BMP', code: 'invalid');
      }
      return (bytes: bytes, mime: mime);
    } on ForumFailure {
      rethrow;
    } catch (_) {
      throw const ForumFailure('本机图片不可读取或已被系统清理，请重新选择', code: 'invalid');
    }
  }

  String _cookieHeader(Uri url) {
    final now = DateTime.now();
    return _cookies.values
        .where((c) {
          final path = c.path ?? '/';
          return (!c.secure || url.scheme == 'https') &&
              (c.expires == null || c.expires!.isAfter(now)) &&
              (url.path == path ||
                  url.path.startsWith(path.endsWith('/') ? path : '$path/'));
        })
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
  }

  void _remember(Response response, Uri url) {
    for (final raw in response.headers['set-cookie'] ?? <String>[]) {
      try {
        final c = Cookie.fromSetCookieValue(raw);
        // Returned sessions may not silently replace the selected identity.
        if (_identityNames.contains(c.name)) continue;
        final domain = c.domain?.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        if (domain != null &&
            url.host != domain &&
            !url.host.endsWith('.$domain')) {
          continue;
        }
        if (c.path == null || !c.path!.startsWith('/')) {
          final slash = url.path.lastIndexOf('/');
          c.path = slash <= 0 ? '/' : url.path.substring(0, slash);
        }
        if (c.maxAge != null) {
          c.expires = DateTime.now().add(Duration(seconds: c.maxAge!));
        }
        _cookies['${c.name}|${c.path}'] = c;
      } catch (_) {
        /* Ignore malformed session cookies, not forum errors. */
      }
    }
  }

  Future<String> _request(
    String method,
    Uri url, {
    Object? data,
    String? contentType,
    void Function(int, int)? onProgress,
  }) async {
    if (url.origin != base.origin ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.hasQuery) {
      throw const ForumFailure('拒绝向不同站点提交帖子或饼干', code: 'security');
    }
    if (cancel.isCancelled) {
      throw const ForumFailure('身份或页面已改变，尚未提交', code: 'auth');
    }
    final requestCancel = CancelToken();
    var finished = false;
    // Repositories cancel old-identity requests when their scope is replaced.
    cancel.whenCancel.then((_) {
      if (!finished) requestCancel.cancel();
    });
    try {
      final response = await http.requestUri<String>(
        url,
        data: data,
        cancelToken: requestCancel,
        onSendProgress: onProgress,
        onReceiveProgress: (received, total) {
          if (received > _maxResponse || total > _maxResponse) {
            requestCancel.cancel();
          }
        },
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          contentType: contentType,
          followRedirects: false,
          sendTimeout: const Duration(seconds: 40),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
          headers: {
            'Cookie': _cookieHeader(url),
            'Referer': (_referer ?? base).toString(),
            if (method == 'POST') 'Origin': base.origin,
          },
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        throw const ForumFailure('饼干无效、权限不足或需要网页验证，请在原站检查', code: 'auth');
      }
      if (status == 429) {
        throw const ForumFailure('站点限制发言频率，请稍后手动重试', code: 'rate_limit');
      }
      if (status < 200 || status >= 300) {
        throw method == 'POST'
            ? unknownResult
            : const ForumFailure('无法读取发帖表单；不跟随重定向，尚未提交', code: 'network');
      }
      final body = response.data ?? '';
      if (utf8.encode(body).length > _maxResponse) {
        throw method == 'POST'
            ? unknownResult
            : const ForumFailure('发帖表单过大，尚未提交', code: 'response');
      }
      _remember(response, url);
      return body;
    } on DioException {
      throw method == 'POST'
          ? unknownResult
          : const ForumFailure('无法读取发帖表单，尚未提交', code: 'network');
    } finally {
      finished = true;
    }
  }

  static void validateText(String body, String title, String site) {
    if (body.trim().isEmpty || utf8.encode(body).length > 8192) {
      throw const ForumFailure(
        '正文不能为空，且不能超过 8192 字节（约 2700 个汉字）',
        code: 'invalid',
      );
    }
    if (utf8.encode(title).length > 128 || site == 'bog' && title.length > 50) {
      throw const ForumFailure('标题过长，请缩短后重试', code: 'invalid');
    }
  }

  static bool validPic(String id) =>
      id.isNotEmpty &&
      id.length <= 200 &&
      !id.contains('..') &&
      RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(id);

  Future<void> publish({
    required String body,
    required String title,
    required int boardId,
    String? boardKey,
    int? threadId,
    required List<MediaItem> media,
    required List<XFile> files,
    required Future<List<Plate>> Function() boards,
  }) async {
    validateText(body, title, site.id);
    if (threadId != null && threadId <= 0) {
      throw const ForumFailure('回复目标无效', code: 'invalid');
    }
    if (site.id == 'x' && (files.length > 1 || media.isNotEmpty) ||
        site.id == 'bog' && (files.isNotEmpty || media.length > 9)) {
      throw const ForumFailure('X 最多一张本机图片；BOG 最多九张已上传图片', code: 'invalid');
    }
    for (final m in media) {
      if (m.type != 'image' ||
          !validPic(m.id) ||
          m.url != base.resolve('image_pre/thumb/${m.id}').toString()) {
        throw const ForumFailure('BOG 附件必须来自当前站点的上传回执', code: 'invalid');
      }
    }
    final picture = files.isEmpty ? null : await image(files.single);
    String? boardName;
    if (threadId == null) {
      final all = await boards();
      final matches = all
          .where((p) => site.id == 'bog' ? p.key == boardKey : p.id == boardId)
          .toList();
      if (matches.length != 1) {
        throw const ForumFailure('请选择具体发串板块，时间线不能直接发布', code: 'invalid');
      }
      boardName = matches.single.name;
      if (boardName.isEmpty || boardName == '.' || boardName == '..') {
        throw const ForumFailure('板块名称无效', code: 'invalid');
      }
    }
    final page = base.resolve(
      threadId == null
          ? 'f/${Uri.encodeComponent(boardName!)}${site.id == 'bog' ? '/1' : ''}'
          : 't/$threadId${site.id == 'bog' ? '/1' : ''}',
    );
    _referer = page;
    final source = await _request('GET', page);
    final form = parseForm(
      source,
      page: page,
      site: site.id,
      body: body,
      title: title,
      boardId: boardId,
      boardName: boardName,
      threadId: threadId,
      hasImage: picture != null,
    );
    if (site.id == 'x') {
      final data = FormData();
      data.fields.addAll(
        form.fields.entries.expand(
          (e) => e.value.map((v) => MapEntry(e.key, v)),
        ),
      );
      if (picture != null) {
        data.files.add(
          MapEntry(
            'image',
            MultipartFile.fromBytes(
              picture.bytes,
              filename: _filename(files.single.name),
              contentType: DioMediaType.parse(picture.mime),
            ),
          ),
        );
      }
      xResult(await _request('POST', form.action, data: data));
    } else {
      if (media.isNotEmpty) {
        form.fields['img[]'] = media.map((m) => m.id).toList();
      }
      final encoded = form.fields.entries
          .expand(
            (e) => e.value.map(
              (v) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(v)}',
            ),
          )
          .join('&');
      final result = _json(
        await _request(
          'POST',
          form.action,
          data: encoded,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      if (int.tryParse('${result['code']}') != 1) {
        throw bogError(result['code']);
      }
    }
  }

  static String _filename(String name) =>
      name.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'[\r\n"]'), '_');

  Future<MediaItem> upload(
    XFile file,
    void Function(int, int) onProgress,
  ) async {
    final picture = await image(file);
    final data = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        picture.bytes,
        filename: _filename(file.name),
        contentType: DioMediaType.parse(picture.mime),
      ),
    });
    final result = _json(
      await _request(
        'POST',
        base.resolve('post/upload'),
        data: data,
        onProgress: onProgress,
      ),
    );
    if (int.tryParse('${result['code']}') != 200) {
      throw bogError(result['code']);
    }
    final id = result['pic'];
    if (id is! String || !validPic(id)) throw unknownResult;
    final url = base.resolve('image_pre/thumb/$id').toString();
    return MediaItem(id: id, url: url, thumbnailUrl: url, type: 'image');
  }

  static Map _json(String source) {
    try {
      final result = jsonDecode(source);
      if (result is Map) return result;
    } catch (_) {
      /* Do not echo server responses or credentials. */
    }
    throw unknownResult;
  }

  static ({Uri action, Map<String, List<String>> fields}) parseForm(
    String source, {
    required Uri page,
    required String site,
    required String body,
    required String title,
    required int boardId,
    String? boardName,
    int? threadId,
    bool hasImage = false,
  }) {
    const changed = ForumFailure('发帖表单缺失、目标不符或结构已变化，尚未提交', code: 'response');
    final reply = threadId != null;
    final path = site == 'bog'
        ? '/post'
        : reply
        ? '/Home/Forum/doReplyThread.html'
        : '/Home/Forum/doPostThread.html';
    final target = site == 'bog'
        ? (reply ? 'res' : 'forum')
        : (reply ? 'resto' : 'fid');
    final content = site == 'bog' ? 'comment' : 'content';
    final forms = html
        .parse(source)
        .querySelectorAll('form')
        .where((e) => Uri.tryParse(e.attributes['action'] ?? '')?.path == path)
        .toList();
    if (forms.length != 1) throw changed;
    final form = forms.single;
    final action = page.resolve(form.attributes['action']!);
    if (form.attributes['method']?.toLowerCase() != 'post' ||
        action.origin != page.origin ||
        action.userInfo.isNotEmpty ||
        action.hasQuery ||
        action.hasFragment) {
      throw changed;
    }
    final fields = <String, List<String>>{};
    var bodyCount = 0, titleCount = 0, imageCount = 0;
    for (final element in form.querySelectorAll('[name]')) {
      final name = element.attributes['name']!;
      final type = element.attributes['type']?.toLowerCase();
      var disabled = element.attributes.containsKey('disabled');
      // BOG's official #other toggle enables .hid-input fields. A supplied
      // title is the equivalent explicit opt-in; other disabled fields stay off.
      if (site == 'bog' &&
          name == 'title' &&
          element.parent?.classes.contains('hid-input') == true &&
          form.querySelector('#other') != null) {
        disabled = false;
      }
      for (
        var parent = element.parent;
        parent != null && parent != form;
        parent = parent.parent
      ) {
        if (parent.localName == 'fieldset' &&
            parent.attributes.containsKey('disabled')) {
          disabled = true;
        }
      }
      if (name.toLowerCase().contains('captcha') || name == 'verify') {
        throw const ForumFailure('当前表单要求验证码，请到原站完成验证，尚未提交', code: 'challenge');
      }
      if (disabled) continue;
      if (!reply && (name == 'res' || name == 'resto')) throw changed;
      if (element.localName == 'input' &&
          type == 'hidden' &&
          (name == target || name == '__hash__')) {
        fields
            .putIfAbsent(name, () => [])
            .add(element.attributes['value'] ?? '');
      }
      String? value;
      if (element.localName == 'textarea' && name == content) {
        bodyCount++;
        value = body;
      }
      if (element.localName == 'input' && name == 'title') {
        titleCount++;
        value = title;
      }
      if (element.localName == 'input' && type == 'file' && name == 'image') {
        imageCount++;
      }
      final limit = int.tryParse(element.attributes['maxlength'] ?? '') ?? 0;
      if (value != null && limit > 0 && value.length > limit) {
        throw const ForumFailure('正文或标题超过当前表单限制，尚未提交', code: 'invalid');
      }
      if (site == 'x' &&
          name == 'water' &&
          type == 'checkbox' &&
          element.attributes.containsKey('checked')) {
        fields['water'] = [element.attributes['value'] ?? 'true'];
      }
    }
    final expected =
        threadId ??
        (site == 'x'
            ? boardId
            : int.tryParse(fields[target]?.firstOrNull ?? '') ?? 0);
    if (bodyCount != 1 ||
        expected <= 0 ||
        fields[target]?.length != 1 ||
        fields[target]!.single != '$expected') {
      throw changed;
    }
    if (site == 'bog' &&
        !reply &&
        form.querySelector('.compose-title span')?.text.trim() != boardName) {
      throw changed;
    }
    if (site == 'x' &&
        (fields['__hash__']?.length != 1 ||
            fields['__hash__']!.single.isEmpty ||
            hasImage && imageCount != 1)) {
      throw changed;
    }
    if (title.isNotEmpty && titleCount != 1) {
      throw const ForumFailure('当前表单不接受标题，请清空标题后重试', code: 'invalid');
    }
    fields[content] = [body];
    if (titleCount == 1) fields['title'] = [title];
    return (
      action: site == 'bog'
          ? action.replace(path: '${action.path}/post')
          : action,
      fields: fields,
    );
  }

  static void xResult(String source) {
    final doc = html.parse(source);
    final error = doc.querySelector('.error')?.text;
    if (error != null) {
      if (error.contains('验证码')) {
        throw const ForumFailure('X 岛要求验证码，请到原站完成验证', code: 'challenge');
      }
      if (error.contains('饼干')) {
        throw const ForumFailure('X 岛拒绝了当前饼干，请在原站检查', code: 'auth');
      }
      if (error.contains('频繁') || error.contains('间隔')) {
        throw const ForumFailure('X 岛限制发言频率，请稍后手动重试', code: 'rate_limit');
      }
      throw const ForumFailure('X 岛拒绝发帖，请在原站检查锁定、版规、内容及图片限制', code: 'rejected');
    }
    final success = doc.querySelector('.success')?.text.trim();
    if (success != null &&
        RegExp(r'^(回复成功|回应成功|发表成功|发帖成功)[！!]?$').hasMatch(success)) {
      return;
    }
    throw unknownResult;
  }

  static ForumFailure bogError(dynamic value) =>
      switch (int.tryParse('$value')) {
        4 => const ForumFailure('BOG 反垃圾检测暂停了发言，请到原站查看', code: 'rate_limit'),
        101 => const ForumFailure('BOG 要求验证码，请在原站完成验证后手动重试', code: 'challenge'),
        1000 ||
        1001 ||
        1002 ||
        1003 ||
        1004 => const ForumFailure('BOG 饼干或影武者不可用，请在原站检查', code: 'auth'),
        301 ||
        302 ||
        303 ||
        304 ||
        1005 ||
        1008 => const ForumFailure('BOG 拒绝图片，请检查格式、大小、数量和权限', code: 'rejected'),
        1101 => const ForumFailure('BOG 发帖目标不存在或已锁定', code: 'not_found'),
        1102 => const ForumFailure('BOG 提示重复内容，请先核对原站', code: 'duplicate'),
        1100 ||
        1103 ||
        1201 => const ForumFailure('BOG 拒绝发帖，请在原站检查目标和内容', code: 'rejected'),
        _ => unknownResult,
      };
}
