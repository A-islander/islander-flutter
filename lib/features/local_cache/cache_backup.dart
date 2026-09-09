import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'cached_post.dart';
import '../forum/domain/forum_site.dart';

const cacheBackupLimit = 32 * 1024 * 1024;

/// Bounded decompression, no archive paths are ever extracted to the filesystem.
class _BoundedOutput extends OutputMemoryStream {
  void check(int n) {
    if (length + n > cacheBackupLimit) {
      throw const FormatException('备份解压后超过 32 MB，请分批导出');
    }
  }

  @override
  void writeByte(int value) {
    check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    check(count);
    super.writeBackReference(distance, count);
  }
}

Uint8List encodeCacheBackup(List<CachedPost> rows) {
  final posts = rows
      .map(
        (r) => {
          'site': r.site.id,
          'instance': r.site.instanceKey,
          'thread': r.threadId,
          'page': r.page,
          'pinned': r.pinned,
          'browsedAt': r.browsedAt,
          'post': cachePostJson(r.post),
        },
      )
      .toList();
  final bytes = utf8.encode(
    jsonEncode({
      'format': 'islander-cache',
      'version': 1,
      'attachments': 'urls-only',
      'posts': posts,
    }),
  );
  if (bytes.length > cacheBackupLimit) {
    throw const FormatException('单份备份最多 32 MB，请分批选择导出');
  }
  return Uint8List.fromList(
    ZipEncoder().encode(
      Archive()..add(ArchiveFile('islander-cache.json', bytes.length, bytes)),
    ),
  );
}

List<Map<String, dynamic>> decodeCacheBackup(Uint8List bytes) {
  if (bytes.length > cacheBackupLimit) {
    throw const FormatException('备份超过 32 MB');
  }
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length != 1) {
    throw const FormatException('不是支持的岛民岛缓存备份');
  }
  final header = directory.fileHeaders.single;
  final file = header.file;
  if (file == null ||
      (file.flags & 1) != 0 ||
      file.filename != 'islander-cache.json' ||
      file.uncompressedSize > cacheBackupLimit ||
      ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000 ||
      ![
        CompressionType.none,
        CompressionType.deflate,
      ].contains(file.compressionMethod)) {
    throw const FormatException('不是支持的岛民岛缓存备份');
  }
  final output = _BoundedOutput();
  final raw = InputMemoryStream(file.getRawContent());
  if (file.compressionMethod == CompressionType.deflate) {
    const ZLibDecoderWeb().decodeStream(raw, output, raw: true);
  } else {
    output.writeStream(raw);
  }
  final data = output.getBytes();
  if (data.length != file.uncompressedSize || getCrc32(data) != file.crc32) {
    throw const FormatException('备份校验失败');
  }
  final root = jsonDecode(utf8.decode(data));
  if (root is! Map ||
      root['format'] != 'islander-cache' ||
      root['version'] != 1 ||
      root['posts'] is! List) {
    throw const FormatException('不支持的备份版本');
  }
  final list = root['posts'] as List;
  if (list.length > 100000) throw const FormatException('备份条数过多');
  return list.map((value) {
    if (value is! Map) throw const FormatException('备份记录异常');
    final r = Map<String, dynamic>.from(value);
    final site = ForumSite.byId(r['site'] as String);
    if (r['instance'] != site.instanceKey || r['post'] is! Map) {
      throw const FormatException('备份站点实例不匹配');
    }
    final j = Map<String, dynamic>.from(r['post'] as Map);
    if (j['id'] is! int ||
        (j['id'] as int) <= 0 ||
        utf8.encode(jsonEncode(j)).length > 1024 * 1024) {
      throw const FormatException('帖子数据异常');
    }
    final p = cachePostFromJson(j, site);
    if (p.followId < 0 ||
        r['thread'] != null &&
            (r['thread'] is! int || (r['thread'] as int) <= 0) ||
        r['page'] != null &&
            (r['page'] is! int ||
                (r['page'] as int) < 0 ||
                (r['page'] as int) > 1000000)) {
      throw const FormatException('帖子导航数据异常');
    }
    if (!p.parentUnknown && r['thread'] != (p.isRoot ? p.id : p.followId)) {
      throw const FormatException('所属串不一致');
    }
    final browsedAt = r['browsedAt'];
    if (browsedAt != null &&
        (browsedAt is! int ||
            browsedAt <= 0 ||
            browsedAt > DateTime.now().microsecondsSinceEpoch ||
            !p.isRoot ||
            p.parentUnknown)) {
      throw const FormatException('浏览时间异常');
    }
    return {
      'site': site.id,
      'instance': site.instanceKey,
      'post': cachePostJson(p),
      'thread': r['thread'],
      'page': r['page'],
      'pinned': r['pinned'] == true,
      'browsedAt': browsedAt,
    };
  }).toList();
}

Future<String> saveCacheBackup(List<CachedPost> rows) async {
  if (rows.isEmpty) return '没有可导出的内容';
  var estimate = 512;
  for (final row in rows) {
    estimate += utf8.encode(row.payload).length + 512;
    if (estimate > cacheBackupLimit) {
      throw const FormatException('单份备份最多 32 MB，请分批选择导出');
    }
  }
  final bytes = await compute(encodeCacheBackup, rows);
  final name =
      'islander-cache-${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.zip';
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final saved = await const MethodChannel(
      'islander/cache_backup',
    ).invokeMethod<bool>('save', {'name': name, 'bytes': bytes});
    return saved == true ? '缓存备份已保存' : '已取消导出';
  }
  final file = XFile.fromData(bytes, name: name, mimeType: 'application/zip');
  if (kIsWeb) {
    await file.saveTo(name);
    return '已交给浏览器下载';
  }
  final target = await getSaveLocation(suggestedName: name);
  if (target == null) return '已取消导出';
  await file.saveTo(target.path);
  return '缓存备份已保存';
}

Future<List<Map<String, dynamic>>?> pickCacheBackup() async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: '岛民岛缓存备份',
        extensions: ['zip'],
        mimeTypes: ['application/zip'],
        uniformTypeIdentifiers: ['public.zip-archive'],
      ),
    ],
  );
  if (file == null) return null;
  if (await file.length() > cacheBackupLimit) {
    throw const FormatException('备份超过 32 MB');
  }
  return compute(decodeCacheBackup, await file.readAsBytes());
}
