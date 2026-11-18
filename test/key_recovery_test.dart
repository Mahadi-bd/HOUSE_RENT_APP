import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/database_key_exceptions.dart';
import 'package:rent_solution/core/security/local_secrets.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/open_database.dart';

const _keyA = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _keyB = '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0';

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('rent_solution_key_');
    file = File('${dir.path}/rent_solution.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a genuinely new database gets a new key, saved for next time', () async {
    final store = MemoryKeyValueStore();
    final secrets = LocalSecrets(store: store);
    final key = await secrets.databasePassphrase(databaseExists: false);
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await secrets.databasePassphrase(databaseExists: true), key);
  });

  test('an existing database with a missing key NEVER gets a silent replacement key', () async {
    final store = MemoryKeyValueStore();
    final secrets = LocalSecrets(store: store);
    await expectLater(
      secrets.databasePassphrase(databaseExists: true),
      throwsA(isA<DatabaseKeyMissingException>()),
    );
    expect(await store.read('db_passphrase_v1'), isNull);
  });

  test('a damaged stored key counts as missing and is not overwritten', () async {
    final store = MemoryKeyValueStore();
    await store.write('db_passphrase_v1', 'not-a-valid-key');
    await expectLater(
      LocalSecrets(store: store).databasePassphrase(databaseExists: true),
      throwsA(isA<DatabaseKeyMissingException>()),
    );
    expect(await store.read('db_passphrase_v1'), 'not-a-valid-key');
  });

  test('open: key lost for an existing file -> recovery error, file untouched', () async {
    final first = openEncryptedDatabase(file, _keyA);
    await first.customSelect('SELECT count(*) FROM sqlite_master').get();
    await first.close();
    final before = file.readAsBytesSync();

    await expectLater(
      openAppDatabase(LocalSecrets(store: MemoryKeyValueStore()), fileOverride: file),
      throwsA(isA<DatabaseKeyMissingException>()),
    );
    expect(file.readAsBytesSync(), before);
  });

  test('open: a stored key that does not open the file -> invalid-key error, file untouched', () async {
    final first = openEncryptedDatabase(file, _keyA);
    await first.customSelect('SELECT count(*) FROM sqlite_master').get();
    await first.close();
    final before = file.readAsBytesSync();

    final store = MemoryKeyValueStore();
    await store.write('db_passphrase_v1', _keyB);
    await expectLater(
      openAppDatabase(LocalSecrets(store: store), fileOverride: file),
      throwsA(isA<DatabaseKeyInvalidException>()),
    );
    expect(file.readAsBytesSync(), before);
    expect(await store.read('db_passphrase_v1'), _keyB);
  });

  test('open: a new file with no key creates one and works', () async {
    final store = MemoryKeyValueStore();
    final db = await openAppDatabase(LocalSecrets(store: store), fileOverride: file);
    await db.customSelect('SELECT count(*) FROM sqlite_master').get();
    await db.close();
    expect(await store.read('db_passphrase_v1'), isNotNull);
    expect(file.existsSync(), isTrue);
  });
}
