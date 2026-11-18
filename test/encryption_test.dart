// Dedicated tests against the real encrypted SQLite build (SQLite3MultipleCiphers).
// They use a real file, not NativeDatabase.memory(). If the encrypted build is missing,
// these tests FAIL on purpose: the app must never run on plain SQLite.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/local_secrets.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/open_database.dart';

const _marker = 'PLAINTEXT_MARKER_Rahim_Uddin_Khulna';
const _keyA = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _keyB = '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0';

Future<void> _insertOrg(AppDatabase db) {
  final now = DateTime.utc(2026, 11, 9);
  return db.into(db.organizations).insert(
        OrganizationsCompanion.insert(
          id: 'org1',
          orgId: 'org1',
          createdAt: now,
          updatedAt: now,
          createdBy: 'u',
          deviceId: 'd',
          hlc: '1',
          name: _marker,
          ownerUid: 'u',
        ),
      );
}

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rent_solution_enc_');
    file = File('${dir.path}/test.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('the encrypted SQLite build is active and uses the SQLCipher-compatible cipher', () async {
    final db = openEncryptedDatabase(file, _keyA);
    final rows = await db.customSelect('PRAGMA cipher;').get();
    expect(rows.single.data.values.single, databaseCipher);
    await db.close();
  });

  test('data written with the key can be read after closing and reopening', () async {
    final first = openEncryptedDatabase(file, _keyA);
    await _insertOrg(first);
    await first.close();

    final second = openEncryptedDatabase(file, _keyA);
    final org = await second.select(second.organizations).getSingle();
    expect(org.name, _marker);
    await second.close();
  });

  test('a wrong key is rejected by a real query', () async {
    final first = openEncryptedDatabase(file, _keyA);
    await _insertOrg(first);
    await first.close();

    final wrong = openEncryptedDatabase(file, _keyB);
    await expectLater(wrong.select(wrong.organizations).get(), throwsA(anything));
    await wrong.close().catchError((Object _) {});
  });

  test('the file on disk is not a readable SQLite file and hides the data', () async {
    final db = openEncryptedDatabase(file, _keyA);
    await _insertOrg(db);
    await db.close();

    final bytes = file.readAsBytesSync();
    expect(bytes.length, greaterThan(100));
    final header = String.fromCharCodes(bytes.take(15));
    expect(header, isNot('SQLite format 3'));
    expect(String.fromCharCodes(bytes), isNot(contains(_marker)));
  });

  group('LocalSecrets key', () {
    test('is 64 hex characters, stable for one store, different across stores', () async {
      final storeA = MemoryKeyValueStore();
      final a1 = await LocalSecrets(store: storeA).databasePassphrase(databaseExists: false);
      final a2 = await LocalSecrets(store: storeA).databasePassphrase(databaseExists: false);
      final b = await LocalSecrets(store: MemoryKeyValueStore()).databasePassphrase(databaseExists: false);
      expect(a1, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a2, a1);
      expect(b, isNot(a1));
    });

    test('device id is stable per store', () async {
      final store = MemoryKeyValueStore();
      final first = await LocalSecrets(store: store).deviceId();
      expect(await LocalSecrets(store: store).deviceId(), first);
    });
  });
}
