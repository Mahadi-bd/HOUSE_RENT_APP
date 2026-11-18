import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';

void main() {
  final key = List<int>.generate(32, (i) => i);
  final otherKey = List<int>.generate(32, (i) => 255 - i);
  final plain = Uint8List.fromList(List<int>.generate(1000, (i) => i % 251));

  test('encrypt then decrypt returns the same bytes, and the file does not contain them', () async {
    final crypto = VaultCrypto(key);
    final box = await crypto.encrypt(plain, 'doc-1');
    expect(box.length, plain.length + 1 + 12 + 16);
    expect(box, isNot(plain));
    expect(await crypto.decrypt(box, 'doc-1'), plain);
  });

  test('every encryption uses a new nonce', () async {
    final crypto = VaultCrypto(key);
    final a = await crypto.encrypt(plain, 'doc-1');
    final b = await crypto.encrypt(plain, 'doc-1');
    expect(a.sublist(1, 13), isNot(b.sublist(1, 13)));
    expect(a, isNot(b));
  });

  test('the wrong key, a changed file, a changed tag or another document id all fail', () async {
    final crypto = VaultCrypto(key);
    final box = await crypto.encrypt(plain, 'doc-1');
    await expectLater(VaultCrypto(otherKey).decrypt(box, 'doc-1'), throwsA(isA<DocumentTamperedException>()));
    final flipped = Uint8List.fromList(box)..[50] ^= 0x01;
    await expectLater(crypto.decrypt(flipped, 'doc-1'), throwsA(isA<DocumentTamperedException>()));
    final tagFlipped = Uint8List.fromList(box)..[box.length - 1] ^= 0x01;
    await expectLater(crypto.decrypt(tagFlipped, 'doc-1'), throwsA(isA<DocumentTamperedException>()));
    await expectLater(crypto.decrypt(box, 'doc-2'), throwsA(isA<DocumentTamperedException>()));
    await expectLater(crypto.decrypt(Uint8List(5), 'doc-1'), throwsA(isA<DocumentTamperedException>()));
  });

  group('VaultKeyStore', () {
    test('makes a 32-byte key for the first document and then keeps using it', () async {
      final store = MemoryKeyValueStore();
      final first = await VaultKeyStore(store).crypto(encryptedDataExists: false);
      final box = await first.encrypt(plain, 'd');
      final again = await VaultKeyStore(store).crypto(encryptedDataExists: true);
      expect(await again.decrypt(box, 'd'), plain);
    });

    test('never makes a replacement key when encrypted documents already exist', () async {
      final store = MemoryKeyValueStore();
      await expectLater(
        VaultKeyStore(store).crypto(encryptedDataExists: true),
        throwsA(isA<VaultKeyMissingException>()),
      );
      expect(await store.read('vault_key_v1'), isNull);
    });

    test('a damaged key counts as missing', () async {
      final store = MemoryKeyValueStore();
      await store.write('vault_key_v1', 'not base64 !!');
      await expectLater(
        VaultKeyStore(store).crypto(encryptedDataExists: true),
        throwsA(isA<VaultKeyMissingException>()),
      );
    });
  });
}
