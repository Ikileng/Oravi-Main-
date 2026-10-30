// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LocalEventsTable extends LocalEvents
    with TableInfo<$LocalEventsTable, LocalEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loopIdMeta = const VerificationMeta('loopId');
  @override
  late final GeneratedColumn<String> loopId = GeneratedColumn<String>(
    'loop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorIdMeta = const VerificationMeta(
    'authorId',
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientCreatedAtMeta = const VerificationMeta(
    'clientCreatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientCreatedAt =
      GeneratedColumn<DateTime>(
        'client_created_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverReceivedAtMeta = const VerificationMeta(
    'serverReceivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverReceivedAt =
      GeneratedColumn<DateTime>(
        'server_received_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    patientId,
    loopId,
    eventType,
    authorId,
    deviceId,
    clientCreatedAt,
    serverSeq,
    serverReceivedAt,
    schemaVersion,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_patientIdMeta);
    }
    if (data.containsKey('loop_id')) {
      context.handle(
        _loopIdMeta,
        loopId.isAcceptableOrUnknown(data['loop_id']!, _loopIdMeta),
      );
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(
        _authorIdMeta,
        authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('client_created_at')) {
      context.handle(
        _clientCreatedAtMeta,
        clientCreatedAt.isAcceptableOrUnknown(
          data['client_created_at']!,
          _clientCreatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientCreatedAtMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    if (data.containsKey('server_received_at')) {
      context.handle(
        _serverReceivedAtMeta,
        serverReceivedAt.isAcceptableOrUnknown(
          data['server_received_at']!,
          _serverReceivedAtMeta,
        ),
      );
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  LocalEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalEvent(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      )!,
      loopId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loop_id'],
      ),
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      authorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      clientCreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_created_at'],
      )!,
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
      serverReceivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_received_at'],
      ),
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $LocalEventsTable createAlias(String alias) {
    return $LocalEventsTable(attachedDatabase, alias);
  }
}

class LocalEvent extends DataClass implements Insertable<LocalEvent> {
  final String eventId;
  final String patientId;
  final String? loopId;
  final String eventType;
  final String authorId;
  final String deviceId;
  final DateTime clientCreatedAt;
  final int? serverSeq;
  final DateTime? serverReceivedAt;
  final int schemaVersion;
  final String payloadJson;
  const LocalEvent({
    required this.eventId,
    required this.patientId,
    this.loopId,
    required this.eventType,
    required this.authorId,
    required this.deviceId,
    required this.clientCreatedAt,
    this.serverSeq,
    this.serverReceivedAt,
    required this.schemaVersion,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['patient_id'] = Variable<String>(patientId);
    if (!nullToAbsent || loopId != null) {
      map['loop_id'] = Variable<String>(loopId);
    }
    map['event_type'] = Variable<String>(eventType);
    map['author_id'] = Variable<String>(authorId);
    map['device_id'] = Variable<String>(deviceId);
    map['client_created_at'] = Variable<DateTime>(clientCreatedAt);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    if (!nullToAbsent || serverReceivedAt != null) {
      map['server_received_at'] = Variable<DateTime>(serverReceivedAt);
    }
    map['schema_version'] = Variable<int>(schemaVersion);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  LocalEventsCompanion toCompanion(bool nullToAbsent) {
    return LocalEventsCompanion(
      eventId: Value(eventId),
      patientId: Value(patientId),
      loopId: loopId == null && nullToAbsent
          ? const Value.absent()
          : Value(loopId),
      eventType: Value(eventType),
      authorId: Value(authorId),
      deviceId: Value(deviceId),
      clientCreatedAt: Value(clientCreatedAt),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
      serverReceivedAt: serverReceivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverReceivedAt),
      schemaVersion: Value(schemaVersion),
      payloadJson: Value(payloadJson),
    );
  }

  factory LocalEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalEvent(
      eventId: serializer.fromJson<String>(json['eventId']),
      patientId: serializer.fromJson<String>(json['patientId']),
      loopId: serializer.fromJson<String?>(json['loopId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      authorId: serializer.fromJson<String>(json['authorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      clientCreatedAt: serializer.fromJson<DateTime>(json['clientCreatedAt']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
      serverReceivedAt: serializer.fromJson<DateTime?>(
        json['serverReceivedAt'],
      ),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'patientId': serializer.toJson<String>(patientId),
      'loopId': serializer.toJson<String?>(loopId),
      'eventType': serializer.toJson<String>(eventType),
      'authorId': serializer.toJson<String>(authorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'clientCreatedAt': serializer.toJson<DateTime>(clientCreatedAt),
      'serverSeq': serializer.toJson<int?>(serverSeq),
      'serverReceivedAt': serializer.toJson<DateTime?>(serverReceivedAt),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  LocalEvent copyWith({
    String? eventId,
    String? patientId,
    Value<String?> loopId = const Value.absent(),
    String? eventType,
    String? authorId,
    String? deviceId,
    DateTime? clientCreatedAt,
    Value<int?> serverSeq = const Value.absent(),
    Value<DateTime?> serverReceivedAt = const Value.absent(),
    int? schemaVersion,
    String? payloadJson,
  }) => LocalEvent(
    eventId: eventId ?? this.eventId,
    patientId: patientId ?? this.patientId,
    loopId: loopId.present ? loopId.value : this.loopId,
    eventType: eventType ?? this.eventType,
    authorId: authorId ?? this.authorId,
    deviceId: deviceId ?? this.deviceId,
    clientCreatedAt: clientCreatedAt ?? this.clientCreatedAt,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
    serverReceivedAt: serverReceivedAt.present
        ? serverReceivedAt.value
        : this.serverReceivedAt,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  LocalEvent copyWithCompanion(LocalEventsCompanion data) {
    return LocalEvent(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
      loopId: data.loopId.present ? data.loopId.value : this.loopId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      clientCreatedAt: data.clientCreatedAt.present
          ? data.clientCreatedAt.value
          : this.clientCreatedAt,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
      serverReceivedAt: data.serverReceivedAt.present
          ? data.serverReceivedAt.value
          : this.serverReceivedAt,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalEvent(')
          ..write('eventId: $eventId, ')
          ..write('patientId: $patientId, ')
          ..write('loopId: $loopId, ')
          ..write('eventType: $eventType, ')
          ..write('authorId: $authorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientCreatedAt: $clientCreatedAt, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('serverReceivedAt: $serverReceivedAt, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    eventId,
    patientId,
    loopId,
    eventType,
    authorId,
    deviceId,
    clientCreatedAt,
    serverSeq,
    serverReceivedAt,
    schemaVersion,
    payloadJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalEvent &&
          other.eventId == this.eventId &&
          other.patientId == this.patientId &&
          other.loopId == this.loopId &&
          other.eventType == this.eventType &&
          other.authorId == this.authorId &&
          other.deviceId == this.deviceId &&
          other.clientCreatedAt == this.clientCreatedAt &&
          other.serverSeq == this.serverSeq &&
          other.serverReceivedAt == this.serverReceivedAt &&
          other.schemaVersion == this.schemaVersion &&
          other.payloadJson == this.payloadJson);
}

class LocalEventsCompanion extends UpdateCompanion<LocalEvent> {
  final Value<String> eventId;
  final Value<String> patientId;
  final Value<String?> loopId;
  final Value<String> eventType;
  final Value<String> authorId;
  final Value<String> deviceId;
  final Value<DateTime> clientCreatedAt;
  final Value<int?> serverSeq;
  final Value<DateTime?> serverReceivedAt;
  final Value<int> schemaVersion;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const LocalEventsCompanion({
    this.eventId = const Value.absent(),
    this.patientId = const Value.absent(),
    this.loopId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.authorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.clientCreatedAt = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.serverReceivedAt = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalEventsCompanion.insert({
    required String eventId,
    required String patientId,
    this.loopId = const Value.absent(),
    required String eventType,
    required String authorId,
    required String deviceId,
    required DateTime clientCreatedAt,
    this.serverSeq = const Value.absent(),
    this.serverReceivedAt = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    required String payloadJson,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       patientId = Value(patientId),
       eventType = Value(eventType),
       authorId = Value(authorId),
       deviceId = Value(deviceId),
       clientCreatedAt = Value(clientCreatedAt),
       payloadJson = Value(payloadJson);
  static Insertable<LocalEvent> custom({
    Expression<String>? eventId,
    Expression<String>? patientId,
    Expression<String>? loopId,
    Expression<String>? eventType,
    Expression<String>? authorId,
    Expression<String>? deviceId,
    Expression<DateTime>? clientCreatedAt,
    Expression<int>? serverSeq,
    Expression<DateTime>? serverReceivedAt,
    Expression<int>? schemaVersion,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (patientId != null) 'patient_id': patientId,
      if (loopId != null) 'loop_id': loopId,
      if (eventType != null) 'event_type': eventType,
      if (authorId != null) 'author_id': authorId,
      if (deviceId != null) 'device_id': deviceId,
      if (clientCreatedAt != null) 'client_created_at': clientCreatedAt,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (serverReceivedAt != null) 'server_received_at': serverReceivedAt,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalEventsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? patientId,
    Value<String?>? loopId,
    Value<String>? eventType,
    Value<String>? authorId,
    Value<String>? deviceId,
    Value<DateTime>? clientCreatedAt,
    Value<int?>? serverSeq,
    Value<DateTime?>? serverReceivedAt,
    Value<int>? schemaVersion,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return LocalEventsCompanion(
      eventId: eventId ?? this.eventId,
      patientId: patientId ?? this.patientId,
      loopId: loopId ?? this.loopId,
      eventType: eventType ?? this.eventType,
      authorId: authorId ?? this.authorId,
      deviceId: deviceId ?? this.deviceId,
      clientCreatedAt: clientCreatedAt ?? this.clientCreatedAt,
      serverSeq: serverSeq ?? this.serverSeq,
      serverReceivedAt: serverReceivedAt ?? this.serverReceivedAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (loopId.present) {
      map['loop_id'] = Variable<String>(loopId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (clientCreatedAt.present) {
      map['client_created_at'] = Variable<DateTime>(clientCreatedAt.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (serverReceivedAt.present) {
      map['server_received_at'] = Variable<DateTime>(serverReceivedAt.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalEventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('patientId: $patientId, ')
          ..write('loopId: $loopId, ')
          ..write('eventType: $eventType, ')
          ..write('authorId: $authorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientCreatedAt: $clientCreatedAt, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('serverReceivedAt: $serverReceivedAt, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventId,
    status,
    retryCount,
    lastAttemptAt,
    errorMessage,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final int id;
  final String eventId;
  final String status;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final String? errorMessage;
  final DateTime createdAt;
  const OutboxData({
    required this.id,
    required this.eventId,
    required this.status,
    required this.retryCount,
    this.lastAttemptAt,
    this.errorMessage,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['event_id'] = Variable<String>(eventId);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      eventId: Value(eventId),
      status: Value(status),
      retryCount: Value(retryCount),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      id: serializer.fromJson<int>(json['id']),
      eventId: serializer.fromJson<String>(json['eventId']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'eventId': serializer.toJson<String>(eventId),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxData copyWith({
    int? id,
    String? eventId,
    String? status,
    int? retryCount,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    DateTime? createdAt,
  }) => OutboxData(
    id: id ?? this.id,
    eventId: eventId ?? this.eventId,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      id: data.id.present ? data.id.value : this.id,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('id: $id, ')
          ..write('eventId: $eventId, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    eventId,
    status,
    retryCount,
    lastAttemptAt,
    errorMessage,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.id == this.id &&
          other.eventId == this.eventId &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.errorMessage == this.errorMessage &&
          other.createdAt == this.createdAt);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<int> id;
  final Value<String> eventId;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> errorMessage;
  final Value<DateTime> createdAt;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.eventId = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.id = const Value.absent(),
    required String eventId,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
    required DateTime createdAt,
  }) : eventId = Value(eventId),
       createdAt = Value(createdAt);
  static Insertable<OutboxData> custom({
    Expression<int>? id,
    Expression<String>? eventId,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? errorMessage,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventId != null) 'event_id': eventId,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (errorMessage != null) 'error_message': errorMessage,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? eventId,
    Value<String>? status,
    Value<int>? retryCount,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? errorMessage,
    Value<DateTime>? createdAt,
  }) {
    return OutboxCompanion(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('eventId: $eventId, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $LocalStaffTable extends LocalStaff
    with TableInfo<$LocalStaffTable, LocalStaffData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalStaffTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _staffIdMeta = const VerificationMeta(
    'staffId',
  );
  @override
  late final GeneratedColumn<String> staffId = GeneratedColumn<String>(
    'staff_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wardIdMeta = const VerificationMeta('wardId');
  @override
  late final GeneratedColumn<String> wardId = GeneratedColumn<String>(
    'ward_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('WARD-4B'),
  );
  static const VerificationMeta _pinMeta = const VerificationMeta('pin');
  @override
  late final GeneratedColumn<String> pin = GeneratedColumn<String>(
    'pin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _avatarColorMeta = const VerificationMeta(
    'avatarColor',
  );
  @override
  late final GeneratedColumn<String> avatarColor = GeneratedColumn<String>(
    'avatar_color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#0284C7'),
  );
  static const VerificationMeta _initialsMeta = const VerificationMeta(
    'initials',
  );
  @override
  late final GeneratedColumn<String> initials = GeneratedColumn<String>(
    'initials',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    staffId,
    name,
    role,
    wardId,
    pin,
    isActive,
    avatarColor,
    initials,
    email,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_staff';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalStaffData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('staff_id')) {
      context.handle(
        _staffIdMeta,
        staffId.isAcceptableOrUnknown(data['staff_id']!, _staffIdMeta),
      );
    } else if (isInserting) {
      context.missing(_staffIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('ward_id')) {
      context.handle(
        _wardIdMeta,
        wardId.isAcceptableOrUnknown(data['ward_id']!, _wardIdMeta),
      );
    }
    if (data.containsKey('pin')) {
      context.handle(
        _pinMeta,
        pin.isAcceptableOrUnknown(data['pin']!, _pinMeta),
      );
    } else if (isInserting) {
      context.missing(_pinMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('avatar_color')) {
      context.handle(
        _avatarColorMeta,
        avatarColor.isAcceptableOrUnknown(
          data['avatar_color']!,
          _avatarColorMeta,
        ),
      );
    }
    if (data.containsKey('initials')) {
      context.handle(
        _initialsMeta,
        initials.isAcceptableOrUnknown(data['initials']!, _initialsMeta),
      );
    } else if (isInserting) {
      context.missing(_initialsMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {staffId};
  @override
  LocalStaffData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalStaffData(
      staffId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}staff_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      wardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ward_id'],
      )!,
      pin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      avatarColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_color'],
      )!,
      initials: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}initials'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
    );
  }

  @override
  $LocalStaffTable createAlias(String alias) {
    return $LocalStaffTable(attachedDatabase, alias);
  }
}

class LocalStaffData extends DataClass implements Insertable<LocalStaffData> {
  final String staffId;
  final String name;
  final String role;
  final String wardId;
  final String pin;
  final bool isActive;
  final String avatarColor;
  final String initials;
  final String? email;
  const LocalStaffData({
    required this.staffId,
    required this.name,
    required this.role,
    required this.wardId,
    required this.pin,
    required this.isActive,
    required this.avatarColor,
    required this.initials,
    this.email,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['staff_id'] = Variable<String>(staffId);
    map['name'] = Variable<String>(name);
    map['role'] = Variable<String>(role);
    map['ward_id'] = Variable<String>(wardId);
    map['pin'] = Variable<String>(pin);
    map['is_active'] = Variable<bool>(isActive);
    map['avatar_color'] = Variable<String>(avatarColor);
    map['initials'] = Variable<String>(initials);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    return map;
  }

  LocalStaffCompanion toCompanion(bool nullToAbsent) {
    return LocalStaffCompanion(
      staffId: Value(staffId),
      name: Value(name),
      role: Value(role),
      wardId: Value(wardId),
      pin: Value(pin),
      isActive: Value(isActive),
      avatarColor: Value(avatarColor),
      initials: Value(initials),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
    );
  }

  factory LocalStaffData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalStaffData(
      staffId: serializer.fromJson<String>(json['staffId']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String>(json['role']),
      wardId: serializer.fromJson<String>(json['wardId']),
      pin: serializer.fromJson<String>(json['pin']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      avatarColor: serializer.fromJson<String>(json['avatarColor']),
      initials: serializer.fromJson<String>(json['initials']),
      email: serializer.fromJson<String?>(json['email']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'staffId': serializer.toJson<String>(staffId),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String>(role),
      'wardId': serializer.toJson<String>(wardId),
      'pin': serializer.toJson<String>(pin),
      'isActive': serializer.toJson<bool>(isActive),
      'avatarColor': serializer.toJson<String>(avatarColor),
      'initials': serializer.toJson<String>(initials),
      'email': serializer.toJson<String?>(email),
    };
  }

  LocalStaffData copyWith({
    String? staffId,
    String? name,
    String? role,
    String? wardId,
    String? pin,
    bool? isActive,
    String? avatarColor,
    String? initials,
    Value<String?> email = const Value.absent(),
  }) => LocalStaffData(
    staffId: staffId ?? this.staffId,
    name: name ?? this.name,
    role: role ?? this.role,
    wardId: wardId ?? this.wardId,
    pin: pin ?? this.pin,
    isActive: isActive ?? this.isActive,
    avatarColor: avatarColor ?? this.avatarColor,
    initials: initials ?? this.initials,
    email: email.present ? email.value : this.email,
  );
  LocalStaffData copyWithCompanion(LocalStaffCompanion data) {
    return LocalStaffData(
      staffId: data.staffId.present ? data.staffId.value : this.staffId,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      wardId: data.wardId.present ? data.wardId.value : this.wardId,
      pin: data.pin.present ? data.pin.value : this.pin,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      avatarColor: data.avatarColor.present
          ? data.avatarColor.value
          : this.avatarColor,
      initials: data.initials.present ? data.initials.value : this.initials,
      email: data.email.present ? data.email.value : this.email,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalStaffData(')
          ..write('staffId: $staffId, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('wardId: $wardId, ')
          ..write('pin: $pin, ')
          ..write('isActive: $isActive, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('initials: $initials, ')
          ..write('email: $email')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    staffId,
    name,
    role,
    wardId,
    pin,
    isActive,
    avatarColor,
    initials,
    email,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalStaffData &&
          other.staffId == this.staffId &&
          other.name == this.name &&
          other.role == this.role &&
          other.wardId == this.wardId &&
          other.pin == this.pin &&
          other.isActive == this.isActive &&
          other.avatarColor == this.avatarColor &&
          other.initials == this.initials &&
          other.email == this.email);
}

class LocalStaffCompanion extends UpdateCompanion<LocalStaffData> {
  final Value<String> staffId;
  final Value<String> name;
  final Value<String> role;
  final Value<String> wardId;
  final Value<String> pin;
  final Value<bool> isActive;
  final Value<String> avatarColor;
  final Value<String> initials;
  final Value<String?> email;
  final Value<int> rowid;
  const LocalStaffCompanion({
    this.staffId = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.wardId = const Value.absent(),
    this.pin = const Value.absent(),
    this.isActive = const Value.absent(),
    this.avatarColor = const Value.absent(),
    this.initials = const Value.absent(),
    this.email = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalStaffCompanion.insert({
    required String staffId,
    required String name,
    required String role,
    this.wardId = const Value.absent(),
    required String pin,
    this.isActive = const Value.absent(),
    this.avatarColor = const Value.absent(),
    required String initials,
    this.email = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : staffId = Value(staffId),
       name = Value(name),
       role = Value(role),
       pin = Value(pin),
       initials = Value(initials);
  static Insertable<LocalStaffData> custom({
    Expression<String>? staffId,
    Expression<String>? name,
    Expression<String>? role,
    Expression<String>? wardId,
    Expression<String>? pin,
    Expression<bool>? isActive,
    Expression<String>? avatarColor,
    Expression<String>? initials,
    Expression<String>? email,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (staffId != null) 'staff_id': staffId,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (wardId != null) 'ward_id': wardId,
      if (pin != null) 'pin': pin,
      if (isActive != null) 'is_active': isActive,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (initials != null) 'initials': initials,
      if (email != null) 'email': email,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalStaffCompanion copyWith({
    Value<String>? staffId,
    Value<String>? name,
    Value<String>? role,
    Value<String>? wardId,
    Value<String>? pin,
    Value<bool>? isActive,
    Value<String>? avatarColor,
    Value<String>? initials,
    Value<String?>? email,
    Value<int>? rowid,
  }) {
    return LocalStaffCompanion(
      staffId: staffId ?? this.staffId,
      name: name ?? this.name,
      role: role ?? this.role,
      wardId: wardId ?? this.wardId,
      pin: pin ?? this.pin,
      isActive: isActive ?? this.isActive,
      avatarColor: avatarColor ?? this.avatarColor,
      initials: initials ?? this.initials,
      email: email ?? this.email,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (staffId.present) {
      map['staff_id'] = Variable<String>(staffId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (wardId.present) {
      map['ward_id'] = Variable<String>(wardId.value);
    }
    if (pin.present) {
      map['pin'] = Variable<String>(pin.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (avatarColor.present) {
      map['avatar_color'] = Variable<String>(avatarColor.value);
    }
    if (initials.present) {
      map['initials'] = Variable<String>(initials.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalStaffCompanion(')
          ..write('staffId: $staffId, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('wardId: $wardId, ')
          ..write('pin: $pin, ')
          ..write('isActive: $isActive, ')
          ..write('avatarColor: $avatarColor, ')
          ..write('initials: $initials, ')
          ..write('email: $email, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalWhiteboardAssignmentsTable extends LocalWhiteboardAssignments
    with
        TableInfo<$LocalWhiteboardAssignmentsTable, LocalWhiteboardAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalWhiteboardAssignmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bedNumberMeta = const VerificationMeta(
    'bedNumber',
  );
  @override
  late final GeneratedColumn<String> bedNumber = GeneratedColumn<String>(
    'bed_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patientNameMeta = const VerificationMeta(
    'patientName',
  );
  @override
  late final GeneratedColumn<String> patientName = GeneratedColumn<String>(
    'patient_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ageGenderMeta = const VerificationMeta(
    'ageGender',
  );
  @override
  late final GeneratedColumn<String> ageGender = GeneratedColumn<String>(
    'age_gender',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _diagnosisMeta = const VerificationMeta(
    'diagnosis',
  );
  @override
  late final GeneratedColumn<String> diagnosis = GeneratedColumn<String>(
    'diagnosis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assignedNurseMeta = const VerificationMeta(
    'assignedNurse',
  );
  @override
  late final GeneratedColumn<String> assignedNurse = GeneratedColumn<String>(
    'assigned_nurse',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bayMeta = const VerificationMeta('bay');
  @override
  late final GeneratedColumn<String> bay = GeneratedColumn<String>(
    'bay',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shiftDateMeta = const VerificationMeta(
    'shiftDate',
  );
  @override
  late final GeneratedColumn<String> shiftDate = GeneratedColumn<String>(
    'shift_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shiftTypeMeta = const VerificationMeta(
    'shiftType',
  );
  @override
  late final GeneratedColumn<String> shiftType = GeneratedColumn<String>(
    'shift_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bedNumber,
    patientName,
    ageGender,
    diagnosis,
    assignedNurse,
    bay,
    shiftDate,
    shiftType,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_whiteboard_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalWhiteboardAssignment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bed_number')) {
      context.handle(
        _bedNumberMeta,
        bedNumber.isAcceptableOrUnknown(data['bed_number']!, _bedNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_bedNumberMeta);
    }
    if (data.containsKey('patient_name')) {
      context.handle(
        _patientNameMeta,
        patientName.isAcceptableOrUnknown(
          data['patient_name']!,
          _patientNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_patientNameMeta);
    }
    if (data.containsKey('age_gender')) {
      context.handle(
        _ageGenderMeta,
        ageGender.isAcceptableOrUnknown(data['age_gender']!, _ageGenderMeta),
      );
    }
    if (data.containsKey('diagnosis')) {
      context.handle(
        _diagnosisMeta,
        diagnosis.isAcceptableOrUnknown(data['diagnosis']!, _diagnosisMeta),
      );
    }
    if (data.containsKey('assigned_nurse')) {
      context.handle(
        _assignedNurseMeta,
        assignedNurse.isAcceptableOrUnknown(
          data['assigned_nurse']!,
          _assignedNurseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignedNurseMeta);
    }
    if (data.containsKey('bay')) {
      context.handle(
        _bayMeta,
        bay.isAcceptableOrUnknown(data['bay']!, _bayMeta),
      );
    } else if (isInserting) {
      context.missing(_bayMeta);
    }
    if (data.containsKey('shift_date')) {
      context.handle(
        _shiftDateMeta,
        shiftDate.isAcceptableOrUnknown(data['shift_date']!, _shiftDateMeta),
      );
    } else if (isInserting) {
      context.missing(_shiftDateMeta);
    }
    if (data.containsKey('shift_type')) {
      context.handle(
        _shiftTypeMeta,
        shiftType.isAcceptableOrUnknown(data['shift_type']!, _shiftTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_shiftTypeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bedNumber, shiftDate, shiftType};
  @override
  LocalWhiteboardAssignment map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalWhiteboardAssignment(
      bedNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bed_number'],
      )!,
      patientName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_name'],
      )!,
      ageGender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age_gender'],
      ),
      diagnosis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diagnosis'],
      ),
      assignedNurse: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assigned_nurse'],
      )!,
      bay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bay'],
      )!,
      shiftDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shift_date'],
      )!,
      shiftType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shift_type'],
      )!,
    );
  }

  @override
  $LocalWhiteboardAssignmentsTable createAlias(String alias) {
    return $LocalWhiteboardAssignmentsTable(attachedDatabase, alias);
  }
}

class LocalWhiteboardAssignment extends DataClass
    implements Insertable<LocalWhiteboardAssignment> {
  final String bedNumber;
  final String patientName;
  final String? ageGender;
  final String? diagnosis;
  final String assignedNurse;
  final String bay;
  final String shiftDate;
  final String shiftType;
  const LocalWhiteboardAssignment({
    required this.bedNumber,
    required this.patientName,
    this.ageGender,
    this.diagnosis,
    required this.assignedNurse,
    required this.bay,
    required this.shiftDate,
    required this.shiftType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bed_number'] = Variable<String>(bedNumber);
    map['patient_name'] = Variable<String>(patientName);
    if (!nullToAbsent || ageGender != null) {
      map['age_gender'] = Variable<String>(ageGender);
    }
    if (!nullToAbsent || diagnosis != null) {
      map['diagnosis'] = Variable<String>(diagnosis);
    }
    map['assigned_nurse'] = Variable<String>(assignedNurse);
    map['bay'] = Variable<String>(bay);
    map['shift_date'] = Variable<String>(shiftDate);
    map['shift_type'] = Variable<String>(shiftType);
    return map;
  }

  LocalWhiteboardAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return LocalWhiteboardAssignmentsCompanion(
      bedNumber: Value(bedNumber),
      patientName: Value(patientName),
      ageGender: ageGender == null && nullToAbsent
          ? const Value.absent()
          : Value(ageGender),
      diagnosis: diagnosis == null && nullToAbsent
          ? const Value.absent()
          : Value(diagnosis),
      assignedNurse: Value(assignedNurse),
      bay: Value(bay),
      shiftDate: Value(shiftDate),
      shiftType: Value(shiftType),
    );
  }

  factory LocalWhiteboardAssignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalWhiteboardAssignment(
      bedNumber: serializer.fromJson<String>(json['bedNumber']),
      patientName: serializer.fromJson<String>(json['patientName']),
      ageGender: serializer.fromJson<String?>(json['ageGender']),
      diagnosis: serializer.fromJson<String?>(json['diagnosis']),
      assignedNurse: serializer.fromJson<String>(json['assignedNurse']),
      bay: serializer.fromJson<String>(json['bay']),
      shiftDate: serializer.fromJson<String>(json['shiftDate']),
      shiftType: serializer.fromJson<String>(json['shiftType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bedNumber': serializer.toJson<String>(bedNumber),
      'patientName': serializer.toJson<String>(patientName),
      'ageGender': serializer.toJson<String?>(ageGender),
      'diagnosis': serializer.toJson<String?>(diagnosis),
      'assignedNurse': serializer.toJson<String>(assignedNurse),
      'bay': serializer.toJson<String>(bay),
      'shiftDate': serializer.toJson<String>(shiftDate),
      'shiftType': serializer.toJson<String>(shiftType),
    };
  }

  LocalWhiteboardAssignment copyWith({
    String? bedNumber,
    String? patientName,
    Value<String?> ageGender = const Value.absent(),
    Value<String?> diagnosis = const Value.absent(),
    String? assignedNurse,
    String? bay,
    String? shiftDate,
    String? shiftType,
  }) => LocalWhiteboardAssignment(
    bedNumber: bedNumber ?? this.bedNumber,
    patientName: patientName ?? this.patientName,
    ageGender: ageGender.present ? ageGender.value : this.ageGender,
    diagnosis: diagnosis.present ? diagnosis.value : this.diagnosis,
    assignedNurse: assignedNurse ?? this.assignedNurse,
    bay: bay ?? this.bay,
    shiftDate: shiftDate ?? this.shiftDate,
    shiftType: shiftType ?? this.shiftType,
  );
  LocalWhiteboardAssignment copyWithCompanion(
    LocalWhiteboardAssignmentsCompanion data,
  ) {
    return LocalWhiteboardAssignment(
      bedNumber: data.bedNumber.present ? data.bedNumber.value : this.bedNumber,
      patientName: data.patientName.present
          ? data.patientName.value
          : this.patientName,
      ageGender: data.ageGender.present ? data.ageGender.value : this.ageGender,
      diagnosis: data.diagnosis.present ? data.diagnosis.value : this.diagnosis,
      assignedNurse: data.assignedNurse.present
          ? data.assignedNurse.value
          : this.assignedNurse,
      bay: data.bay.present ? data.bay.value : this.bay,
      shiftDate: data.shiftDate.present ? data.shiftDate.value : this.shiftDate,
      shiftType: data.shiftType.present ? data.shiftType.value : this.shiftType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalWhiteboardAssignment(')
          ..write('bedNumber: $bedNumber, ')
          ..write('patientName: $patientName, ')
          ..write('ageGender: $ageGender, ')
          ..write('diagnosis: $diagnosis, ')
          ..write('assignedNurse: $assignedNurse, ')
          ..write('bay: $bay, ')
          ..write('shiftDate: $shiftDate, ')
          ..write('shiftType: $shiftType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bedNumber,
    patientName,
    ageGender,
    diagnosis,
    assignedNurse,
    bay,
    shiftDate,
    shiftType,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalWhiteboardAssignment &&
          other.bedNumber == this.bedNumber &&
          other.patientName == this.patientName &&
          other.ageGender == this.ageGender &&
          other.diagnosis == this.diagnosis &&
          other.assignedNurse == this.assignedNurse &&
          other.bay == this.bay &&
          other.shiftDate == this.shiftDate &&
          other.shiftType == this.shiftType);
}

class LocalWhiteboardAssignmentsCompanion
    extends UpdateCompanion<LocalWhiteboardAssignment> {
  final Value<String> bedNumber;
  final Value<String> patientName;
  final Value<String?> ageGender;
  final Value<String?> diagnosis;
  final Value<String> assignedNurse;
  final Value<String> bay;
  final Value<String> shiftDate;
  final Value<String> shiftType;
  final Value<int> rowid;
  const LocalWhiteboardAssignmentsCompanion({
    this.bedNumber = const Value.absent(),
    this.patientName = const Value.absent(),
    this.ageGender = const Value.absent(),
    this.diagnosis = const Value.absent(),
    this.assignedNurse = const Value.absent(),
    this.bay = const Value.absent(),
    this.shiftDate = const Value.absent(),
    this.shiftType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalWhiteboardAssignmentsCompanion.insert({
    required String bedNumber,
    required String patientName,
    this.ageGender = const Value.absent(),
    this.diagnosis = const Value.absent(),
    required String assignedNurse,
    required String bay,
    required String shiftDate,
    required String shiftType,
    this.rowid = const Value.absent(),
  }) : bedNumber = Value(bedNumber),
       patientName = Value(patientName),
       assignedNurse = Value(assignedNurse),
       bay = Value(bay),
       shiftDate = Value(shiftDate),
       shiftType = Value(shiftType);
  static Insertable<LocalWhiteboardAssignment> custom({
    Expression<String>? bedNumber,
    Expression<String>? patientName,
    Expression<String>? ageGender,
    Expression<String>? diagnosis,
    Expression<String>? assignedNurse,
    Expression<String>? bay,
    Expression<String>? shiftDate,
    Expression<String>? shiftType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bedNumber != null) 'bed_number': bedNumber,
      if (patientName != null) 'patient_name': patientName,
      if (ageGender != null) 'age_gender': ageGender,
      if (diagnosis != null) 'diagnosis': diagnosis,
      if (assignedNurse != null) 'assigned_nurse': assignedNurse,
      if (bay != null) 'bay': bay,
      if (shiftDate != null) 'shift_date': shiftDate,
      if (shiftType != null) 'shift_type': shiftType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalWhiteboardAssignmentsCompanion copyWith({
    Value<String>? bedNumber,
    Value<String>? patientName,
    Value<String?>? ageGender,
    Value<String?>? diagnosis,
    Value<String>? assignedNurse,
    Value<String>? bay,
    Value<String>? shiftDate,
    Value<String>? shiftType,
    Value<int>? rowid,
  }) {
    return LocalWhiteboardAssignmentsCompanion(
      bedNumber: bedNumber ?? this.bedNumber,
      patientName: patientName ?? this.patientName,
      ageGender: ageGender ?? this.ageGender,
      diagnosis: diagnosis ?? this.diagnosis,
      assignedNurse: assignedNurse ?? this.assignedNurse,
      bay: bay ?? this.bay,
      shiftDate: shiftDate ?? this.shiftDate,
      shiftType: shiftType ?? this.shiftType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bedNumber.present) {
      map['bed_number'] = Variable<String>(bedNumber.value);
    }
    if (patientName.present) {
      map['patient_name'] = Variable<String>(patientName.value);
    }
    if (ageGender.present) {
      map['age_gender'] = Variable<String>(ageGender.value);
    }
    if (diagnosis.present) {
      map['diagnosis'] = Variable<String>(diagnosis.value);
    }
    if (assignedNurse.present) {
      map['assigned_nurse'] = Variable<String>(assignedNurse.value);
    }
    if (bay.present) {
      map['bay'] = Variable<String>(bay.value);
    }
    if (shiftDate.present) {
      map['shift_date'] = Variable<String>(shiftDate.value);
    }
    if (shiftType.present) {
      map['shift_type'] = Variable<String>(shiftType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalWhiteboardAssignmentsCompanion(')
          ..write('bedNumber: $bedNumber, ')
          ..write('patientName: $patientName, ')
          ..write('ageGender: $ageGender, ')
          ..write('diagnosis: $diagnosis, ')
          ..write('assignedNurse: $assignedNurse, ')
          ..write('bay: $bay, ')
          ..write('shiftDate: $shiftDate, ')
          ..write('shiftType: $shiftType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSupportRostersTable extends LocalSupportRosters
    with TableInfo<$LocalSupportRostersTable, LocalSupportRoster> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSupportRostersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wardIdMeta = const VerificationMeta('wardId');
  @override
  late final GeneratedColumn<String> wardId = GeneratedColumn<String>(
    'ward_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shiftDateMeta = const VerificationMeta(
    'shiftDate',
  );
  @override
  late final GeneratedColumn<String> shiftDate = GeneratedColumn<String>(
    'shift_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shiftTypeMeta = const VerificationMeta(
    'shiftType',
  );
  @override
  late final GeneratedColumn<String> shiftType = GeneratedColumn<String>(
    'shift_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inChargeNameMeta = const VerificationMeta(
    'inChargeName',
  );
  @override
  late final GeneratedColumn<String> inChargeName = GeneratedColumn<String>(
    'in_charge_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inChargePhoneMeta = const VerificationMeta(
    'inChargePhone',
  );
  @override
  late final GeneratedColumn<String> inChargePhone = GeneratedColumn<String>(
    'in_charge_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inChargeRoleMeta = const VerificationMeta(
    'inChargeRole',
  );
  @override
  late final GeneratedColumn<String> inChargeRole = GeneratedColumn<String>(
    'in_charge_role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _floatNurseNameMeta = const VerificationMeta(
    'floatNurseName',
  );
  @override
  late final GeneratedColumn<String> floatNurseName = GeneratedColumn<String>(
    'float_nurse_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _floatNursePhoneMeta = const VerificationMeta(
    'floatNursePhone',
  );
  @override
  late final GeneratedColumn<String> floatNursePhone = GeneratedColumn<String>(
    'float_nurse_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _floatNurseRoleMeta = const VerificationMeta(
    'floatNurseRole',
  );
  @override
  late final GeneratedColumn<String> floatNurseRole = GeneratedColumn<String>(
    'float_nurse_role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hcasJsonMeta = const VerificationMeta(
    'hcasJson',
  );
  @override
  late final GeneratedColumn<String> hcasJson = GeneratedColumn<String>(
    'hcas_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doctorsJsonMeta = const VerificationMeta(
    'doctorsJson',
  );
  @override
  late final GeneratedColumn<String> doctorsJson = GeneratedColumn<String>(
    'doctors_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    wardId,
    shiftDate,
    shiftType,
    inChargeName,
    inChargePhone,
    inChargeRole,
    floatNurseName,
    floatNursePhone,
    floatNurseRole,
    hcasJson,
    doctorsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_support_rosters';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSupportRoster> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ward_id')) {
      context.handle(
        _wardIdMeta,
        wardId.isAcceptableOrUnknown(data['ward_id']!, _wardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wardIdMeta);
    }
    if (data.containsKey('shift_date')) {
      context.handle(
        _shiftDateMeta,
        shiftDate.isAcceptableOrUnknown(data['shift_date']!, _shiftDateMeta),
      );
    } else if (isInserting) {
      context.missing(_shiftDateMeta);
    }
    if (data.containsKey('shift_type')) {
      context.handle(
        _shiftTypeMeta,
        shiftType.isAcceptableOrUnknown(data['shift_type']!, _shiftTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_shiftTypeMeta);
    }
    if (data.containsKey('in_charge_name')) {
      context.handle(
        _inChargeNameMeta,
        inChargeName.isAcceptableOrUnknown(
          data['in_charge_name']!,
          _inChargeNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inChargeNameMeta);
    }
    if (data.containsKey('in_charge_phone')) {
      context.handle(
        _inChargePhoneMeta,
        inChargePhone.isAcceptableOrUnknown(
          data['in_charge_phone']!,
          _inChargePhoneMeta,
        ),
      );
    }
    if (data.containsKey('in_charge_role')) {
      context.handle(
        _inChargeRoleMeta,
        inChargeRole.isAcceptableOrUnknown(
          data['in_charge_role']!,
          _inChargeRoleMeta,
        ),
      );
    }
    if (data.containsKey('float_nurse_name')) {
      context.handle(
        _floatNurseNameMeta,
        floatNurseName.isAcceptableOrUnknown(
          data['float_nurse_name']!,
          _floatNurseNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_floatNurseNameMeta);
    }
    if (data.containsKey('float_nurse_phone')) {
      context.handle(
        _floatNursePhoneMeta,
        floatNursePhone.isAcceptableOrUnknown(
          data['float_nurse_phone']!,
          _floatNursePhoneMeta,
        ),
      );
    }
    if (data.containsKey('float_nurse_role')) {
      context.handle(
        _floatNurseRoleMeta,
        floatNurseRole.isAcceptableOrUnknown(
          data['float_nurse_role']!,
          _floatNurseRoleMeta,
        ),
      );
    }
    if (data.containsKey('hcas_json')) {
      context.handle(
        _hcasJsonMeta,
        hcasJson.isAcceptableOrUnknown(data['hcas_json']!, _hcasJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_hcasJsonMeta);
    }
    if (data.containsKey('doctors_json')) {
      context.handle(
        _doctorsJsonMeta,
        doctorsJson.isAcceptableOrUnknown(
          data['doctors_json']!,
          _doctorsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_doctorsJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wardId, shiftDate, shiftType};
  @override
  LocalSupportRoster map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSupportRoster(
      wardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ward_id'],
      )!,
      shiftDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shift_date'],
      )!,
      shiftType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shift_type'],
      )!,
      inChargeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}in_charge_name'],
      )!,
      inChargePhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}in_charge_phone'],
      ),
      inChargeRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}in_charge_role'],
      ),
      floatNurseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}float_nurse_name'],
      )!,
      floatNursePhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}float_nurse_phone'],
      ),
      floatNurseRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}float_nurse_role'],
      ),
      hcasJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hcas_json'],
      )!,
      doctorsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doctors_json'],
      )!,
    );
  }

  @override
  $LocalSupportRostersTable createAlias(String alias) {
    return $LocalSupportRostersTable(attachedDatabase, alias);
  }
}

class LocalSupportRoster extends DataClass
    implements Insertable<LocalSupportRoster> {
  final String wardId;
  final String shiftDate;
  final String shiftType;
  final String inChargeName;
  final String? inChargePhone;
  final String? inChargeRole;
  final String floatNurseName;
  final String? floatNursePhone;
  final String? floatNurseRole;
  final String hcasJson;
  final String doctorsJson;
  const LocalSupportRoster({
    required this.wardId,
    required this.shiftDate,
    required this.shiftType,
    required this.inChargeName,
    this.inChargePhone,
    this.inChargeRole,
    required this.floatNurseName,
    this.floatNursePhone,
    this.floatNurseRole,
    required this.hcasJson,
    required this.doctorsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ward_id'] = Variable<String>(wardId);
    map['shift_date'] = Variable<String>(shiftDate);
    map['shift_type'] = Variable<String>(shiftType);
    map['in_charge_name'] = Variable<String>(inChargeName);
    if (!nullToAbsent || inChargePhone != null) {
      map['in_charge_phone'] = Variable<String>(inChargePhone);
    }
    if (!nullToAbsent || inChargeRole != null) {
      map['in_charge_role'] = Variable<String>(inChargeRole);
    }
    map['float_nurse_name'] = Variable<String>(floatNurseName);
    if (!nullToAbsent || floatNursePhone != null) {
      map['float_nurse_phone'] = Variable<String>(floatNursePhone);
    }
    if (!nullToAbsent || floatNurseRole != null) {
      map['float_nurse_role'] = Variable<String>(floatNurseRole);
    }
    map['hcas_json'] = Variable<String>(hcasJson);
    map['doctors_json'] = Variable<String>(doctorsJson);
    return map;
  }

  LocalSupportRostersCompanion toCompanion(bool nullToAbsent) {
    return LocalSupportRostersCompanion(
      wardId: Value(wardId),
      shiftDate: Value(shiftDate),
      shiftType: Value(shiftType),
      inChargeName: Value(inChargeName),
      inChargePhone: inChargePhone == null && nullToAbsent
          ? const Value.absent()
          : Value(inChargePhone),
      inChargeRole: inChargeRole == null && nullToAbsent
          ? const Value.absent()
          : Value(inChargeRole),
      floatNurseName: Value(floatNurseName),
      floatNursePhone: floatNursePhone == null && nullToAbsent
          ? const Value.absent()
          : Value(floatNursePhone),
      floatNurseRole: floatNurseRole == null && nullToAbsent
          ? const Value.absent()
          : Value(floatNurseRole),
      hcasJson: Value(hcasJson),
      doctorsJson: Value(doctorsJson),
    );
  }

  factory LocalSupportRoster.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSupportRoster(
      wardId: serializer.fromJson<String>(json['wardId']),
      shiftDate: serializer.fromJson<String>(json['shiftDate']),
      shiftType: serializer.fromJson<String>(json['shiftType']),
      inChargeName: serializer.fromJson<String>(json['inChargeName']),
      inChargePhone: serializer.fromJson<String?>(json['inChargePhone']),
      inChargeRole: serializer.fromJson<String?>(json['inChargeRole']),
      floatNurseName: serializer.fromJson<String>(json['floatNurseName']),
      floatNursePhone: serializer.fromJson<String?>(json['floatNursePhone']),
      floatNurseRole: serializer.fromJson<String?>(json['floatNurseRole']),
      hcasJson: serializer.fromJson<String>(json['hcasJson']),
      doctorsJson: serializer.fromJson<String>(json['doctorsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wardId': serializer.toJson<String>(wardId),
      'shiftDate': serializer.toJson<String>(shiftDate),
      'shiftType': serializer.toJson<String>(shiftType),
      'inChargeName': serializer.toJson<String>(inChargeName),
      'inChargePhone': serializer.toJson<String?>(inChargePhone),
      'inChargeRole': serializer.toJson<String?>(inChargeRole),
      'floatNurseName': serializer.toJson<String>(floatNurseName),
      'floatNursePhone': serializer.toJson<String?>(floatNursePhone),
      'floatNurseRole': serializer.toJson<String?>(floatNurseRole),
      'hcasJson': serializer.toJson<String>(hcasJson),
      'doctorsJson': serializer.toJson<String>(doctorsJson),
    };
  }

  LocalSupportRoster copyWith({
    String? wardId,
    String? shiftDate,
    String? shiftType,
    String? inChargeName,
    Value<String?> inChargePhone = const Value.absent(),
    Value<String?> inChargeRole = const Value.absent(),
    String? floatNurseName,
    Value<String?> floatNursePhone = const Value.absent(),
    Value<String?> floatNurseRole = const Value.absent(),
    String? hcasJson,
    String? doctorsJson,
  }) => LocalSupportRoster(
    wardId: wardId ?? this.wardId,
    shiftDate: shiftDate ?? this.shiftDate,
    shiftType: shiftType ?? this.shiftType,
    inChargeName: inChargeName ?? this.inChargeName,
    inChargePhone: inChargePhone.present
        ? inChargePhone.value
        : this.inChargePhone,
    inChargeRole: inChargeRole.present ? inChargeRole.value : this.inChargeRole,
    floatNurseName: floatNurseName ?? this.floatNurseName,
    floatNursePhone: floatNursePhone.present
        ? floatNursePhone.value
        : this.floatNursePhone,
    floatNurseRole: floatNurseRole.present
        ? floatNurseRole.value
        : this.floatNurseRole,
    hcasJson: hcasJson ?? this.hcasJson,
    doctorsJson: doctorsJson ?? this.doctorsJson,
  );
  LocalSupportRoster copyWithCompanion(LocalSupportRostersCompanion data) {
    return LocalSupportRoster(
      wardId: data.wardId.present ? data.wardId.value : this.wardId,
      shiftDate: data.shiftDate.present ? data.shiftDate.value : this.shiftDate,
      shiftType: data.shiftType.present ? data.shiftType.value : this.shiftType,
      inChargeName: data.inChargeName.present
          ? data.inChargeName.value
          : this.inChargeName,
      inChargePhone: data.inChargePhone.present
          ? data.inChargePhone.value
          : this.inChargePhone,
      inChargeRole: data.inChargeRole.present
          ? data.inChargeRole.value
          : this.inChargeRole,
      floatNurseName: data.floatNurseName.present
          ? data.floatNurseName.value
          : this.floatNurseName,
      floatNursePhone: data.floatNursePhone.present
          ? data.floatNursePhone.value
          : this.floatNursePhone,
      floatNurseRole: data.floatNurseRole.present
          ? data.floatNurseRole.value
          : this.floatNurseRole,
      hcasJson: data.hcasJson.present ? data.hcasJson.value : this.hcasJson,
      doctorsJson: data.doctorsJson.present
          ? data.doctorsJson.value
          : this.doctorsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSupportRoster(')
          ..write('wardId: $wardId, ')
          ..write('shiftDate: $shiftDate, ')
          ..write('shiftType: $shiftType, ')
          ..write('inChargeName: $inChargeName, ')
          ..write('inChargePhone: $inChargePhone, ')
          ..write('inChargeRole: $inChargeRole, ')
          ..write('floatNurseName: $floatNurseName, ')
          ..write('floatNursePhone: $floatNursePhone, ')
          ..write('floatNurseRole: $floatNurseRole, ')
          ..write('hcasJson: $hcasJson, ')
          ..write('doctorsJson: $doctorsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    wardId,
    shiftDate,
    shiftType,
    inChargeName,
    inChargePhone,
    inChargeRole,
    floatNurseName,
    floatNursePhone,
    floatNurseRole,
    hcasJson,
    doctorsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSupportRoster &&
          other.wardId == this.wardId &&
          other.shiftDate == this.shiftDate &&
          other.shiftType == this.shiftType &&
          other.inChargeName == this.inChargeName &&
          other.inChargePhone == this.inChargePhone &&
          other.inChargeRole == this.inChargeRole &&
          other.floatNurseName == this.floatNurseName &&
          other.floatNursePhone == this.floatNursePhone &&
          other.floatNurseRole == this.floatNurseRole &&
          other.hcasJson == this.hcasJson &&
          other.doctorsJson == this.doctorsJson);
}

class LocalSupportRostersCompanion extends UpdateCompanion<LocalSupportRoster> {
  final Value<String> wardId;
  final Value<String> shiftDate;
  final Value<String> shiftType;
  final Value<String> inChargeName;
  final Value<String?> inChargePhone;
  final Value<String?> inChargeRole;
  final Value<String> floatNurseName;
  final Value<String?> floatNursePhone;
  final Value<String?> floatNurseRole;
  final Value<String> hcasJson;
  final Value<String> doctorsJson;
  final Value<int> rowid;
  const LocalSupportRostersCompanion({
    this.wardId = const Value.absent(),
    this.shiftDate = const Value.absent(),
    this.shiftType = const Value.absent(),
    this.inChargeName = const Value.absent(),
    this.inChargePhone = const Value.absent(),
    this.inChargeRole = const Value.absent(),
    this.floatNurseName = const Value.absent(),
    this.floatNursePhone = const Value.absent(),
    this.floatNurseRole = const Value.absent(),
    this.hcasJson = const Value.absent(),
    this.doctorsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSupportRostersCompanion.insert({
    required String wardId,
    required String shiftDate,
    required String shiftType,
    required String inChargeName,
    this.inChargePhone = const Value.absent(),
    this.inChargeRole = const Value.absent(),
    required String floatNurseName,
    this.floatNursePhone = const Value.absent(),
    this.floatNurseRole = const Value.absent(),
    required String hcasJson,
    required String doctorsJson,
    this.rowid = const Value.absent(),
  }) : wardId = Value(wardId),
       shiftDate = Value(shiftDate),
       shiftType = Value(shiftType),
       inChargeName = Value(inChargeName),
       floatNurseName = Value(floatNurseName),
       hcasJson = Value(hcasJson),
       doctorsJson = Value(doctorsJson);
  static Insertable<LocalSupportRoster> custom({
    Expression<String>? wardId,
    Expression<String>? shiftDate,
    Expression<String>? shiftType,
    Expression<String>? inChargeName,
    Expression<String>? inChargePhone,
    Expression<String>? inChargeRole,
    Expression<String>? floatNurseName,
    Expression<String>? floatNursePhone,
    Expression<String>? floatNurseRole,
    Expression<String>? hcasJson,
    Expression<String>? doctorsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (wardId != null) 'ward_id': wardId,
      if (shiftDate != null) 'shift_date': shiftDate,
      if (shiftType != null) 'shift_type': shiftType,
      if (inChargeName != null) 'in_charge_name': inChargeName,
      if (inChargePhone != null) 'in_charge_phone': inChargePhone,
      if (inChargeRole != null) 'in_charge_role': inChargeRole,
      if (floatNurseName != null) 'float_nurse_name': floatNurseName,
      if (floatNursePhone != null) 'float_nurse_phone': floatNursePhone,
      if (floatNurseRole != null) 'float_nurse_role': floatNurseRole,
      if (hcasJson != null) 'hcas_json': hcasJson,
      if (doctorsJson != null) 'doctors_json': doctorsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSupportRostersCompanion copyWith({
    Value<String>? wardId,
    Value<String>? shiftDate,
    Value<String>? shiftType,
    Value<String>? inChargeName,
    Value<String?>? inChargePhone,
    Value<String?>? inChargeRole,
    Value<String>? floatNurseName,
    Value<String?>? floatNursePhone,
    Value<String?>? floatNurseRole,
    Value<String>? hcasJson,
    Value<String>? doctorsJson,
    Value<int>? rowid,
  }) {
    return LocalSupportRostersCompanion(
      wardId: wardId ?? this.wardId,
      shiftDate: shiftDate ?? this.shiftDate,
      shiftType: shiftType ?? this.shiftType,
      inChargeName: inChargeName ?? this.inChargeName,
      inChargePhone: inChargePhone ?? this.inChargePhone,
      inChargeRole: inChargeRole ?? this.inChargeRole,
      floatNurseName: floatNurseName ?? this.floatNurseName,
      floatNursePhone: floatNursePhone ?? this.floatNursePhone,
      floatNurseRole: floatNurseRole ?? this.floatNurseRole,
      hcasJson: hcasJson ?? this.hcasJson,
      doctorsJson: doctorsJson ?? this.doctorsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wardId.present) {
      map['ward_id'] = Variable<String>(wardId.value);
    }
    if (shiftDate.present) {
      map['shift_date'] = Variable<String>(shiftDate.value);
    }
    if (shiftType.present) {
      map['shift_type'] = Variable<String>(shiftType.value);
    }
    if (inChargeName.present) {
      map['in_charge_name'] = Variable<String>(inChargeName.value);
    }
    if (inChargePhone.present) {
      map['in_charge_phone'] = Variable<String>(inChargePhone.value);
    }
    if (inChargeRole.present) {
      map['in_charge_role'] = Variable<String>(inChargeRole.value);
    }
    if (floatNurseName.present) {
      map['float_nurse_name'] = Variable<String>(floatNurseName.value);
    }
    if (floatNursePhone.present) {
      map['float_nurse_phone'] = Variable<String>(floatNursePhone.value);
    }
    if (floatNurseRole.present) {
      map['float_nurse_role'] = Variable<String>(floatNurseRole.value);
    }
    if (hcasJson.present) {
      map['hcas_json'] = Variable<String>(hcasJson.value);
    }
    if (doctorsJson.present) {
      map['doctors_json'] = Variable<String>(doctorsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSupportRostersCompanion(')
          ..write('wardId: $wardId, ')
          ..write('shiftDate: $shiftDate, ')
          ..write('shiftType: $shiftType, ')
          ..write('inChargeName: $inChargeName, ')
          ..write('inChargePhone: $inChargePhone, ')
          ..write('inChargeRole: $inChargeRole, ')
          ..write('floatNurseName: $floatNurseName, ')
          ..write('floatNursePhone: $floatNursePhone, ')
          ..write('floatNurseRole: $floatNurseRole, ')
          ..write('hcasJson: $hcasJson, ')
          ..write('doctorsJson: $doctorsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$OraviLocalDatabase extends GeneratedDatabase {
  _$OraviLocalDatabase(QueryExecutor e) : super(e);
  $OraviLocalDatabaseManager get managers => $OraviLocalDatabaseManager(this);
  late final $LocalEventsTable localEvents = $LocalEventsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $LocalStaffTable localStaff = $LocalStaffTable(this);
  late final $LocalWhiteboardAssignmentsTable localWhiteboardAssignments =
      $LocalWhiteboardAssignmentsTable(this);
  late final $LocalSupportRostersTable localSupportRosters =
      $LocalSupportRostersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localEvents,
    outbox,
    localStaff,
    localWhiteboardAssignments,
    localSupportRosters,
  ];
}

typedef $$LocalEventsTableCreateCompanionBuilder =
    LocalEventsCompanion Function({
      required String eventId,
      required String patientId,
      Value<String?> loopId,
      required String eventType,
      required String authorId,
      required String deviceId,
      required DateTime clientCreatedAt,
      Value<int?> serverSeq,
      Value<DateTime?> serverReceivedAt,
      Value<int> schemaVersion,
      required String payloadJson,
      Value<int> rowid,
    });
typedef $$LocalEventsTableUpdateCompanionBuilder =
    LocalEventsCompanion Function({
      Value<String> eventId,
      Value<String> patientId,
      Value<String?> loopId,
      Value<String> eventType,
      Value<String> authorId,
      Value<String> deviceId,
      Value<DateTime> clientCreatedAt,
      Value<int?> serverSeq,
      Value<DateTime?> serverReceivedAt,
      Value<int> schemaVersion,
      Value<String> payloadJson,
      Value<int> rowid,
    });

class $$LocalEventsTableFilterComposer
    extends Composer<_$OraviLocalDatabase, $LocalEventsTable> {
  $$LocalEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loopId => $composableBuilder(
    column: $table.loopId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientCreatedAt => $composableBuilder(
    column: $table.clientCreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverReceivedAt => $composableBuilder(
    column: $table.serverReceivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalEventsTableOrderingComposer
    extends Composer<_$OraviLocalDatabase, $LocalEventsTable> {
  $$LocalEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loopId => $composableBuilder(
    column: $table.loopId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientCreatedAt => $composableBuilder(
    column: $table.clientCreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverReceivedAt => $composableBuilder(
    column: $table.serverReceivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalEventsTableAnnotationComposer
    extends Composer<_$OraviLocalDatabase, $LocalEventsTable> {
  $$LocalEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);

  GeneratedColumn<String> get loopId =>
      $composableBuilder(column: $table.loopId, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get authorId =>
      $composableBuilder(column: $table.authorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<DateTime> get clientCreatedAt => $composableBuilder(
    column: $table.clientCreatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);

  GeneratedColumn<DateTime> get serverReceivedAt => $composableBuilder(
    column: $table.serverReceivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );
}

class $$LocalEventsTableTableManager
    extends
        RootTableManager<
          _$OraviLocalDatabase,
          $LocalEventsTable,
          LocalEvent,
          $$LocalEventsTableFilterComposer,
          $$LocalEventsTableOrderingComposer,
          $$LocalEventsTableAnnotationComposer,
          $$LocalEventsTableCreateCompanionBuilder,
          $$LocalEventsTableUpdateCompanionBuilder,
          (
            LocalEvent,
            BaseReferences<_$OraviLocalDatabase, $LocalEventsTable, LocalEvent>,
          ),
          LocalEvent,
          PrefetchHooks Function()
        > {
  $$LocalEventsTableTableManager(
    _$OraviLocalDatabase db,
    $LocalEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> patientId = const Value.absent(),
                Value<String?> loopId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> authorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<DateTime> clientCreatedAt = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<DateTime?> serverReceivedAt = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalEventsCompanion(
                eventId: eventId,
                patientId: patientId,
                loopId: loopId,
                eventType: eventType,
                authorId: authorId,
                deviceId: deviceId,
                clientCreatedAt: clientCreatedAt,
                serverSeq: serverSeq,
                serverReceivedAt: serverReceivedAt,
                schemaVersion: schemaVersion,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String patientId,
                Value<String?> loopId = const Value.absent(),
                required String eventType,
                required String authorId,
                required String deviceId,
                required DateTime clientCreatedAt,
                Value<int?> serverSeq = const Value.absent(),
                Value<DateTime?> serverReceivedAt = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                required String payloadJson,
                Value<int> rowid = const Value.absent(),
              }) => LocalEventsCompanion.insert(
                eventId: eventId,
                patientId: patientId,
                loopId: loopId,
                eventType: eventType,
                authorId: authorId,
                deviceId: deviceId,
                clientCreatedAt: clientCreatedAt,
                serverSeq: serverSeq,
                serverReceivedAt: serverReceivedAt,
                schemaVersion: schemaVersion,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalEventsTable, LocalEvent>(table),
                  BaseReferences<
                    _$OraviLocalDatabase,
                    $LocalEventsTable,
                    LocalEvent
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$OraviLocalDatabase,
      $LocalEventsTable,
      LocalEvent,
      $$LocalEventsTableFilterComposer,
      $$LocalEventsTableOrderingComposer,
      $$LocalEventsTableAnnotationComposer,
      $$LocalEventsTableCreateCompanionBuilder,
      $$LocalEventsTableUpdateCompanionBuilder,
      (
        LocalEvent,
        BaseReferences<_$OraviLocalDatabase, $LocalEventsTable, LocalEvent>,
      ),
      LocalEvent,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> id,
      required String eventId,
      Value<String> status,
      Value<int> retryCount,
      Value<DateTime?> lastAttemptAt,
      Value<String?> errorMessage,
      required DateTime createdAt,
    });
typedef $$OutboxTableUpdateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> id,
      Value<String> eventId,
      Value<String> status,
      Value<int> retryCount,
      Value<DateTime?> lastAttemptAt,
      Value<String?> errorMessage,
      Value<DateTime> createdAt,
    });

class $$OutboxTableFilterComposer
    extends Composer<_$OraviLocalDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$OraviLocalDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$OraviLocalDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$OraviLocalDatabase,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (
            OutboxData,
            BaseReferences<_$OraviLocalDatabase, $OutboxTable, OutboxData>,
          ),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$OraviLocalDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OutboxCompanion(
                id: id,
                eventId: eventId,
                status: status,
                retryCount: retryCount,
                lastAttemptAt: lastAttemptAt,
                errorMessage: errorMessage,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String eventId,
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                required DateTime createdAt,
              }) => OutboxCompanion.insert(
                id: id,
                eventId: eventId,
                status: status,
                retryCount: retryCount,
                lastAttemptAt: lastAttemptAt,
                errorMessage: errorMessage,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxData>(table),
                  BaseReferences<
                    _$OraviLocalDatabase,
                    $OutboxTable,
                    OutboxData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$OraviLocalDatabase,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (
        OutboxData,
        BaseReferences<_$OraviLocalDatabase, $OutboxTable, OutboxData>,
      ),
      OutboxData,
      PrefetchHooks Function()
    >;
typedef $$LocalStaffTableCreateCompanionBuilder =
    LocalStaffCompanion Function({
      required String staffId,
      required String name,
      required String role,
      Value<String> wardId,
      required String pin,
      Value<bool> isActive,
      Value<String> avatarColor,
      required String initials,
      Value<String?> email,
      Value<int> rowid,
    });
typedef $$LocalStaffTableUpdateCompanionBuilder =
    LocalStaffCompanion Function({
      Value<String> staffId,
      Value<String> name,
      Value<String> role,
      Value<String> wardId,
      Value<String> pin,
      Value<bool> isActive,
      Value<String> avatarColor,
      Value<String> initials,
      Value<String?> email,
      Value<int> rowid,
    });

class $$LocalStaffTableFilterComposer
    extends Composer<_$OraviLocalDatabase, $LocalStaffTable> {
  $$LocalStaffTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wardId => $composableBuilder(
    column: $table.wardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get initials => $composableBuilder(
    column: $table.initials,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalStaffTableOrderingComposer
    extends Composer<_$OraviLocalDatabase, $LocalStaffTable> {
  $$LocalStaffTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wardId => $composableBuilder(
    column: $table.wardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pin => $composableBuilder(
    column: $table.pin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get initials => $composableBuilder(
    column: $table.initials,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalStaffTableAnnotationComposer
    extends Composer<_$OraviLocalDatabase, $LocalStaffTable> {
  $$LocalStaffTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get staffId =>
      $composableBuilder(column: $table.staffId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get wardId =>
      $composableBuilder(column: $table.wardId, builder: (column) => column);

  GeneratedColumn<String> get pin =>
      $composableBuilder(column: $table.pin, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get avatarColor => $composableBuilder(
    column: $table.avatarColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get initials =>
      $composableBuilder(column: $table.initials, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);
}

class $$LocalStaffTableTableManager
    extends
        RootTableManager<
          _$OraviLocalDatabase,
          $LocalStaffTable,
          LocalStaffData,
          $$LocalStaffTableFilterComposer,
          $$LocalStaffTableOrderingComposer,
          $$LocalStaffTableAnnotationComposer,
          $$LocalStaffTableCreateCompanionBuilder,
          $$LocalStaffTableUpdateCompanionBuilder,
          (
            LocalStaffData,
            BaseReferences<
              _$OraviLocalDatabase,
              $LocalStaffTable,
              LocalStaffData
            >,
          ),
          LocalStaffData,
          PrefetchHooks Function()
        > {
  $$LocalStaffTableTableManager(_$OraviLocalDatabase db, $LocalStaffTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalStaffTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalStaffTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalStaffTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> staffId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> wardId = const Value.absent(),
                Value<String> pin = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String> avatarColor = const Value.absent(),
                Value<String> initials = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalStaffCompanion(
                staffId: staffId,
                name: name,
                role: role,
                wardId: wardId,
                pin: pin,
                isActive: isActive,
                avatarColor: avatarColor,
                initials: initials,
                email: email,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String staffId,
                required String name,
                required String role,
                Value<String> wardId = const Value.absent(),
                required String pin,
                Value<bool> isActive = const Value.absent(),
                Value<String> avatarColor = const Value.absent(),
                required String initials,
                Value<String?> email = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalStaffCompanion.insert(
                staffId: staffId,
                name: name,
                role: role,
                wardId: wardId,
                pin: pin,
                isActive: isActive,
                avatarColor: avatarColor,
                initials: initials,
                email: email,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalStaffTable, LocalStaffData>(table),
                  BaseReferences<
                    _$OraviLocalDatabase,
                    $LocalStaffTable,
                    LocalStaffData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalStaffTableProcessedTableManager =
    ProcessedTableManager<
      _$OraviLocalDatabase,
      $LocalStaffTable,
      LocalStaffData,
      $$LocalStaffTableFilterComposer,
      $$LocalStaffTableOrderingComposer,
      $$LocalStaffTableAnnotationComposer,
      $$LocalStaffTableCreateCompanionBuilder,
      $$LocalStaffTableUpdateCompanionBuilder,
      (
        LocalStaffData,
        BaseReferences<_$OraviLocalDatabase, $LocalStaffTable, LocalStaffData>,
      ),
      LocalStaffData,
      PrefetchHooks Function()
    >;
typedef $$LocalWhiteboardAssignmentsTableCreateCompanionBuilder =
    LocalWhiteboardAssignmentsCompanion Function({
      required String bedNumber,
      required String patientName,
      Value<String?> ageGender,
      Value<String?> diagnosis,
      required String assignedNurse,
      required String bay,
      required String shiftDate,
      required String shiftType,
      Value<int> rowid,
    });
typedef $$LocalWhiteboardAssignmentsTableUpdateCompanionBuilder =
    LocalWhiteboardAssignmentsCompanion Function({
      Value<String> bedNumber,
      Value<String> patientName,
      Value<String?> ageGender,
      Value<String?> diagnosis,
      Value<String> assignedNurse,
      Value<String> bay,
      Value<String> shiftDate,
      Value<String> shiftType,
      Value<int> rowid,
    });

class $$LocalWhiteboardAssignmentsTableFilterComposer
    extends Composer<_$OraviLocalDatabase, $LocalWhiteboardAssignmentsTable> {
  $$LocalWhiteboardAssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bedNumber => $composableBuilder(
    column: $table.bedNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patientName => $composableBuilder(
    column: $table.patientName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ageGender => $composableBuilder(
    column: $table.ageGender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get diagnosis => $composableBuilder(
    column: $table.diagnosis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assignedNurse => $composableBuilder(
    column: $table.assignedNurse,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bay => $composableBuilder(
    column: $table.bay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shiftDate => $composableBuilder(
    column: $table.shiftDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shiftType => $composableBuilder(
    column: $table.shiftType,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalWhiteboardAssignmentsTableOrderingComposer
    extends Composer<_$OraviLocalDatabase, $LocalWhiteboardAssignmentsTable> {
  $$LocalWhiteboardAssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bedNumber => $composableBuilder(
    column: $table.bedNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientName => $composableBuilder(
    column: $table.patientName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ageGender => $composableBuilder(
    column: $table.ageGender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get diagnosis => $composableBuilder(
    column: $table.diagnosis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assignedNurse => $composableBuilder(
    column: $table.assignedNurse,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bay => $composableBuilder(
    column: $table.bay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shiftDate => $composableBuilder(
    column: $table.shiftDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shiftType => $composableBuilder(
    column: $table.shiftType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalWhiteboardAssignmentsTableAnnotationComposer
    extends Composer<_$OraviLocalDatabase, $LocalWhiteboardAssignmentsTable> {
  $$LocalWhiteboardAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bedNumber =>
      $composableBuilder(column: $table.bedNumber, builder: (column) => column);

  GeneratedColumn<String> get patientName => $composableBuilder(
    column: $table.patientName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ageGender =>
      $composableBuilder(column: $table.ageGender, builder: (column) => column);

  GeneratedColumn<String> get diagnosis =>
      $composableBuilder(column: $table.diagnosis, builder: (column) => column);

  GeneratedColumn<String> get assignedNurse => $composableBuilder(
    column: $table.assignedNurse,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bay =>
      $composableBuilder(column: $table.bay, builder: (column) => column);

  GeneratedColumn<String> get shiftDate =>
      $composableBuilder(column: $table.shiftDate, builder: (column) => column);

  GeneratedColumn<String> get shiftType =>
      $composableBuilder(column: $table.shiftType, builder: (column) => column);
}

class $$LocalWhiteboardAssignmentsTableTableManager
    extends
        RootTableManager<
          _$OraviLocalDatabase,
          $LocalWhiteboardAssignmentsTable,
          LocalWhiteboardAssignment,
          $$LocalWhiteboardAssignmentsTableFilterComposer,
          $$LocalWhiteboardAssignmentsTableOrderingComposer,
          $$LocalWhiteboardAssignmentsTableAnnotationComposer,
          $$LocalWhiteboardAssignmentsTableCreateCompanionBuilder,
          $$LocalWhiteboardAssignmentsTableUpdateCompanionBuilder,
          (
            LocalWhiteboardAssignment,
            BaseReferences<
              _$OraviLocalDatabase,
              $LocalWhiteboardAssignmentsTable,
              LocalWhiteboardAssignment
            >,
          ),
          LocalWhiteboardAssignment,
          PrefetchHooks Function()
        > {
  $$LocalWhiteboardAssignmentsTableTableManager(
    _$OraviLocalDatabase db,
    $LocalWhiteboardAssignmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalWhiteboardAssignmentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalWhiteboardAssignmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalWhiteboardAssignmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bedNumber = const Value.absent(),
                Value<String> patientName = const Value.absent(),
                Value<String?> ageGender = const Value.absent(),
                Value<String?> diagnosis = const Value.absent(),
                Value<String> assignedNurse = const Value.absent(),
                Value<String> bay = const Value.absent(),
                Value<String> shiftDate = const Value.absent(),
                Value<String> shiftType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalWhiteboardAssignmentsCompanion(
                bedNumber: bedNumber,
                patientName: patientName,
                ageGender: ageGender,
                diagnosis: diagnosis,
                assignedNurse: assignedNurse,
                bay: bay,
                shiftDate: shiftDate,
                shiftType: shiftType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bedNumber,
                required String patientName,
                Value<String?> ageGender = const Value.absent(),
                Value<String?> diagnosis = const Value.absent(),
                required String assignedNurse,
                required String bay,
                required String shiftDate,
                required String shiftType,
                Value<int> rowid = const Value.absent(),
              }) => LocalWhiteboardAssignmentsCompanion.insert(
                bedNumber: bedNumber,
                patientName: patientName,
                ageGender: ageGender,
                diagnosis: diagnosis,
                assignedNurse: assignedNurse,
                bay: bay,
                shiftDate: shiftDate,
                shiftType: shiftType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LocalWhiteboardAssignmentsTable,
                    LocalWhiteboardAssignment
                  >(table),
                  BaseReferences<
                    _$OraviLocalDatabase,
                    $LocalWhiteboardAssignmentsTable,
                    LocalWhiteboardAssignment
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalWhiteboardAssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$OraviLocalDatabase,
      $LocalWhiteboardAssignmentsTable,
      LocalWhiteboardAssignment,
      $$LocalWhiteboardAssignmentsTableFilterComposer,
      $$LocalWhiteboardAssignmentsTableOrderingComposer,
      $$LocalWhiteboardAssignmentsTableAnnotationComposer,
      $$LocalWhiteboardAssignmentsTableCreateCompanionBuilder,
      $$LocalWhiteboardAssignmentsTableUpdateCompanionBuilder,
      (
        LocalWhiteboardAssignment,
        BaseReferences<
          _$OraviLocalDatabase,
          $LocalWhiteboardAssignmentsTable,
          LocalWhiteboardAssignment
        >,
      ),
      LocalWhiteboardAssignment,
      PrefetchHooks Function()
    >;
typedef $$LocalSupportRostersTableCreateCompanionBuilder =
    LocalSupportRostersCompanion Function({
      required String wardId,
      required String shiftDate,
      required String shiftType,
      required String inChargeName,
      Value<String?> inChargePhone,
      Value<String?> inChargeRole,
      required String floatNurseName,
      Value<String?> floatNursePhone,
      Value<String?> floatNurseRole,
      required String hcasJson,
      required String doctorsJson,
      Value<int> rowid,
    });
typedef $$LocalSupportRostersTableUpdateCompanionBuilder =
    LocalSupportRostersCompanion Function({
      Value<String> wardId,
      Value<String> shiftDate,
      Value<String> shiftType,
      Value<String> inChargeName,
      Value<String?> inChargePhone,
      Value<String?> inChargeRole,
      Value<String> floatNurseName,
      Value<String?> floatNursePhone,
      Value<String?> floatNurseRole,
      Value<String> hcasJson,
      Value<String> doctorsJson,
      Value<int> rowid,
    });

class $$LocalSupportRostersTableFilterComposer
    extends Composer<_$OraviLocalDatabase, $LocalSupportRostersTable> {
  $$LocalSupportRostersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get wardId => $composableBuilder(
    column: $table.wardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shiftDate => $composableBuilder(
    column: $table.shiftDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shiftType => $composableBuilder(
    column: $table.shiftType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inChargeName => $composableBuilder(
    column: $table.inChargeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inChargePhone => $composableBuilder(
    column: $table.inChargePhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inChargeRole => $composableBuilder(
    column: $table.inChargeRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get floatNurseName => $composableBuilder(
    column: $table.floatNurseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get floatNursePhone => $composableBuilder(
    column: $table.floatNursePhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get floatNurseRole => $composableBuilder(
    column: $table.floatNurseRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hcasJson => $composableBuilder(
    column: $table.hcasJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get doctorsJson => $composableBuilder(
    column: $table.doctorsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSupportRostersTableOrderingComposer
    extends Composer<_$OraviLocalDatabase, $LocalSupportRostersTable> {
  $$LocalSupportRostersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get wardId => $composableBuilder(
    column: $table.wardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shiftDate => $composableBuilder(
    column: $table.shiftDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shiftType => $composableBuilder(
    column: $table.shiftType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inChargeName => $composableBuilder(
    column: $table.inChargeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inChargePhone => $composableBuilder(
    column: $table.inChargePhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inChargeRole => $composableBuilder(
    column: $table.inChargeRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get floatNurseName => $composableBuilder(
    column: $table.floatNurseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get floatNursePhone => $composableBuilder(
    column: $table.floatNursePhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get floatNurseRole => $composableBuilder(
    column: $table.floatNurseRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hcasJson => $composableBuilder(
    column: $table.hcasJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get doctorsJson => $composableBuilder(
    column: $table.doctorsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSupportRostersTableAnnotationComposer
    extends Composer<_$OraviLocalDatabase, $LocalSupportRostersTable> {
  $$LocalSupportRostersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get wardId =>
      $composableBuilder(column: $table.wardId, builder: (column) => column);

  GeneratedColumn<String> get shiftDate =>
      $composableBuilder(column: $table.shiftDate, builder: (column) => column);

  GeneratedColumn<String> get shiftType =>
      $composableBuilder(column: $table.shiftType, builder: (column) => column);

  GeneratedColumn<String> get inChargeName => $composableBuilder(
    column: $table.inChargeName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inChargePhone => $composableBuilder(
    column: $table.inChargePhone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inChargeRole => $composableBuilder(
    column: $table.inChargeRole,
    builder: (column) => column,
  );

  GeneratedColumn<String> get floatNurseName => $composableBuilder(
    column: $table.floatNurseName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get floatNursePhone => $composableBuilder(
    column: $table.floatNursePhone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get floatNurseRole => $composableBuilder(
    column: $table.floatNurseRole,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hcasJson =>
      $composableBuilder(column: $table.hcasJson, builder: (column) => column);

  GeneratedColumn<String> get doctorsJson => $composableBuilder(
    column: $table.doctorsJson,
    builder: (column) => column,
  );
}

class $$LocalSupportRostersTableTableManager
    extends
        RootTableManager<
          _$OraviLocalDatabase,
          $LocalSupportRostersTable,
          LocalSupportRoster,
          $$LocalSupportRostersTableFilterComposer,
          $$LocalSupportRostersTableOrderingComposer,
          $$LocalSupportRostersTableAnnotationComposer,
          $$LocalSupportRostersTableCreateCompanionBuilder,
          $$LocalSupportRostersTableUpdateCompanionBuilder,
          (
            LocalSupportRoster,
            BaseReferences<
              _$OraviLocalDatabase,
              $LocalSupportRostersTable,
              LocalSupportRoster
            >,
          ),
          LocalSupportRoster,
          PrefetchHooks Function()
        > {
  $$LocalSupportRostersTableTableManager(
    _$OraviLocalDatabase db,
    $LocalSupportRostersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSupportRostersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSupportRostersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalSupportRostersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> wardId = const Value.absent(),
                Value<String> shiftDate = const Value.absent(),
                Value<String> shiftType = const Value.absent(),
                Value<String> inChargeName = const Value.absent(),
                Value<String?> inChargePhone = const Value.absent(),
                Value<String?> inChargeRole = const Value.absent(),
                Value<String> floatNurseName = const Value.absent(),
                Value<String?> floatNursePhone = const Value.absent(),
                Value<String?> floatNurseRole = const Value.absent(),
                Value<String> hcasJson = const Value.absent(),
                Value<String> doctorsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSupportRostersCompanion(
                wardId: wardId,
                shiftDate: shiftDate,
                shiftType: shiftType,
                inChargeName: inChargeName,
                inChargePhone: inChargePhone,
                inChargeRole: inChargeRole,
                floatNurseName: floatNurseName,
                floatNursePhone: floatNursePhone,
                floatNurseRole: floatNurseRole,
                hcasJson: hcasJson,
                doctorsJson: doctorsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String wardId,
                required String shiftDate,
                required String shiftType,
                required String inChargeName,
                Value<String?> inChargePhone = const Value.absent(),
                Value<String?> inChargeRole = const Value.absent(),
                required String floatNurseName,
                Value<String?> floatNursePhone = const Value.absent(),
                Value<String?> floatNurseRole = const Value.absent(),
                required String hcasJson,
                required String doctorsJson,
                Value<int> rowid = const Value.absent(),
              }) => LocalSupportRostersCompanion.insert(
                wardId: wardId,
                shiftDate: shiftDate,
                shiftType: shiftType,
                inChargeName: inChargeName,
                inChargePhone: inChargePhone,
                inChargeRole: inChargeRole,
                floatNurseName: floatNurseName,
                floatNursePhone: floatNursePhone,
                floatNurseRole: floatNurseRole,
                hcasJson: hcasJson,
                doctorsJson: doctorsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalSupportRostersTable, LocalSupportRoster>(
                    table,
                  ),
                  BaseReferences<
                    _$OraviLocalDatabase,
                    $LocalSupportRostersTable,
                    LocalSupportRoster
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSupportRostersTableProcessedTableManager =
    ProcessedTableManager<
      _$OraviLocalDatabase,
      $LocalSupportRostersTable,
      LocalSupportRoster,
      $$LocalSupportRostersTableFilterComposer,
      $$LocalSupportRostersTableOrderingComposer,
      $$LocalSupportRostersTableAnnotationComposer,
      $$LocalSupportRostersTableCreateCompanionBuilder,
      $$LocalSupportRostersTableUpdateCompanionBuilder,
      (
        LocalSupportRoster,
        BaseReferences<
          _$OraviLocalDatabase,
          $LocalSupportRostersTable,
          LocalSupportRoster
        >,
      ),
      LocalSupportRoster,
      PrefetchHooks Function()
    >;

class $OraviLocalDatabaseManager {
  final _$OraviLocalDatabase _db;
  $OraviLocalDatabaseManager(this._db);
  $$LocalEventsTableTableManager get localEvents =>
      $$LocalEventsTableTableManager(_db, _db.localEvents);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$LocalStaffTableTableManager get localStaff =>
      $$LocalStaffTableTableManager(_db, _db.localStaff);
  $$LocalWhiteboardAssignmentsTableTableManager
  get localWhiteboardAssignments =>
      $$LocalWhiteboardAssignmentsTableTableManager(
        _db,
        _db.localWhiteboardAssignments,
      );
  $$LocalSupportRostersTableTableManager get localSupportRosters =>
      $$LocalSupportRostersTableTableManager(_db, _db.localSupportRosters);
}
