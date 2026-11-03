import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Stable per-install identifier used to attribute local clinical events.
class DeviceIdentity {
  static const _fileName = 'oravi_device_id';
  static final _uuidPattern = RegExp(r'^DEVICE-[0-9a-fA-F-]{36}$');

  static Future<String> loadOrCreate() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, _fileName));

    if (await file.exists()) {
      final savedId = (await file.readAsString()).trim();
      if (_uuidPattern.hasMatch(savedId)) return savedId;
    }

    await directory.create(recursive: true);
    final deviceId = 'DEVICE-${const Uuid().v7()}';
    await file.writeAsString(deviceId, flush: true);
    return deviceId;
  }
}
