import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/core/utils/id_numbers.dart';

void main() {
  final key = List<int>.generate(32, (i) => i);
  final other = List<int>.generate(32, (i) => 255 - i);
  final plain = Uint8List.fromList(List<int>.generate(2000, (i) => i % 251));

  group('VaultCrypto (AES-256-GCM)', () {
    test('round trip; the ciphertext does not contain the plain data', () async {
      final crypto = VaultCrypto(key);
      final box = await crypto.encrypt(plain, 'doc-1');
      expect(box.length, plain.length + 1 + 12 + 16);
      expect(box[0], 1);
      expect(await crypto.decrypt(box, 'doc-1'), plain);
      expect(box.sublist(13, 63), isNot(plain.sublist(0, 50)));
    });

    test('every encryption uses a new random nonce', () async {
      final crypto = VaultCrypto(key);
      final a = await crypto.encrypt(plain, 'doc-1');
      final b = await crypto.encrypt(plain, 'doc-1');
      expect(a.sublist(1, 13), isNot(b.sublist(1, 13)));
    });

    test('a wrong key, a changed byte, a swapped document id or a short file all fail', () async {
      final box = await VaultCrypto(key).encrypt(plain, 'doc-1');
      await expectLater(VaultCrypto(other).decrypt(box, 'doc-1'), throwsA(isA<DocumentTamperedException>()));
      final flipped = Uint8List.fromList(box)..[100] ^= 1;
      await expectLater(VaultCrypto(key).decrypt(flipped, 'doc-1'), throwsA(isA<DocumentTamperedException>()));
      await expectLater(VaultCrypto(key).decrypt(box, 'doc-2'), throwsA(isA<DocumentTamperedException>()));
      await expectLater(
        VaultCrypto(key).decrypt(Uint8List.fromList([1, 2, 3]), 'doc-1'),
        throwsA(isA<DocumentTamperedException>()),
      );
    });
  });

  group('VaultKeyStore', () {
    test('creates a key once for new data and reuses it', () async {
      final store = MemoryKeyValueStore();
      final keys = VaultKeyStore(store);
      final box = await (await keys.crypto(encryptedDataExists: false)).encrypt(plain, 'd');
      final again = await keys.crypto(encryptedDataExists: true);
      expect(await again.decrypt(box, 'd'), plain);
    });

    test('never replaces a lost key when encrypted data exists', () async {
      final store = MemoryKeyValueStore();
      await expectLater(
        VaultKeyStore(store).crypto(encryptedDataExists: true),
        throwsA(isA<VaultKeyMissingException>()),
      );
      expect(await store.read('vault_key_v1'), isNull);
      await store.write('vault_key_v1', 'not base64 !!');
      await expectLater(
        VaultKeyStore(store).crypto(encryptedDataExists: true),
        throwsA(isA<VaultKeyMissingException>()),
      );
    });
  });

  group('ID numbers', () {
    test('NID: 10, 13 or 17 digits, any digit script, spaces allowed', () {
      expect(normalizeNid('1234567890'), '1234567890');
      expect(normalizeNid('123 456 7890'), '1234567890');
      expect(normalizeNid('১২৩৪৫৬৭৮৯০'), '1234567890');
      expect(normalizeNid('1990123456789'), '1990123456789');
      expect(normalizeNid('19901234567890123'), '19901234567890123');
    });

    test('NID: other lengths and letters are refused', () {
      for (final bad in ['', '123', '12345678901', '123456789a', '123456789012345']) {
        expect(normalizeNid(bad), isNull, reason: bad);
      }
    });

    test('other ids: letters and digits, 6 to 20 characters', () {
      expect(normalizeOtherId('ab 123456'), 'AB123456');
      expect(normalizeOtherId('12'), isNull);
      expect(normalizeOtherId('abc!def'), isNull);
    });
  });
}
