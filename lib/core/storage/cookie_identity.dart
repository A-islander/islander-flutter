import 'dart:math';

class CookieIdentity {
  const CookieIdentity({
    required this.id,
    required this.token,
    required this.name,
    required this.userId,
    this.label = '',
    this.invalid = false,
  });
  final String id, token, name, label;
  final int userId;
  final bool invalid;
  String get displayName => label.isNotEmpty
      ? label
      : name.isNotEmpty
      ? name
      : '岛民 #$userId';
  static String newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  CookieIdentity copyWith({
    String? name,
    int? userId,
    String? label,
    bool? invalid,
  }) => CookieIdentity(
    id: id,
    token: token,
    name: name ?? this.name,
    userId: userId ?? this.userId,
    label: label ?? this.label,
    invalid: invalid ?? this.invalid,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'token': token,
    'name': name,
    'userId': userId,
    'label': label,
    'invalid': invalid,
  };
  factory CookieIdentity.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(json['id']) ||
        json['token'] is! String ||
        (json['token'] as String).isEmpty ||
        json['userId'] is! int) {
      throw const FormatException('Invalid cookie record');
    }
    return CookieIdentity(
      id: json['id'],
      token: json['token'],
      name: json['name'] as String,
      userId: json['userId'],
      label: json['label'] as String? ?? '',
      invalid: json['invalid'] as bool? ?? false,
    );
  }
}
