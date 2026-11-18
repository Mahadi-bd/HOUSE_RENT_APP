/// The database file exists but its key is gone from the Keystore/Keychain.
/// The app must NOT create a new key: the old data is still on the phone.
class DatabaseKeyMissingException implements Exception {
  /// Creates the exception.
  const DatabaseKeyMissingException();

  @override
  String toString() => 'DatabaseKeyMissingException';
}

/// The database file exists but the stored key does not open it.
class DatabaseKeyInvalidException implements Exception {
  /// Creates the exception.
  const DatabaseKeyInvalidException();

  @override
  String toString() => 'DatabaseKeyInvalidException';
}
