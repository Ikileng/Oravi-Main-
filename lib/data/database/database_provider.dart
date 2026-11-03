import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database.dart';

/// Global provider for the encrypted local event/outbox database.
final localDatabaseProvider = Provider<OraviLocalDatabase>((ref) {
  final db = OraviLocalDatabase(null);
  ref.onDispose(() => db.close());
  return db;
});
