// Run on a real Android device or iPhone: flutter test integration_test/keystore_database_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rent_solution/core/security/local_secrets.dart';
import 'package:rent_solution/data/local/open_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('key lives in Keystore/Keychain and the database file is encrypted', (tester) async {
    final secrets = LocalSecrets(); // real Keystore (Android) / Keychain (iOS)
    final key = await secrets.databasePassphrase(databaseExists: false);
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await secrets.databasePassphrase(databaseExists: true), key);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/it_encrypted.db');
    if (file.existsSync()) {
      file.deleteSync();
    }
    final db = openEncryptedDatabase(file, key);
    final cipher = await db.customSelect('PRAGMA cipher;').get();
    expect(cipher.single.data.values.single, databaseCipher);
    await db.close();

    final header = String.fromCharCodes(file.readAsBytesSync().take(15));
    expect(header, isNot('SQLite format 3'));

    final wrong = openEncryptedDatabase(file, '0' * 64);
    await expectLater(wrong.customSelect('SELECT count(*) FROM sqlite_master').get(), throwsA(anything));
    file.deleteSync();
  });
}
