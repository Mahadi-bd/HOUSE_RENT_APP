import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A tiny key-value store. Production uses the Keystore/Keychain; tests use memory.
abstract interface class KeyValueStore {
  /// Reads [key], or null when missing.
  Future<String?> read(String key);

  /// Writes [value] under [key].
  Future<void> write(String key, String value);
}

/// Keystore (Android) / Keychain (iOS) backed store.
class SecureKeyValueStore implements KeyValueStore {
  /// Creates the store.
  const SecureKeyValueStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

/// In-memory store for tests.
class MemoryKeyValueStore implements KeyValueStore {
  /// Creates an empty store.
  MemoryKeyValueStore();

  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}
