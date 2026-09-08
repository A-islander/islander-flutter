import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/widgets/media_item.dart';
import 'forum_repository.dart';
import 'image_save_service.dart';

class ForumImageViewer extends ConsumerStatefulWidget {
  const ForumImageViewer({
    super.key,
    required this.item,
    required this.site,
    required this.postId,
    required this.index,
  });
  final MediaItem item;
  final String site;
  final int postId, index;
  @override
  ConsumerState<ForumImageViewer> createState() => _ForumImageViewerState();
}

class _ForumImageViewerState extends ConsumerState<ForumImageViewer> {
  CancelToken? _cancel;
  String? _message;
  double? _progress;
  bool _saving = false;
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
      _progress = null;
    });
    final cancel = _cancel = CancelToken();
    try {
      final message = await ref
          .read(imageSaveProvider)
          .save(
            url: widget.item.url,
            site: widget.site,
            postId: widget.postId,
            index: widget.index,
            cancelToken: cancel,
            onProgress: (received, total) {
              final value = total > 0
                  ? (received / total).clamp(0.0, 1.0)
                  : null;
              if (mounted &&
                  (value == null
                      ? _progress != null
                      : (_progress == null ||
                            (value * 100).floor() !=
                                (_progress! * 100).floor()))) {
                setState(() => _progress = value);
              }
            },
          );
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is ForumFailure ? error.message : '图片保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          onLongPress: _save,
          child: InteractiveViewer(
            minScale: .5,
            maxScale: 5,
            child: Image.network(
              widget.item.url,
              errorBuilder: (_, error, stack) => const Center(
                child: Text(
                  '图片加载失败，可重试下载或打开原图',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 4,
        right: 48,
        child: Row(
          children: [
            IconButton(
              onPressed: () async {
                final uri = Uri.tryParse(widget.item.url);
                if (uri != null &&
                    ['http', 'https'].contains(uri.scheme) &&
                    uri.userInfo.isEmpty) {
                  try {
                    if (await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    )) {
                      return;
                    }
                  } catch (_) {}
                }
                if (mounted) setState(() => _message = '无法打开原图');
              },
              tooltip: '打开原图',
              icon: const Icon(Icons.open_in_new, color: Colors.white),
            ),
            IconButton(
              key: const Key('image-save'),
              onPressed: _saving ? null : _save,
              tooltip: '保存原图',
              icon: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: _progress,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined, color: Colors.white),
            ),
          ],
        ),
      ),
      if (_message != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: ColoredBox(
            color: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _message!,
                key: const Key('image-save-status'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
    ],
  );
}
