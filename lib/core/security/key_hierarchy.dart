import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:rent_solution/core/permissions/role.dart';

/// Names of key scopes: `org`, `vault`, `property:<id>`, `tenant:<id>`.
abstract final class Scope {
  /// Organization-wide basic data (business profile, settings).
  static const org = 'org';

  /// Private tenant data (NID, address, documents).
  static const vault = 'vault';

  /// One property.
  static String property(String id) => 'property:$id';

  /// One tenant record.
  static String tenant(String id) => 'tenant:$id';
}

/// What a member is allowed to see, used to decide which keys they receive.
class AccessProfile {
  /// Creates a profile.
  const AccessProfile({
    required this.uid,
    required this.role,
    this.propertyIds = const {},
    this.linkedTenantId,
    this.vaultAccess = false,
  });

  /// Firebase uid.
  final String uid;

  /// Role.
  final Role role;

  /// Property ids for staff. Empty means every property.
  final Set<String> propertyIds;

  /// The one tenant record a tenant member may see.
  final String? linkedTenantId;

  /// Approved for private data.
  final bool vaultAccess;
}

/// Which scopes a member holds keys for. [allProperties] is every property of the organization and
/// [tenantProperty] maps each tenant id to its property id.
Set<String> scopesFor(
  AccessProfile who, {
  required Set<String> allProperties,
  required Map<String, String> tenantProperty,
}) {
  final scopes = <String>{Scope.org};
  switch (who.role) {
    case Role.owner:
    case Role.admin:
      scopes
        ..add(Scope.vault)
        ..addAll(allProperties.map(Scope.property))
        ..addAll(tenantProperty.keys.map(Scope.tenant));
    case Role.manager:
    case Role.caretaker:
      final props = who.propertyIds.isEmpty ? allProperties : who.propertyIds.intersection(allProperties);
      scopes.addAll(props.map(Scope.property));
      for (final entry in tenantProperty.entries) {
        if (props.contains(entry.value)) {
          scopes.add(Scope.tenant(entry.key));
        }
      }
      if (who.vaultAccess) {
        scopes.add(Scope.vault);
      }
    case Role.tenant:
      final own = who.linkedTenantId;
      if (own != null) {
        scopes.add(Scope.tenant(own));
      }
  }
  return scopes;
}

/// Keys of every epoch a holder knows: epoch number -> scope -> 32-byte key.
class KeyRing {
  /// Creates a ring.
  KeyRing([Map<int, Map<String, List<int>>>? keys]) : _keys = keys ?? {};

  /// Restores a ring from [toJson].
  factory KeyRing.fromJson(Map<String, dynamic> json) {
    final ring = KeyRing();
    (json['keys'] as Map<String, dynamic>).forEach((epoch, scopes) {
      ring._keys[int.parse(epoch)] = {
        for (final e in (scopes as Map<String, dynamic>).entries) e.key: base64Decode(e.value as String),
      };
    });
    return ring;
  }

  final Map<int, Map<String, List<int>>> _keys;

  /// The newest epoch in this ring (0 if empty).
  int get latestEpoch => _keys.keys.fold(0, max);

  /// The key of [scope] at [epoch], or null if this holder never received it.
  List<int>? keyFor(int epoch, String scope) => _keys[epoch]?[scope];

  /// Scopes this ring holds at [epoch].
  Set<String> scopesAt(int epoch) => _keys[epoch]?.keys.toSet() ?? {};

  /// Adds a key.
  void put(int epoch, String scope, List<int> key) =>
      (_keys[epoch] ??= {})[scope] = List<int>.unmodifiable(key);

  /// A copy that keeps only the scopes in [allowed] (every epoch).
  KeyRing restrictedTo(Set<String> allowed) {
    final copy = KeyRing();
    _keys.forEach((epoch, scopes) {
      scopes.forEach((scope, key) {
        if (allowed.contains(scope)) {
          copy.put(epoch, scope, key);
        }
      });
    });
    return copy;
  }

  /// JSON form (keys in base64). Treat it as a secret.
  Map<String, dynamic> toJson() => {
        'keys': {
          for (final e in _keys.entries)
            '${e.key}': {for (final s in e.value.entries) s.key: base64Encode(s.value)},
        },
      };

  /// Creates a ring that has fresh random keys for [scopes] at [epoch].
  static KeyRing generate(int epoch, Set<String> scopes) {
    final ring = KeyRing();
    for (final scope in scopes) {
      ring.put(epoch, scope, randomKey());
    }
    return ring;
  }

  /// A fresh random 32-byte key.
  static List<int> randomKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }
}

/// A member's long-term key pair (X25519). The private part stays in the Keystore/Keychain.
class MemberKeyPair {
  MemberKeyPair._(this._pair, this.publicKey);

  final SimpleKeyPair _pair;

  /// The public half, stored on the member record so admins can wrap keys for them.
  final SimplePublicKey publicKey;

  /// Makes a new key pair.
  static Future<MemberKeyPair> generate() async {
    final pair = await X25519().newKeyPair();
    return MemberKeyPair._(pair, await pair.extractPublicKey());
  }
}

/// A key ring wrapped for one recipient (stored in `grants/{uid}`).
class GrantBundle {
  /// Creates a bundle.
  const GrantBundle({required this.ephemeralPublicKey, required this.nonce, required this.cipherText});

  /// Restores a bundle from [encode].
  factory GrantBundle.decode(String text) {
    final m = jsonDecode(utf8.decode(base64Decode(text))) as Map<String, dynamic>;
    return GrantBundle(
      ephemeralPublicKey: base64Decode(m['e'] as String),
      nonce: base64Decode(m['n'] as String),
      cipherText: base64Decode(m['c'] as String),
    );
  }

  /// Sender's one-time public key.
  final List<int> ephemeralPublicKey;

  /// AES-GCM nonce.
  final List<int> nonce;

  /// Encrypted ring with its authentication tag.
  final List<int> cipherText;

  /// One text value for Firestore.
  String encode() => base64Encode(
        utf8.encode(jsonEncode({'e': base64Encode(ephemeralPublicKey), 'n': base64Encode(nonce), 'c': base64Encode(cipherText)})),
      );
}

/// Wrapping, unwrapping, rotating and using keys. Only the Admin device creates grants; each member's
/// device unwraps its own. All algorithms: X25519 + HKDF-SHA256 for wrapping, AES-256-GCM for data.
abstract final class KeyHierarchy {
  static final _gcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<SecretKey> _wrapKey(SecretKey shared, String orgId, String uid) =>
      _hkdf.deriveKey(secretKey: shared, nonce: utf8.encode('rent-solution-grant-v1'), info: utf8.encode('$orgId|$uid'));

  /// Wraps [ring] so only the holder of [recipient]'s private key can open it.
  static Future<GrantBundle> wrap(
    KeyRing ring, {
    required SimplePublicKey recipient,
    required String orgId,
    required String recipientUid,
  }) async {
    final ephemeral = await X25519().newKeyPair();
    final shared = await X25519().sharedSecretKey(keyPair: ephemeral, remotePublicKey: recipient);
    final box = await _gcm.encrypt(
      utf8.encode(jsonEncode(ring.toJson())),
      secretKey: await _wrapKey(shared, orgId, recipientUid),
      aad: utf8.encode('$orgId|$recipientUid'),
    );
    return GrantBundle(
      ephemeralPublicKey: (await ephemeral.extractPublicKey()).bytes,
      nonce: box.nonce,
      cipherText: [...box.cipherText, ...box.mac.bytes],
    );
  }

  /// Opens a bundle. Throws [SecretBoxAuthenticationError] for a wrong key or a changed bundle.
  static Future<KeyRing> unwrap(
    GrantBundle bundle, {
    required MemberKeyPair mine,
    required String orgId,
    required String myUid,
  }) async {
    final shared = await X25519().sharedSecretKey(
      keyPair: mine._pair,
      remotePublicKey: SimplePublicKey(bundle.ephemeralPublicKey, type: KeyPairType.x25519),
    );
    final c = bundle.cipherText;
    final clear = await _gcm.decrypt(
      SecretBox(c.sublist(0, c.length - 16), nonce: bundle.nonce, mac: Mac(c.sublist(c.length - 16))),
      secretKey: await _wrapKey(shared, orgId, myUid),
      aad: utf8.encode('$orgId|$myUid'),
    );
    return KeyRing.fromJson(jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
  }

  /// Starts a new key epoch for every scope. [admin] is the full ring of the Admin device (all older
  /// epochs). The result has, per remaining member, a ring with the NEW keys of the scopes that member may
  /// see, plus the old keys of the same scopes (so old data stays readable). A removed member simply gets
  /// nothing: they keep the old keys they already had, which cannot open anything created from now on.
  static Map<String, KeyRing> rotate({
    required KeyRing admin,
    required List<AccessProfile> remaining,
    required Set<String> allProperties,
    required Map<String, String> tenantProperty,
  }) {
    final newEpoch = admin.latestEpoch + 1;
    final everything = <String>{
      Scope.org,
      Scope.vault,
      ...allProperties.map(Scope.property),
      ...tenantProperty.keys.map(Scope.tenant),
    };
    for (final scope in everything) {
      admin.put(newEpoch, scope, KeyRing.randomKey());
    }
    return {
      for (final member in remaining)
        member.uid: admin.restrictedTo(scopesFor(member, allProperties: allProperties, tenantProperty: tenantProperty)),
    };
  }

  static List<int> _aad(String orgId, String scope, int epoch, String opId, String senderUid) =>
      utf8.encode('$orgId|$scope|$epoch|$opId|$senderUid');

  /// Encrypts an operation for [scope] with the current epoch key. Throws StateError when this holder has no key.
  static Future<({String nonce, String ciphertext, int epoch})> encryptOp(
    KeyRing ring, {
    required String orgId,
    required String scope,
    required String opId,
    required String senderUid,
    required Uint8List plain,
    int? epoch,
  }) async {
    final e = epoch ?? ring.latestEpoch;
    final key = ring.keyFor(e, scope);
    if (key == null) {
      throw StateError('No key for $scope at epoch $e.');
    }
    final box = await _gcm.encrypt(plain, secretKey: SecretKey(key), aad: _aad(orgId, scope, e, opId, senderUid));
    return (
      nonce: base64Encode(box.nonce),
      ciphertext: base64Encode([...box.cipherText, ...box.mac.bytes]),
      epoch: e,
    );
  }

  /// Decrypts an operation. Throws StateError (no key) or [SecretBoxAuthenticationError] (wrong key or changed data).
  static Future<Uint8List> decryptOp(
    KeyRing ring, {
    required String orgId,
    required String scope,
    required int epoch,
    required String opId,
    required String senderUid,
    required String nonce,
    required String ciphertext,
  }) async {
    final key = ring.keyFor(epoch, scope);
    if (key == null) {
      throw StateError('No key for $scope at epoch $epoch.');
    }
    final c = base64Decode(ciphertext);
    final clear = await _gcm.decrypt(
      SecretBox(c.sublist(0, c.length - 16), nonce: base64Decode(nonce), mac: Mac(c.sublist(c.length - 16))),
      secretKey: SecretKey(key),
      aad: _aad(orgId, scope, epoch, opId, senderUid),
    );
    return Uint8List.fromList(clear);
  }
}
