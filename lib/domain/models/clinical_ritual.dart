class ClinicalRitual {
  final String ritualId;
  final String ritualType;
  final String title;
  final String? patientId;
  final String creatorId;
  final String status;
  final String? roomName;
  final String? recordingStatus;
  final String? egressId;
  final String? transcript;
  final Map<String, dynamic>? summary;

  const ClinicalRitual({
    required this.ritualId,
    required this.ritualType,
    required this.title,
    required this.patientId,
    required this.creatorId,
    required this.status,
    required this.roomName,
    required this.recordingStatus,
    required this.egressId,
    required this.transcript,
    required this.summary,
  });

  factory ClinicalRitual.fromMap(Map<String, dynamic> map) {
    return ClinicalRitual(
      ritualId: map['ritual_id'] as String,
      ritualType: map['ritual_type'] as String,
      title: map['title'] as String,
      patientId: map['patient_id'] as String?,
      creatorId: map['creator_id'] as String,
      status: map['status'] as String,
      roomName: map['room_name'] as String?,
      recordingStatus: map['recording_status'] as String?,
      egressId: map['egress_id'] as String?,
      transcript: map['transcript'] as String?,
      summary: map['summary'] as Map<String, dynamic>?,
    );
  }
}

class ClinicalRitualRoomSession {
  final String roomName;
  final String liveKitUrl;
  final String token;

  const ClinicalRitualRoomSession({
    required this.roomName,
    required this.liveKitUrl,
    required this.token,
  });

  factory ClinicalRitualRoomSession.fromMap(Map<String, dynamic> map) {
    return ClinicalRitualRoomSession(
      roomName: map['room_name'] as String,
      liveKitUrl: map['livekit_url'] as String,
      token: map['token'] as String,
    );
  }
}
