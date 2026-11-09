import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'data/database/database.dart';
import 'data/database/database_key.dart';
import 'data/database/database_provider.dart';
import 'data/device_identity.dart';
import 'data/local_ward_repository.dart';
import 'domain/models/staff_profile.dart';
import 'domain/projections/projections.dart';
import 'presentation/lockscreen/digital_id_lockscreen.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/ward_providers.dart';
import 'presentation/providers/ward_context_providers.dart';
import 'presentation/providers/whiteboard_providers.dart';
import 'presentation/theme/clinical_theme.dart';
import 'presentation/patient_detail_screen.dart';
import 'presentation/ward_board_screen.dart';
import 'data/notifications/medical_issue_push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (_) => const Material(
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Oravi could not load this screen. Please go back and try again. '
          'If this continues, let your supervisor know.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  // Open the encrypted local database. New installations start empty; ward data
  // and accounts are supplied by the hospital backend.
  if (kDebugMode) debugPrint('ORAVI_STARTUP device_identity:start');
  final deviceId = await DeviceIdentity.loadOrCreate();
  if (kDebugMode) debugPrint('ORAVI_STARTUP device_identity:done');
  if (kDebugMode) debugPrint('ORAVI_STARTUP database_key:start');
  final databaseKey = await DatabaseKey.loadOrCreate();
  if (kDebugMode) debugPrint('ORAVI_STARTUP database_key:done');
  final documentsDirectory = await getApplicationDocumentsDirectory();
  if (kDebugMode) debugPrint('ORAVI_STARTUP encrypted_database_prepare:start');
  final databaseFile = File(
    p.join(documentsDirectory.path, 'oravi_offline.sqlite'),
  );
  await OraviLocalDatabase.prepareEncryptedDatabase(databaseFile, databaseKey);
  if (kDebugMode) debugPrint('ORAVI_STARTUP encrypted_database_prepare:done');
  final db = OraviLocalDatabase(null, encryptionKey: databaseKey);
  await db.removeKnownDebugFixtures();
  // Restore previously saved events before the ward board can read them.
  final wardRepository = LocalWardRepository(database: db);
  if (kDebugMode) debugPrint('ORAVI_STARTUP restore_events:start');
  await wardRepository.initialize();
  if (kDebugMode) debugPrint('ORAVI_STARTUP restore_events:done');

  if (kDebugMode) debugPrint('ORAVI_STARTUP run_app');
  runApp(
    ProviderScope(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        localWardRepositoryProvider.overrideWithValue(wardRepository),
        localDeviceIdProvider.overrideWithValue(deviceId),
      ],
      child: const OraviApp(),
    ),
  );
}

class OraviApp extends ConsumerStatefulWidget {
  final Widget? home;
  const OraviApp({super.key, this.home});

  @override
  ConsumerState<OraviApp> createState() => _OraviAppState();
}

class _OraviAppState extends ConsumerState<OraviApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<MedicalIssueAlert>? _openedAlerts;
  MedicalIssueAlert? _pendingAlert;
  bool _openingAlert = false;

  @override
  void initState() {
    super.initState();
    _openedAlerts = ref
        .read(medicalIssuePushServiceProvider)
        .openedAlerts
        .listen(_queueAlert);
  }

  @override
  void dispose() {
    _openedAlerts?.cancel();
    super.dispose();
  }

  void _queueAlert(MedicalIssueAlert alert) {
    _pendingAlert = alert;
    if (mounted) setState(() {});
  }

  void _schedulePendingAlert(StaffProfile? staff) {
    if (staff == null || _pendingAlert == null || _openingAlert) return;
    _openingAlert = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingAlert();
    });
  }

  Future<void> _openPendingAlert() async {
    final alert = _pendingAlert;
    _pendingAlert = null;
    if (alert == null) {
      _openingAlert = false;
      return;
    }

    try {
      final response = await ref
          .read(wardBoardServiceProvider)
          .getMedicalIssueThread(
            patientId: alert.patientId,
            loopId: alert.loopId,
          );
      final rawEvents = response['events'] as List;
      final events = rawEvents.map((event) {
        if (event is! Map<String, dynamic>) {
          throw const FormatException(
            'The server returned an invalid Medical Issue event.',
          );
        }
        return event;
      }).toList();
      await ref.read(localDatabaseProvider).insertRemoteEvents(events);
      await ref.read(localWardRepositoryProvider).reloadFromDatabase();
      ref.read(wardControllerProvider.notifier).refresh();

      final loop = ref
          .read(localWardRepositoryProvider)
          .getLoopsForPatient(alert.patientId)
          .where((candidate) => candidate.loopId == alert.loopId)
          .firstOrNull;
      if (loop == null) {
        throw StateError('The Medical Issue thread could not be opened.');
      }

      final patient = ref
          .read(wardPatientsProvider)
          .where((candidate) => candidate.patientId == alert.patientId)
          .firstOrNull;
      final patientContext =
          patient ??
          PatientStateProjection(
            patientId: alert.patientId,
            wardId:
                response['ward_id'] as String? ??
                ref.read(selectedWardProvider).wardId,
            bedNumber: 'Medical Issue',
            patientInitials: '',
            age: 0,
            sex: '',
            shortAdmittingNote: '',
            admittedAt: loop.createdAt,
            updatedAt: loop.updatedAt,
          );
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        throw StateError('The app navigation context is not ready.');
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) => PatientDetailScreen(
            patient: patientContext,
            issueOnlyLoopIds: {alert.loopId},
            initialExpandedLoopId: alert.loopId,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This Medical Issue is no longer assigned to your account, or could not be loaded.',
            ),
          ),
        );
      }
      debugPrint(
        'Could not open a Medical Issue alert (${error.runtimeType}).',
      );
    } finally {
      _openingAlert = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authStaff = ref.watch(authenticatedStaffProvider);
    final pushStatus = ref.watch(medicalIssuePushControllerProvider);
    _schedulePendingAlert(authStaff);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Oravi Clinical Operating System',
      debugShowCheckedModeBanner: false,
      theme: ClinicalTheme.darkTheme,
      builder: (context, child) => Column(
        children: [
          if (pushStatus != null)
            Material(
              color: ClinicalTheme.urgentAmber.withValues(alpha: 0.18),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      pushStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ClinicalTheme.urgentAmber,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
      home:
          widget.home ??
          (authStaff == null
              ? const DigitalIdLockscreen()
              : const WardBoardScreen()),
    );
  }
}
