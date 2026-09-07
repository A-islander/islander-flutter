class Plate {
  final int id;
  final String name;
  final int status;
  final String value;
  final String? sourceKey;
  String get key => sourceKey ?? '$id';

  const Plate({
    required this.id,
    required this.name,
    required this.status,
    required this.value,
    this.sourceKey,
  });

  factory Plate.fromJson(Map<String, dynamic> json) {
    return Plate(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      status: json['status'] as int? ?? 0,
      value: json['value'] as String? ?? '',
    );
  }
}
