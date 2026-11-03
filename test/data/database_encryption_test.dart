import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oravi_app/data/database/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test(
    'existing plaintext database is converted and requires its encryption key',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'oravi-encryption-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}oravi.sqlite',
      );
      const key = 'test-key-0123456789abcdef0123456789abcdef';

      final plaintext = sqlite3.sqlite3.open(file.path);
      plaintext.execute('CREATE TABLE clinical_events (note TEXT)');
      plaintext.execute(
        "INSERT INTO clinical_events VALUES ('private test note')",
      );
      plaintext.close();

      await OraviLocalDatabase.prepareEncryptedDatabase(file, key);

      final encrypted = sqlite3.sqlite3.open(file.path);
      try {
        encrypted.execute("PRAGMA key = '$key'");
        final rows = encrypted.select('SELECT note FROM clinical_events');
        expect(rows.single['note'], 'private test note');
      } finally {
        encrypted.close();
      }

      final withoutKey = sqlite3.sqlite3.open(file.path);
      try {
        expect(
          () => withoutKey.select('SELECT note FROM clinical_events'),
          throwsA(isA<sqlite3.SqliteException>()),
        );
      } finally {
        withoutKey.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
