import '../models/loop_enums.dart';
import '../models/patient_identity.dart';
import 'oravi_event.dart';

String _restoredLoopId(Map<String, dynamic> map) {
  final storedLoopId = map['loop_id'] as String?;
  if (storedLoopId?.trim().isNotEmpty == true) return storedLoopId!.trim();

  // Preserve malformed legacy events under a deterministic isolated thread id.
  // This keeps one incomplete row from blocking restoration of the whole ward.
  final eventId = map['event_id'] as String?;
  if (eventId == null || eventId.isEmpty) {
    throw const FormatException('A stored event is missing its event id.');
  }
  return 'recovered-$eventId';
}

// ==========================================
// 1. Patient Lifecycle Events (Appendix A)
// ==========================================

class PatientAdmittedEvent extends OraviEvent {
  static const String eventType = 'PatientAdmitted';

  final String wardId;
  final String bedNumber;
  final String patientInitials;
  final String? _legacyAdmissionNumber;
  final String? _legacyNameOrInitials;
  final int age;
  final String sex;
  final String shortAdmittingNote;
  final List<String> keyAlerts; // e.g., allergies

  PatientAdmittedEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.wardId,
    required this.bedNumber,
    required String patientInitials,
    required this.age,
    required this.sex,
    required this.shortAdmittingNote,
    this.keyAlerts = const [],
  }) : patientInitials = PatientIdentity.requireInitials(patientInitials),
       _legacyAdmissionNumber = null,
       _legacyNameOrInitials = null,
       super(type: eventType);

  PatientAdmittedEvent._legacy({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.wardId,
    required this.bedNumber,
    required String patientInitials,
    required this._legacyAdmissionNumber,
    required this._legacyNameOrInitials,
    required this.age,
    required this.sex,
    required this.shortAdmittingNote,
    this.keyAlerts = const [],
  }) : patientInitials = PatientIdentity.initialsFromLegacy(patientInitials),
       super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'ward_id': wardId,
      'bed_number': bedNumber,
      if (_legacyAdmissionNumber != null)
        'admission_number': _legacyAdmissionNumber,
      // Keep the existing wire key for compatibility. Its new value is initials only.
      'name_or_initials': _legacyNameOrInitials ?? patientInitials,
      'age': age,
      'sex': sex,
      'short_admitting_note': shortAdmittingNote,
      'key_alerts': keyAlerts,
    },
  };

  factory PatientAdmittedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return PatientAdmittedEvent._legacy(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      prevHash: map['prev_hash'],
      hash: map['hash'],
      wardId: payload['ward_id'],
      bedNumber: payload['bed_number'],
      patientInitials: PatientIdentity.initialsFromLegacy(
        (payload['patient_initials'] ?? payload['name_or_initials'] ?? '')
            .toString(),
      ),
      legacyAdmissionNumber: payload['admission_number']?.toString(),
      legacyNameOrInitials: payload['name_or_initials']?.toString(),
      age: payload['age'],
      sex: payload['sex'],
      shortAdmittingNote: payload['short_admitting_note'] ?? '',
      keyAlerts: List<String>.from(payload['key_alerts'] ?? []),
    );
  }
}

class PatientTransferredEvent extends OraviEvent {
  static const String eventType = 'PatientTransferred';

  final String fromWardId;
  final String toWardId;
  final String toBedNumber;

  PatientTransferredEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.fromWardId,
    required this.toWardId,
    required this.toBedNumber,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'from_ward_id': fromWardId,
      'to_ward_id': toWardId,
      'to_bed_number': toBedNumber,
    },
  };

  factory PatientTransferredEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return PatientTransferredEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      fromWardId: payload['from_ward_id'],
      toWardId: payload['to_ward_id'],
      toBedNumber: payload['to_bed_number'],
    );
  }
}

class PatientDischargedEvent extends OraviEvent {
  static const String eventType = 'PatientDischarged';

  final String dischargeDisposition;
  final String? unresolvedCarriedForwardNotes;

  PatientDischargedEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.dischargeDisposition,
    this.unresolvedCarriedForwardNotes,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'discharge_disposition': dischargeDisposition,
      'unresolved_carried_forward_notes': unresolvedCarriedForwardNotes,
    },
  };

  factory PatientDischargedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return PatientDischargedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      dischargeDisposition: payload['discharge_disposition'],
      unresolvedCarriedForwardNotes:
          payload['unresolved_carried_forward_notes'],
    );
  }
}

// ==========================================
// 2. Loop Lifecycle Events (Appendix A)
// ==========================================

class LoopOpenedEvent extends OraviEvent {
  static const String eventType = 'LoopOpened';

  final String title;
  final String description;
  final LoopType loopType;
  final LoopUrgency urgency;
  final String initialOwnerId;
  final String initialOwnerRole;
  final String?
  linkedLoopId; // If created from recurring/linked loop flow (FR-53)

  LoopOpenedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.title,
    required this.description,
    required this.loopType,
    required this.urgency,
    required this.initialOwnerId,
    required this.initialOwnerRole,
    this.linkedLoopId,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'title': title,
      'description': description,
      'loop_type': loopType.wireName,
      'urgency': urgency.wireName,
      'initial_owner_id': initialOwnerId,
      'initial_owner_role': initialOwnerRole,
      'linked_loop_id': linkedLoopId,
    },
  };

  factory LoopOpenedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    final eventId = map['event_id'] as String;
    final authorId = map['author_id'] as String;
    return LoopOpenedEvent(
      eventId: eventId,
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: authorId,
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      title: (payload['title'] as String?)?.trim().isNotEmpty == true
          ? (payload['title'] as String).trim()
          : 'Recovered medical issue',
      description: payload['description'] as String? ?? '',
      loopType: LoopType.fromString(
        payload['loop_type'] as String? ??
            LoopType.taskOrPendingResult.wireName,
      ),
      urgency: LoopUrgency.fromString(
        payload['urgency'] as String? ?? LoopUrgency.routine.wireName,
      ),
      initialOwnerId: payload['initial_owner_id'] as String? ?? authorId,
      initialOwnerRole: payload['initial_owner_role'] as String? ?? 'unknown',
      linkedLoopId: payload['linked_loop_id'],
    );
  }
}

class LoopAcknowledgedEvent extends OraviEvent {
  static const String eventType = 'LoopAcknowledged';

  LoopAcknowledgedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {},
  };

  factory LoopAcknowledgedEvent.fromMap(Map<String, dynamic> map) {
    return LoopAcknowledgedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
    );
  }
}

class LoopReadEvent extends OraviEvent {
  static const String eventType = 'LoopRead';

  LoopReadEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': const <String, dynamic>{},
  };

  factory LoopReadEvent.fromMap(Map<String, dynamic> map) {
    return LoopReadEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
    );
  }
}

class LoopUserAcknowledgedEvent extends OraviEvent {
  static const String eventType = 'LoopUserAcknowledged';

  LoopUserAcknowledgedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': const <String, dynamic>{},
  };

  factory LoopUserAcknowledgedEvent.fromMap(Map<String, dynamic> map) {
    return LoopUserAcknowledgedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
    );
  }
}

class LoopWorkStartedEvent extends OraviEvent {
  static const String eventType = 'LoopWorkStarted';

  LoopWorkStartedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {},
  };

  factory LoopWorkStartedEvent.fromMap(Map<String, dynamic> map) {
    return LoopWorkStartedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
    );
  }
}

class LoopOwnerChangedEvent extends OraviEvent {
  static const String eventType = 'LoopOwnerChanged';

  final String newOwnerId;
  final String newOwnerRole;
  final String transferReason;
  final String? handoffSessionId;
  final bool carryForward;

  LoopOwnerChangedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.newOwnerId,
    required this.newOwnerRole,
    required this.transferReason,
    this.handoffSessionId,
    this.carryForward = false,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'new_owner_id': newOwnerId,
      'new_owner_role': newOwnerRole,
      'transfer_reason': transferReason,
      if (handoffSessionId != null)
        'handoff_session_id': handoffSessionId,
      if (carryForward) 'carry_forward': true,
    },
  };

  factory LoopOwnerChangedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return LoopOwnerChangedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      newOwnerId: payload['new_owner_id'],
      newOwnerRole: payload['new_owner_role'],
      transferReason: payload['transfer_reason'] ?? '',
      handoffSessionId: payload['handoff_session_id'],
      carryForward: payload['carry_forward'] == true,
    );
  }
}

// ==========================================
// 3. Thread Content Events (Appendix A)
// ==========================================

class MessagePostedEvent extends OraviEvent {
  static const String eventType = 'MessagePosted';

  final String messageId;
  final String content;
  final String? quotedMessageId; // For contextual replies
  final List<String> roleMentions; // e.g. ['doctor_on_call']
  final List<String> mentionedStaffIds;

  MessagePostedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.messageId,
    required this.content,
    this.quotedMessageId,
    this.roleMentions = const [],
    this.mentionedStaffIds = const [],
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'message_id': messageId,
      'content': content,
      'quoted_message_id': quotedMessageId,
      'role_mentions': roleMentions,
      'mentioned_staff_ids': mentionedStaffIds,
    },
  };

  factory MessagePostedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return MessagePostedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      messageId: payload['message_id'],
      content: payload['content'],
      quotedMessageId: payload['quoted_message_id'],
      roleMentions: List<String>.from(payload['role_mentions'] ?? []),
      mentionedStaffIds: List<String>.from(
        payload['mentioned_staff_ids'] ?? [],
      ),
    );
  }
}

class MessageEditedEvent extends OraviEvent {
  static const String eventType = 'MessageEdited';

  final String messageId;
  final String previousContent;
  final String newContent;

  MessageEditedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.messageId,
    required this.previousContent,
    required this.newContent,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'message_id': messageId,
      'previous_content': previousContent,
      'new_content': newContent,
    },
  };

  factory MessageEditedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return MessageEditedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      messageId: payload['message_id'],
      previousContent: payload['previous_content'],
      newContent: payload['new_content'],
    );
  }
}

class CallLoggedEvent extends OraviEvent {
  static const String eventType = 'CallLogged';

  final String callId;
  final String callerId;
  final String callerRole;
  final String recipientId;
  final String recipientRole;
  final String outcomeNote; // PRD FR-54: Mandatory summary of verbal agreement
  final int durationSeconds;
  final String callStatus;

  CallLoggedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.callId,
    required this.callerId,
    required this.callerRole,
    required this.recipientId,
    required this.recipientRole,
    required this.outcomeNote,
    this.durationSeconds = 0,
    this.callStatus = 'completed',
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'call_id': callId,
      'caller_id': callerId,
      'caller_role': callerRole,
      'recipient_id': recipientId,
      'recipient_role': recipientRole,
      'outcome_note': outcomeNote,
      'duration_seconds': durationSeconds,
      'call_status': callStatus,
    },
  };

  factory CallLoggedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return CallLoggedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      callId: payload['call_id'],
      callerId: payload['caller_id'],
      callerRole: payload['caller_role'] ?? 'clinician',
      recipientId: payload['recipient_id'],
      recipientRole: payload['recipient_role'] ?? 'clinician',
      outcomeNote: payload['outcome_note'] ?? '',
      durationSeconds: payload['duration_seconds'] ?? 0,
      callStatus: payload['call_status'] ?? 'completed',
    );
  }
}

// ==========================================
// 4. Closure & Recurrence Events (Appendix A)
// ==========================================

class LoopClosedEvent extends OraviEvent {
  static const String eventType = 'LoopClosed';

  final ClosureReasonCode? reasonCode;
  final String? closureReason;
  final String? freeTextNote;
  final ClosureResolutionType resolutionType;

  LoopClosedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    this.reasonCode,
    this.closureReason,
    this.freeTextNote,
    required this.resolutionType,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      if (reasonCode != null) 'reason_code': reasonCode!.wireName,
      if (closureReason != null) 'closure_reason': closureReason,
      'free_text_note': freeTextNote,
      'resolution_type': resolutionType.wireName,
    },
  };

  factory LoopClosedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return LoopClosedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      reasonCode: payload['reason_code'] is String
          ? ClosureReasonCode.fromString(payload['reason_code'] as String)
          : null,
      closureReason: payload['closure_reason'] as String?,
      freeTextNote: payload['free_text_note'],
      resolutionType: ClosureResolutionType.fromString(
        payload['resolution_type'] as String? ?? 'resolved',
      ),
    );
  }
}

class LoopClosureConfirmedEvent extends OraviEvent {
  static const String eventType = 'LoopClosureConfirmed';

  final String confirmedByRole;

  LoopClosureConfirmedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.confirmedByRole,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {'confirmed_by_role': confirmedByRole},
  };

  factory LoopClosureConfirmedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return LoopClosureConfirmedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      confirmedByRole: payload['confirmed_by_role'],
    );
  }
}

class LoopReopenedEvent extends OraviEvent {
  static const String eventType = 'LoopReopened';

  final String reopenReason;

  LoopReopenedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.reopenReason,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {'reopen_reason': reopenReason},
  };

  factory LoopReopenedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return LoopReopenedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      reopenReason: payload['reopen_reason'],
    );
  }
}

class LoopLinkedEvent extends OraviEvent {
  static const String eventType = 'LoopLinked';

  final String targetLoopId;
  final String linkType; // e.g., 'recurrence', 'duplicate', 'related'

  LoopLinkedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.targetLoopId,
    required this.linkType,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {'target_loop_id': targetLoopId, 'link_type': linkType},
  };

  factory LoopLinkedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return LoopLinkedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      targetLoopId: payload['target_loop_id'],
      linkType: payload['link_type'],
    );
  }
}

// ==========================================
// 5. Shift Handoff Events (Appendix A)
// ==========================================

class HandoffStartedEvent extends OraviEvent {
  static const String eventType = 'HandoffStarted';

  final String handoffSessionId;
  final String wardId;
  final String outgoingNurseId;
  final String incomingNurseId;

  HandoffStartedEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.handoffSessionId,
    required this.wardId,
    required this.outgoingNurseId,
    required this.incomingNurseId,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'handoff_session_id': handoffSessionId,
      'ward_id': wardId,
      'outgoing_nurse_id': outgoingNurseId,
      'incoming_nurse_id': incomingNurseId,
    },
  };

  factory HandoffStartedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return HandoffStartedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      handoffSessionId: payload['handoff_session_id'],
      wardId: payload['ward_id'],
      outgoingNurseId: payload['outgoing_nurse_id'],
      incomingNurseId: payload['incoming_nurse_id'],
    );
  }
}

class HandoffBedAcceptedEvent extends OraviEvent {
  static const String eventType = 'HandoffBedAccepted';

  final String handoffSessionId;
  final String bedNumber;
  final bool nothingPendingConfirmed; // PRD FR-14: Silence is never ambiguous
  final List<String> transferredLoopIds;

  HandoffBedAcceptedEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.handoffSessionId,
    required this.bedNumber,
    required this.nothingPendingConfirmed,
    this.transferredLoopIds = const [],
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'handoff_session_id': handoffSessionId,
      'bed_number': bedNumber,
      'nothing_pending_confirmed': nothingPendingConfirmed,
      'transferred_loop_ids': transferredLoopIds,
    },
  };

  factory HandoffBedAcceptedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return HandoffBedAcceptedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      handoffSessionId: payload['handoff_session_id'],
      bedNumber: payload['bed_number'],
      nothingPendingConfirmed: payload['nothing_pending_confirmed'] ?? false,
      transferredLoopIds: List<String>.from(
        payload['transferred_loop_ids'] ?? [],
      ),
    );
  }
}

class HandoffCompletedEvent extends OraviEvent {
  static const String eventType = 'HandoffCompleted';

  final String handoffSessionId;
  final int totalBedsHandedOver;
  final int totalLoopsTransferred;

  HandoffCompletedEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.handoffSessionId,
    required this.totalBedsHandedOver,
    required this.totalLoopsTransferred,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'handoff_session_id': handoffSessionId,
      'total_beds_handed_over': totalBedsHandedOver,
      'total_loops_transferred': totalLoopsTransferred,
    },
  };

  factory HandoffCompletedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return HandoffCompletedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      handoffSessionId: payload['handoff_session_id'],
      totalBedsHandedOver: payload['total_beds_handed_over'],
      totalLoopsTransferred: payload['total_loops_transferred'],
    );
  }
}

// ==========================================
// 6. Escalations & Deterministic Flags (Appendix A)
// ==========================================

class EscalationRaisedEvent extends OraviEvent {
  static const String eventType = 'EscalationRaised';

  final String escalationId;
  final String targetRole;
  final String initialTargetUserId;
  final String escalationReason;
  final int timeoutMinutes;

  EscalationRaisedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.escalationId,
    required this.targetRole,
    required this.initialTargetUserId,
    required this.escalationReason,
    required this.timeoutMinutes,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'escalation_id': escalationId,
      'target_role': targetRole,
      'initial_target_user_id': initialTargetUserId,
      'escalation_reason': escalationReason,
      'timeout_minutes': timeoutMinutes,
    },
  };

  factory EscalationRaisedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return EscalationRaisedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      escalationId: payload['escalation_id'],
      targetRole: payload['target_role'],
      initialTargetUserId: payload['initial_target_user_id'],
      escalationReason: payload['escalation_reason'],
      timeoutMinutes: payload['timeout_minutes'],
    );
  }
}

class EscalationAcknowledgedEvent extends OraviEvent {
  static const String eventType = 'EscalationAcknowledged';

  final String escalationId;
  final String note;

  EscalationAcknowledgedEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.escalationId,
    this.note = '',
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {'escalation_id': escalationId, 'note': note},
  };

  factory EscalationAcknowledgedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return EscalationAcknowledgedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      escalationId: payload['escalation_id'],
      note: payload['note'] ?? '',
    );
  }
}

class EscalationPassedOnEvent extends OraviEvent {
  static const String eventType = 'EscalationPassedOn';

  final String escalationId;
  final String nextTargetUserId;
  final String nextTargetRole;
  final String reason;

  EscalationPassedOnEvent({
    super.eventId,
    required super.patientId,
    required String super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.escalationId,
    required this.nextTargetUserId,
    required this.nextTargetRole,
    required this.reason,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'escalation_id': escalationId,
      'next_target_user_id': nextTargetUserId,
      'next_target_role': nextTargetRole,
      'reason': reason,
    },
  };

  factory EscalationPassedOnEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return EscalationPassedOnEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      escalationId: payload['escalation_id'],
      nextTargetUserId: payload['next_target_user_id'],
      nextTargetRole: payload['next_target_role'],
      reason: payload['reason'],
    );
  }
}

class FlagRaisedEvent extends OraviEvent {
  static const String eventType = 'FlagRaised';

  final String flagId;
  final String ruleName;
  final String explanation; // PRD FR-27: Every flag states why it fired
  final String severity; // e.g. 'routine', 'warning', 'critical'

  FlagRaisedEvent({
    super.eventId,
    required super.patientId,
    super.loopId,
    required super.authorId, // System or clinician ID
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.flagId,
    required this.ruleName,
    required this.explanation,
    required this.severity,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {
      'flag_id': flagId,
      'rule_name': ruleName,
      'explanation': explanation,
      'severity': severity,
    },
  };

  factory FlagRaisedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return FlagRaisedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      flagId: payload['flag_id'],
      ruleName: payload['rule_name'],
      explanation: payload['explanation'],
      severity: payload['severity'],
    );
  }
}

class FlagDismissedEvent extends OraviEvent {
  static const String eventType = 'FlagDismissed';

  final String flagId;
  final String
  dismissalReason; // PRD FR-27: Snoozed/dismissed only with a logged reason

  FlagDismissedEvent({
    super.eventId,
    required super.patientId,
    super.loopId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.flagId,
    required this.dismissalReason,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'loop_id': loopId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'payload': {'flag_id': flagId, 'dismissal_reason': dismissalReason},
  };

  factory FlagDismissedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return FlagDismissedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      loopId: _restoredLoopId(map),
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      flagId: payload['flag_id'],
      dismissalReason: payload['dismissal_reason'],
    );
  }
}

// ==========================================
// 7. Milestone 8: Multi-Ward Digital Whiteboard & Shift Allocation Events
// ==========================================

class ShiftAllocationPublishedEvent extends OraviEvent {
  static const String eventType = 'ShiftAllocationPublished';

  final String allocationId;
  final String wardId;
  final String shiftType; // 'day' | 'night'
  final String date; // 'YYYY-MM-DD'
  final List<Map<String, dynamic>> bedAssignments;
  final Map<String, dynamic> supportRoster;

  ShiftAllocationPublishedEvent({
    super.eventId,
    required super.patientId, // Canonical 'ward-{wardId}' or system patient ID
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.allocationId,
    required this.wardId,
    required this.shiftType,
    required this.date,
    required this.bedAssignments,
    required this.supportRoster,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'prev_hash': prevHash,
    'hash': hash,
    'payload': {
      'allocation_id': allocationId,
      'ward_id': wardId,
      'shift_type': shiftType,
      'date': date,
      'bed_assignments': bedAssignments,
      'support_roster': supportRoster,
    },
  };

  factory ShiftAllocationPublishedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return ShiftAllocationPublishedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      allocationId: payload['allocation_id'],
      wardId: payload['ward_id'],
      shiftType: payload['shift_type'],
      date: payload['date'],
      bedAssignments: List<Map<String, dynamic>>.from(
        payload['bed_assignments'] ?? [],
      ),
      supportRoster: Map<String, dynamic>.from(payload['support_roster'] ?? {}),
    );
  }
}

class ShiftAllocationAcceptedEvent extends OraviEvent {
  static const String eventType = 'ShiftAllocationAccepted';

  final String allocationId;
  final String wardId;
  final String nurseId;
  final List<String> acceptedBeds;

  ShiftAllocationAcceptedEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.allocationId,
    required this.wardId,
    required this.nurseId,
    required this.acceptedBeds,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'prev_hash': prevHash,
    'hash': hash,
    'payload': {
      'allocation_id': allocationId,
      'ward_id': wardId,
      'nurse_id': nurseId,
      'accepted_beds': acceptedBeds,
    },
  };

  factory ShiftAllocationAcceptedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return ShiftAllocationAcceptedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      allocationId: payload['allocation_id'],
      wardId: payload['ward_id'],
      nurseId: payload['nurse_id'],
      acceptedBeds: List<String>.from(payload['accepted_beds'] ?? []),
    );
  }
}

class ShiftAllocationDisputedEvent extends OraviEvent {
  static const String eventType = 'ShiftAllocationDisputed';

  final String allocationId;
  final String wardId;
  final String nurseId;
  final String bedNumber;
  final String disputeReason;

  ShiftAllocationDisputedEvent({
    super.eventId,
    required super.patientId,
    required super.authorId,
    required super.deviceId,
    super.clientCreatedAt,
    super.serverSeq,
    super.serverReceivedAt,
    super.schemaVersion,
    super.prevHash,
    super.hash,
    required this.allocationId,
    required this.wardId,
    required this.nurseId,
    required this.bedNumber,
    required this.disputeReason,
  }) : super(type: eventType);

  @override
  Map<String, dynamic> toMap() => {
    'event_id': eventId,
    'type': type,
    'patient_id': patientId,
    'author_id': authorId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt.toIso8601String(),
    'server_seq': serverSeq,
    'server_received_at': serverReceivedAt?.toIso8601String(),
    'schema_version': schemaVersion,
    'prev_hash': prevHash,
    'hash': hash,
    'payload': {
      'allocation_id': allocationId,
      'ward_id': wardId,
      'nurse_id': nurseId,
      'bed_number': bedNumber,
      'dispute_reason': disputeReason,
    },
  };

  factory ShiftAllocationDisputedEvent.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'] as Map<String, dynamic>;
    return ShiftAllocationDisputedEvent(
      eventId: map['event_id'],
      patientId: map['patient_id'],
      authorId: map['author_id'],
      deviceId: map['device_id'],
      clientCreatedAt: DateTime.parse(map['client_created_at']),
      serverSeq: map['server_seq'],
      serverReceivedAt: map['server_received_at'] != null
          ? DateTime.parse(map['server_received_at'])
          : null,
      schemaVersion: map['schema_version'] ?? 1,
      allocationId: payload['allocation_id'],
      wardId: payload['ward_id'],
      nurseId: payload['nurse_id'],
      bedNumber: payload['bed_number'],
      disputeReason: payload['dispute_reason'],
    );
  }
}

/// Generic factory to deserialize any canonical event map into its specific type.
OraviEvent deserializeOraviEvent(Map<String, dynamic> map) {
  final type = map['type'] as String;
  switch (type) {
    case PatientAdmittedEvent.eventType:
      return PatientAdmittedEvent.fromMap(map);
    case PatientTransferredEvent.eventType:
      return PatientTransferredEvent.fromMap(map);
    case PatientDischargedEvent.eventType:
      return PatientDischargedEvent.fromMap(map);
    case LoopOpenedEvent.eventType:
      return LoopOpenedEvent.fromMap(map);
    case LoopAcknowledgedEvent.eventType:
      return LoopAcknowledgedEvent.fromMap(map);
    case LoopReadEvent.eventType:
      return LoopReadEvent.fromMap(map);
    case LoopUserAcknowledgedEvent.eventType:
      return LoopUserAcknowledgedEvent.fromMap(map);
    case LoopWorkStartedEvent.eventType:
      return LoopWorkStartedEvent.fromMap(map);
    case LoopOwnerChangedEvent.eventType:
      return LoopOwnerChangedEvent.fromMap(map);
    case MessagePostedEvent.eventType:
      return MessagePostedEvent.fromMap(map);
    case MessageEditedEvent.eventType:
      return MessageEditedEvent.fromMap(map);
    case CallLoggedEvent.eventType:
      return CallLoggedEvent.fromMap(map);
    case LoopClosedEvent.eventType:
      return LoopClosedEvent.fromMap(map);
    case LoopClosureConfirmedEvent.eventType:
      return LoopClosureConfirmedEvent.fromMap(map);
    case LoopReopenedEvent.eventType:
      return LoopReopenedEvent.fromMap(map);
    case LoopLinkedEvent.eventType:
      return LoopLinkedEvent.fromMap(map);
    case HandoffStartedEvent.eventType:
      return HandoffStartedEvent.fromMap(map);
    case HandoffBedAcceptedEvent.eventType:
      return HandoffBedAcceptedEvent.fromMap(map);
    case HandoffCompletedEvent.eventType:
      return HandoffCompletedEvent.fromMap(map);
    case EscalationRaisedEvent.eventType:
      return EscalationRaisedEvent.fromMap(map);
    case EscalationAcknowledgedEvent.eventType:
      return EscalationAcknowledgedEvent.fromMap(map);
    case EscalationPassedOnEvent.eventType:
      return EscalationPassedOnEvent.fromMap(map);
    case FlagRaisedEvent.eventType:
      return FlagRaisedEvent.fromMap(map);
    case FlagDismissedEvent.eventType:
      return FlagDismissedEvent.fromMap(map);
    case ShiftAllocationPublishedEvent.eventType:
      return ShiftAllocationPublishedEvent.fromMap(map);
    case ShiftAllocationAcceptedEvent.eventType:
      return ShiftAllocationAcceptedEvent.fromMap(map);
    case ShiftAllocationDisputedEvent.eventType:
      return ShiftAllocationDisputedEvent.fromMap(map);
    default:
      throw UnsupportedError('Unknown event type: $type');
  }
}
