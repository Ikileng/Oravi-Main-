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
import 'presentation/lockscreen/digital_id_lockscreen.dart';
import 'presentation/providers/auth_providers.dart';
import 'presentation/providers/ward_providers.dart';
import 'presentation/theme/clinical_theme.dart';
import 'presentation/ward_board_screen.dart';

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

class OraviApp extends ConsumerWidget {
  final Widget? home;
  const OraviApp({super.key, this.home});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStaff = ref.watch(authenticatedStaffProvider);

    return MaterialApp(
      title: 'Oravi Clinical Operating System',
      debugShowCheckedModeBanner: false,
      theme: ClinicalTheme.darkTheme,
      home:
          home ??
          (authStaff == null
              ? const DigitalIdLockscreen()
              : const WardBoardScreen()),
    );
  }
}
