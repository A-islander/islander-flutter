class Plate {
  final int id;
  final String name;
  final int status;
  final String value;

  const Plate({required this.id, required this.name, required this.status, required this.value});

  factory Plate.fromJson(Map<String, dynamic> json) {
    return Plate(
      id: json['Id'] as int? ?? 0,
      name: json['Name'] as String? ?? '',
      status: json['Status'] as int? ?? 0,
      value: json['Value'] as String? ?? '',
    );
  }
}
