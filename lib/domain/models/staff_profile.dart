import 'package:equatable/equatable.dart';

/// Clinical Staff Profile for Digital ID representation and authorization.
class StaffProfile extends Equatable {
  final String staffId;
  final String name;
  final String role;
  final String wardId;
  final String avatarColor;
  final String initials;
  final bool isActive;

  const StaffProfile({
    required this.staffId,
    required this.name,
    required this.role,
    required this.wardId,
    required this.avatarColor,
    required this.initials,
    this.isActive = true,
  });

  bool get isWardNurse => role == 'ward_nurse';
  bool get isChargeNurse => role == 'charge_nurse';
  bool get isDoctorOnCall => role == 'doctor_on_call';

  String get formattedRole {
    switch (role) {
      case 'charge_nurse':
        return 'Charge Nurse';
      case 'doctor_on_call':
        return 'Doctor on Call';
      case 'ward_nurse':
      default:
        return 'Ward Nurse';
    }
  }

  factory StaffProfile.fromJson(Map<String, dynamic> json) {
    return StaffProfile(
      staffId: json['staff_id'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      wardId: json['ward_id'] as String,
      avatarColor: json['avatar_color'] as String? ?? '#059669',
      initials: json['initials'] as String? ?? 'RN',
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'staff_id': staffId,
      'name': name,
      'role': role,
      'ward_id': wardId,
      'avatar_color': avatarColor,
      'initials': initials,
      'is_active': isActive,
    };
  }

  @override
  List<Object?> get props => [
        staffId,
        name,
        role,
        wardId,
        avatarColor,
        initials,
        isActive,
      ];
}
