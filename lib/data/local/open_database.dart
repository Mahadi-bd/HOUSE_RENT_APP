import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rent_solution/core/security/database_key_exceptions.dart';
import 'package:rent_solution/core/security/local_secrets.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Secrets store (database key, device id).
final localSecretsProvider = Provider<LocalSecrets>((ref) => LocalSecrets());

/// Cipher used by the encrypted database: SQLCipher-compatible AES-256.
const databaseCipher = 'sqlcipher';

/// Runs on every new connection, BEFORE any other statement.
/// 1. Refuses to continue when the encrypted SQLite build is not present (no plain fallback).
/// 2. Selects the cipher and applies the key.
/// 3. Forces a read so a wrong key fails right here instead of later.
void Function(Database) encryptionSetup(String passphrase) {
  return (rawDb) {
    if (rawDb.select('PRAGMA cipher;').isEmpty) {
      throw StateError(
        'Encrypted SQLite is not available. Check the hooks block in pubspec.yaml.',
      );
    }
    rawDb
      ..execute("PRAGMA cipher = '$databaseCipher';")
      ..execute("PRAGMA key = '$passphrase';");
    final active = rawDb.select('PRAGMA cipher;');
    if (active.isEmpty || active.first.values.first != databaseCipher) {
      throw StateError('The database cipher could not be set to $databaseCipher.');
    }
    // Throws SqliteException (file is not a database) when the key is wrong.
    rawDb.select('SELECT count(*) FROM sqlite_master;');
  };
}

/// Opens (or creates) an encrypted database file with [passphrase].
AppDatabase openEncryptedDatabase(File file, String passphrase) {
  return AppDatabase(NativeDatabase(file, setup: encryptionSetup(passphrase)));
}

/// Opens the app database in the documents folder, in a background isolate.
/// Never replaces a missing key for an existing database (see [DatabaseKeyMissingException]);
/// a key that does not open the file gives [DatabaseKeyInvalidException]. The file is never
/// deleted or changed.
Future<AppDatabase> openAppDatabase(LocalSecrets secrets, {File? fileOverride}) async {
  final file = fileOverride ?? File(p.join((await getApplicationDocumentsDirectory()).path, 'rent_solution.db'));
  final passphrase = await secrets.databasePassphrase(databaseExists: file.existsSync());
  final db = AppDatabase(
    NativeDatabase.createInBackground(file, setup: encryptionSetup(passphrase)),
  );
  try {
    await db.customSelect('SELECT count(*) AS c FROM sqlite_master').get();
  } on Object {
    await db.close().catchError((Object _) {});
    throw const DatabaseKeyInvalidException();
  }
  return db;
}

/// The open database, shared across the app.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await openAppDatabase(ref.watch(localSecretsProvider));
  ref.onDispose(db.close);
  return db;
});
