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

/// Gertrude's & regional hospital canonical catalog of wards
const List<HospitalWard> kDefaultHospitalWards = [
  HospitalWard(
    wardId: 'ward-3',
    name: 'Ward 3',
    bedCount: 10,
    bedNumbers: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
    department: 'General Inpatient',
    description: 'Jaramanda Hospital · Ward 3',
  ),
  HospitalWard(
    wardId: 'ward-jacaranda',
    name: 'Jacaranda Ward (Pediatrics)',
    bedCount: 12,
    bedNumbers: ['25', '26', '27', '28', '29', '30', '31', '43', '44', '45', '46', '47'],
    department: 'Pediatrics',
    description: 'General Pediatric Inpatient Ward & Short-Stay Unit',
  ),
  HospitalWard(
    wardId: 'ward-edna',
    name: 'Edna Ward (Surgical)',
    bedCount: 10,
    bedNumbers: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
    department: 'Surgery',
    description: 'Post-operative Surgical Recovery & Orthopedics',
  ),
  HospitalWard(
    wardId: 'ward-kilimanjaro',
    name: 'Kilimanjaro Ward (Adult Medical)',
    bedCount: 14,
    bedNumbers: ['101', '102', '103', '104', '105', '106', '107', '108', '109', '110', '111', '112', '113', '114'],
    department: 'Internal Medicine',
    description: 'Acute Adult Medical Admissions & High Dependency',
  ),
  HospitalWard(
    wardId: 'ward-4b',
    name: 'Ward 4B (Inpatient Medical/Surgical)',
    bedCount: 5,
    bedNumbers: ['Bed 1', 'Bed 2', 'Bed 3', 'Bed 4', 'Bed 5'],
    department: 'Mixed Med-Surg',
    description: 'Clinical Station Reference Ward 4B',
  ),
];
