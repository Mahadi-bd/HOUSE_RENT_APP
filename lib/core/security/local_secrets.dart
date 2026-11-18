import 'dart:math';

import 'package:rent_solution/core/security/database_key_exceptions.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/core/utils/ids.dart';

/// Device secrets kept in the Android Keystore / iOS Keychain.
class LocalSecrets {
  /// Creates the secret store. Pass a [MemoryKeyValueStore] in tests.
  LocalSecrets({KeyValueStore? store}) : _store = store ?? const SecureKeyValueStore();

  final KeyValueStore _store;

  static const _dbKeyName = 'db_passphrase_v1';
  static const _deviceIdName = 'device_id_v1';

  /// The database key: 32 random bytes from the OS secure random, as 64 hex characters.
  /// A new key is created ONLY for a genuinely new database ([databaseExists] false).
  /// If the database already exists but the key is missing or damaged, this throws
  /// [DatabaseKeyMissingException] and changes nothing, so the old data stays recoverable.
  Future<String> databasePassphrase({required bool databaseExists}) async {
    final existing = await _store.read(_dbKeyName);
    if (existing != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
      return existing;
    }
    if (databaseExists) {
      throw const DatabaseKeyMissingException();
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _store.write(_dbKeyName, key);
    return key;
  }

  /// A stable random id for this installation. Created on first use.
  Future<String> deviceId() async {
    final existing = await _store.read(_deviceIdName);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = newId();
    await _store.write(_deviceIdName, id);
    return id;
  }
}
