import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:oravi_app/data/database/database.dart';

void main() {
  late OraviLocalDatabase db;
  setUp(() => db = OraviLocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('board cache survives writes and updates', () async {
    const key = 'ward_board:WARD-TEST:2026-11-17:day';
    await db.cacheJson(key, {'bed_assignments': [], 'ward_id': 'WARD-TEST'});
    expect((await db.readCachedJson(key))?['ward_id'], 'WARD-TEST');
    expect(await db.getCachedAt(key), isNotNull);
    await db.cacheJson(key, {
      'bed_assignments': [
        {'bed_number': '1'},
      ],
    });
    expect((await db.readCachedJson(key))?['bed_assignments'], hasLength(1));
  });

  test('successful sync timestamp and local preferences persist', () async {
    final time = DateTime.utc(2026, 11, 17, 10);
    await db.saveLastSuccessfulSyncAt(time);
    expect((await db.getLastSuccessfulSyncAt())?.toUtc(), time);
    await db.saveLocalValue('test', 'first');
    await db.saveLocalValue('test', 'second');
    expect(await db.readLocalValue('test'), 'second');
    await db.deleteLocalValue('test');
    expect(await db.readLocalValue('test'), isNull);
  });

  test(
    'queued board publication can fail, retry, and be acknowledged',
    () async {
      await db.enqueueApiOperation(
        operationId: 'publish-1',
        method: 'POST',
        path: '/api/v1/allocations/publish',
        payload: {'ward_id': 'WARD-TEST'},
      );
      expect(await db.getPendingApiOperationCount(), 1);
      await db.markApiOperationInFlight('publish-1');
      expect(await db.getPendingApiOperations(), isEmpty);
      await db.resetStaleApiOperations(staleAfter: Duration.zero);
      expect(await db.getPendingApiOperations(), hasLength(1));
      await db.markApiOperationFailed(
        'publish-1',
        'Unavailable',
        blocked: false,
      );
      expect(
        (await db.getPendingApiOperations()).single.payload['ward_id'],
        'WARD-TEST',
      );
      await db.markApiOperationSynced('publish-1');
      expect(await db.getPendingApiOperationCount(), 0);
    },
  );
}
