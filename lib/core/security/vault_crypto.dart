import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';

/// A sensitive document was changed on disk or opened with the wrong key.
class DocumentTamperedException implements Exception {
  /// Creates the exception.
  const DocumentTamperedException();

  @override
  String toString() => 'DocumentTamperedException';
}

/// The vault key is gone but encrypted documents still exist. No new key is made silently.
class VaultKeyMissingException implements Exception {
  /// Creates the exception.
  const VaultKeyMissingException();

  @override
  String toString() => 'VaultKeyMissingException';
}

/// AES-256-GCM for sensitive documents. File layout: 1 byte version, 12 bytes nonce,
/// encrypted data, 16 bytes authentication tag. The document id is bound in as associated data,
/// so a file cannot be swapped with another document's file.
class VaultCrypto {
  /// Creates the crypto with a 32-byte [key].
  VaultCrypto(List<int> key)
      : assert(key.length == 32, 'The vault key must be 32 bytes'),
        _key = SecretKey(List<int>.unmodifiable(key));

  final SecretKey _key;
  static const _version = 1;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static final _algo = AesGcm.with256bits();

  /// Encrypts [plain] for the document [documentId].
  Future<Uint8List> encrypt(Uint8List plain, String documentId) async {
    final box = await _algo.encrypt(plain, secretKey: _key, aad: utf8.encode(documentId));
    return Uint8List.fromList([_version, ...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Decrypts a file made by [encrypt]. Throws [DocumentTamperedException] for a wrong key,
  /// a changed file or a file that belongs to another document.
  Future<Uint8List> decrypt(Uint8List data, String documentId) async {
    if (data.length < 1 + _nonceLength + _macLength || data[0] != _version) {
      throw const DocumentTamperedException();
    }
    final nonce = data.sublist(1, 1 + _nonceLength);
    final mac = data.sublist(data.length - _macLength);
    final cipher = data.sublist(1 + _nonceLength, data.length - _macLength);
    try {
      final clear = await _algo.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: _key,
        aad: utf8.encode(documentId),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const DocumentTamperedException();
    }
  }
}

/// Keeps the vault key in the Keystore/Keychain. Phase 3 hands this key to members whom an
/// Admin approves for vault access (see the scoped key design).
class VaultKeyStore {
  /// Creates the key store.
  const VaultKeyStore(this._store);

  final KeyValueStore _store;
  static const _name = 'vault_key_v1';

  /// The vault key. A new key is created only when no encrypted data exists yet
  /// ([encryptedDataExists] false). Otherwise a missing key throws [VaultKeyMissingException].
  Future<VaultCrypto> crypto({required bool encryptedDataExists}) async {
    final saved = await _store.read(_name);
    if (saved != null) {
      try {
        final bytes = base64Decode(saved);
        if (bytes.length == 32) {
          return VaultCrypto(bytes);
        }
      } on FormatException {
        // fall through: treat as missing
      }
    }
    if (encryptedDataExists) {
      throw const VaultKeyMissingException();
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _store.write(_name, base64Encode(bytes));
    return VaultCrypto(bytes);
  }
}
