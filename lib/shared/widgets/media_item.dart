import 'dart:convert';

class MediaItem {
  final String id;
  final String url;
  final String thumbnailUrl;
  final String type; // 'image' | 'video'

  const MediaItem({
    required this.id,
    required this.url,
    required this.thumbnailUrl,
    required this.type,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: (json['id'] ?? json['RequestId'] ?? '').toString(),
      url: json['url'] ?? json['images'] ?? '',
      thumbnailUrl: json['thumbnailUrl'] ?? json['url'] ?? json['images'] ?? '',
      type: json['type'] ?? (json['images'] != null ? 'image' : 'video'),
    );
  }

  static List<MediaItem> parseMediaUrl(String mediaUrl) {
    if (mediaUrl.isEmpty) return [];
    try {
      final decoded = jsonDecode(mediaUrl);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(MediaItem.fromJson)
            .toList();
      }
    } catch (_) {}
    // plain URL string fallback
    if (mediaUrl.startsWith('http')) return [MediaItem(id: '', url: mediaUrl, thumbnailUrl: mediaUrl, type: 'image')];
    return [];
  }
}
