class Plate {
  final int id;
  final String name;
  final int status;
  final String value;

  const Plate({required this.id, required this.name, required this.status, required this.value});

  factory Plate.fromJson(Map<String, dynamic> json) {
    return Plate(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      status: json['status'] as int? ?? 0,
      value: json['value'] as String? ?? '',
    );
  }
}
