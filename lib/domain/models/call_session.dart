class CallSession {
  final String callId;
  final String patientId;
  final String loopId;
  final String callerId;
  final String callerName;
  final String callerRole;
  final String recipientId;
  final String recipientName;
  final String recipientRole;
  final String roomName;
  final String liveKitUrl;
  final String token;
  final bool isIncoming;
  final String status;

  const CallSession({
    required this.callId,
    required this.patientId,
    required this.loopId,
    required this.callerId,
    required this.callerName,
    this.callerRole = 'clinician',
    required this.recipientId,
    required this.recipientName,
    required this.recipientRole,
    required this.roomName,
    required this.liveKitUrl,
    required this.token,
    this.isIncoming = false,
    this.status = 'ringing',
  });

  factory CallSession.fromMap(Map<String, dynamic> map) {
    return CallSession(
      callId: map['call_id'] as String,
      patientId: map['patient_id'] as String,
      loopId: map['loop_id'] as String,
      callerId: map['caller_id'] as String,
      callerName: map['caller_name'] as String? ?? map['caller_id'] as String,
      callerRole: map['caller_role'] as String? ?? 'clinician',
      recipientId: map['recipient_id'] as String,
      recipientName:
          map['recipient_name'] as String? ?? map['recipient_id'] as String,
      recipientRole: map['recipient_role'] as String? ?? 'clinician',
      roomName: map['room_name'] as String,
      liveKitUrl: map['livekit_url'] as String,
      token: map['token'] as String,
      isIncoming: map['is_incoming'] as bool? ?? false,
      status: map['status'] as String? ?? 'ringing',
    );
  }
}
