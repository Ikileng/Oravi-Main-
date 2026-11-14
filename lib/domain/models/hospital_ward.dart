class HospitalWard {
  final String wardId;
  final String name;
  final int bedCount;
  final List<String> bedNumbers;
  final String department;
  final String description;

  const HospitalWard({
    required this.wardId,
    required this.name,
    required this.bedCount,
    required this.bedNumbers,
    required this.department,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
        'ward_id': wardId,
        'name': name,
        'bed_count': bedCount,
        'bed_numbers': bedNumbers,
        'department': department,
        'description': description,
      };

  factory HospitalWard.fromMap(Map<String, dynamic> map) {
    return HospitalWard(
      wardId: map['ward_id'] as String,
      name: map['name'] as String,
      bedCount: map['bed_count'] as int,
      bedNumbers: List<String>.from(map['bed_numbers'] ?? []),
      department: map['department'] as String? ?? 'General',
      description: map['description'] as String? ?? '',
    );
  }
}
