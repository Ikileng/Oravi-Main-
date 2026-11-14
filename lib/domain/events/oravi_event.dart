import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Base class for all immutable domain events in Oravi.
///
/// Follows Technical Architecture v0.1 Section 4.1:
/// - Every state mutation in Oravi is an immutable event.
/// - [eventId] is generated on the client via UUIDv7 for idempotent retries.
/// - [clientCreatedAt] is the phone's clock, used for display only.
/// - [serverSeq] and [serverReceivedAt] are assigned by the server (authoritative for ordering).
abstract class OraviEvent extends Equatable {
  final String eventId;
  final String type;
  final String patientId;
  final String? loopId;
  final String authorId;
  final String deviceId;
  final DateTime clientCreatedAt;
  final int? serverSeq;
  final DateTime? serverReceivedAt;
  final int schemaVersion;
  final String? prevHash;
  final String? hash;

  OraviEvent({
    String? eventId,
    required this.type,
    required this.patientId,
    this.loopId,
    required this.authorId,
    required this.deviceId,
    DateTime? clientCreatedAt,
    this.serverSeq,
    this.serverReceivedAt,
    this.schemaVersion = 1,
    this.prevHash,
    this.hash,
  })  : eventId = eventId ?? const Uuid().v7(),
        clientCreatedAt = clientCreatedAt ?? DateTime.now().toUtc();

  /// Canonical serialization of the event payload for sync and state reduction.
  Map<String, dynamic> toMap();

  @override
  List<Object?> get props => [
        eventId,
        type,
        patientId,
        loopId,
        authorId,
        deviceId,
        clientCreatedAt,
        serverSeq,
        serverReceivedAt,
        schemaVersion,
      ];
}
