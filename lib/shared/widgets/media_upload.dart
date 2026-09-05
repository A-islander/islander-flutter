import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/api_constants.dart';
import '../../../main.dart';
import 'media_item.dart';

class MediaUploadWidget extends ConsumerStatefulWidget {
  final List<MediaItem> mediaItems;
  final ValueChanged<List<MediaItem>> onChanged;
  final int maxCount;

  const MediaUploadWidget({
    super.key,
    required this.mediaItems,
    required this.onChanged,
    this.maxCount = 4,
  });

  @override
  ConsumerState<MediaUploadWidget> createState() => _MediaUploadWidgetState();
}

class _MediaUploadWidgetState extends ConsumerState<MediaUploadWidget> {
  final ImagePicker _picker = ImagePicker();
  final Set<int> _uploadingIndices = {};
  double _uploadProgress = 0;

  Future<void> _pickImage() async {
    if (widget.mediaItems.length >= widget.maxCount) return;
    final images = await _picker.pickMultiImage();
    for (final img in images) {
      if (widget.mediaItems.length + _uploadingIndices.length >= widget.maxCount) break;
      await _uploadFile(img.path, 'image');
    }
  }

  Future<void> _pickVideo() async {
    if (widget.mediaItems.length >= widget.maxCount) return;
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) await _uploadFile(video.path, 'video');
  }

  Future<void> _uploadFile(String filePath, String type) async {
    final file = File(filePath);
    if (file.lengthSync() > ApiConstants.maxUploadSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件大小不能超过20MB')),
        );
      }
      return;
    }

    final dio = ref.read(dioClientProvider);
    final idx = widget.mediaItems.length + _uploadingIndices.length;
    setState(() => _uploadingIndices.add(idx));

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      final res = await dio.forumDio.post(
        ApiConstants.imgUpload,
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );

      final data = res.data;
      MediaItem item;
      if (data is Map && data['data'] != null) {
        final d = data['data'] as Map;
        item = MediaItem(
          id: (d['RequestId'] ?? '').toString(),
          url: d['url'] ?? d['images'] ?? '',
          thumbnailUrl: d['url'] ?? d['images'] ?? '',
          type: type == 'video' ? 'video' : 'image',
        );
      } else {
        item = MediaItem(id: '', url: filePath, thumbnailUrl: filePath, type: type);
      }

      if (mounted) {
        setState(() => _uploadingIndices.remove(idx));
        widget.onChanged([...widget.mediaItems, item]);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _uploadingIndices.remove(idx));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('上传失败')),
        );
      }
    }
  }

  void _removeItem(int index) {
    final updated = List<MediaItem>.from(widget.mediaItems)..removeAt(index);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Media preview grid
        if (widget.mediaItems.isNotEmpty || _uploadingIndices.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...widget.mediaItems.asMap().entries.map((e) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: e.value.type == 'video'
                          ? Container(
                              width: 80, height: 80,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.videocam, size: 32),
                            )
                          : Image.file(
                              File(e.value.url),
                              width: 80, height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 80, height: 80,
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 2, right: 2,
                      child: GestureDetector(
                        onTap: () => _removeItem(e.key),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              ..._uploadingIndices.map((_) => Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.colorScheme.primary),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 30, height: 30,
                      child: CircularProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(_uploadProgress * 100).toInt()}%',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              )),
            ],
          ),

        const SizedBox(height: 8),

        // Action buttons
        if (widget.mediaItems.length + _uploadingIndices.length < widget.maxCount)
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.image),
                onPressed: _pickImage,
                tooltip: '添加图片',
                iconSize: 20,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.videocam),
                onPressed: _pickVideo,
                tooltip: '添加视频',
                iconSize: 20,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              Text(
                '最多${widget.maxCount}个，单个不超过20MB',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
