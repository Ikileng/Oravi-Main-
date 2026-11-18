import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database/database.dart';
import 'database/database_provider.dart';

final askOraviHistoryStoreProvider = Provider<AskOraviHistoryStore>(
  (ref) => AskOraviHistoryStore(ref.watch(localDatabaseProvider)),
);

/// Durable device-local history, separate from disposable cached server data.
class AskOraviHistoryStore {
  final OraviLocalDatabase database;
  Future<void> _writes = Future<void>.value();
  AskOraviHistoryStore(this.database);

  String _key(String staffId, String patientId) =>
      'ask_oravi_history:v1:${jsonEncode([staffId, patientId])}';

  Future<List<Map<String, dynamic>>> load(
    String staffId,
    String patientId,
  ) async {
    await _writes;
    final value = await database.readLocalValue(_key(staffId, patientId));
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> save(
    String staffId,
    String patientId,
    Map<String, dynamic> chat,
  ) {
    // Capture immutable JSON before awaiting, and serialize read/modify/write.
    final snapshot = jsonEncode(chat);
    final next = _writes.then((_) async {
      final key = _key(staffId, patientId);
      final value = await database.readLocalValue(key);
      final chats = value == null ? <dynamic>[] : jsonDecode(value) as List;
      final saved = jsonDecode(snapshot) as Map<String, dynamic>;
      chats.removeWhere((item) => item['id'] == saved['id']);
      chats.insert(0, saved);
      await database.saveLocalValue(key, jsonEncode(chats));
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
