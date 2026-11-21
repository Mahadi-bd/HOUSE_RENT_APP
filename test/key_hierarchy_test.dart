import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/key_hierarchy.dart';

void main() {
  const org = 'org1';
  final props = {'p1', 'p2'};
  final tenants = {'t1': 'p1', 't2': 'p2', 't3': 'p1'};
  Set<String> scopes(AccessProfile a) => scopesFor(a, allProperties: props, tenantProperty: tenants);
  final plain = Uint8List.fromList(List.generate(64, (i) => i));

  group('which scopes each member holds', () {
    test('owner and admin hold everything including the vault', () {
      final all = {Scope.org, Scope.vault, 'property:p1', 'property:p2', 'tenant:t1', 'tenant:t2', 'tenant:t3'};
      expect(scopes(const AccessProfile(uid: 'o', role: Role.owner)), all);
      expect(scopes(const AccessProfile(uid: 'a', role: Role.admin)), all);
    });

    test('an unscoped manager holds every property and tenant but not the vault', () {
      final s = scopes(const AccessProfile(uid: 'm', role: Role.manager));
      expect(s, containsAll(['property:p1', 'property:p2', 'tenant:t1', 'tenant:t2', 'tenant:t3']));
      expect(s, isNot(contains(Scope.vault)));
    });

    test('a manager or caretaker scoped to p1 holds only p1 and its tenants', () {
      for (final role in [Role.manager, Role.caretaker]) {
        final s = scopes(AccessProfile(uid: 'x', role: role, propertyIds: const {'p1'}));
        expect(s, {Scope.org, 'property:p1', 'tenant:t1', 'tenant:t3'});
      }
    });

    test('vault key only with approved vault access', () {
      expect(scopes(const AccessProfile(uid: 'm', role: Role.manager, vaultAccess: true)), contains(Scope.vault));
      expect(scopes(const AccessProfile(uid: 'm', role: Role.manager)), isNot(contains(Scope.vault)));
    });

    test('a tenant holds only the organization key and its own tenant key', () {
      expect(scopes(const AccessProfile(uid: 't', role: Role.tenant, linkedTenantId: 't1')), {Scope.org, 'tenant:t1'});
      expect(scopes(const AccessProfile(uid: 't', role: Role.tenant)), {Scope.org});
    });
  });

  group('wrapping keys for a member', () {
    test('only the intended member can open a bundle; a changed bundle fails', () async {
      final alice = await MemberKeyPair.generate();
      final bob = await MemberKeyPair.generate();
      final ring = KeyRing.generate(1, {Scope.org, 'tenant:t1'});
      final bundle = await KeyHierarchy.wrap(ring, recipient: alice.publicKey, orgId: org, recipientUid: 'alice');
      final opened = await KeyHierarchy.unwrap(GrantBundle.decode(bundle.encode()), mine: alice, orgId: org, myUid: 'alice');
      expect(opened.keyFor(1, Scope.org), ring.keyFor(1, Scope.org));
      expect(opened.keyFor(1, 'tenant:t1'), ring.keyFor(1, 'tenant:t1'));
      await expectLater(KeyHierarchy.unwrap(bundle, mine: bob, orgId: org, myUid: 'alice'), throwsA(isA<SecretBoxAuthenticationError>()));
      await expectLater(KeyHierarchy.unwrap(bundle, mine: alice, orgId: org, myUid: 'bob'), throwsA(isA<SecretBoxAuthenticationError>()));
      final tampered = GrantBundle(
        ephemeralPublicKey: bundle.ephemeralPublicKey,
        nonce: bundle.nonce,
        cipherText: [...bundle.cipherText]..[3] ^= 1,
      );
      await expectLater(KeyHierarchy.unwrap(tampered, mine: alice, orgId: org, myUid: 'alice'), throwsA(isA<SecretBoxAuthenticationError>()));
    });
  });

  group('encrypting operations', () {
    test('round trip with the right key; wrong scope, sender, operation id or epoch fail', () async {
      final ring = KeyRing.generate(1, {Scope.org, 'property:p1'});
      final box = await KeyHierarchy.encryptOp(ring, orgId: org, scope: 'property:p1', opId: 'op1', senderUid: 'u1', plain: plain);
      Future<Uint8List> open({String scope = 'property:p1', String op = 'op1', String sender = 'u1', int epoch = 1}) =>
          KeyHierarchy.decryptOp(ring, orgId: org, scope: scope, epoch: epoch, opId: op, senderUid: sender, nonce: box.nonce, ciphertext: box.ciphertext);
      expect(await open(), plain);
      await expectLater(open(scope: Scope.org), throwsA(isA<SecretBoxAuthenticationError>()));
      await expectLater(open(op: 'op2'), throwsA(isA<SecretBoxAuthenticationError>()));
      await expectLater(open(sender: 'u2'), throwsA(isA<SecretBoxAuthenticationError>()));
      await expectLater(open(epoch: 2), throwsStateError);
    });

    test('a holder without the key cannot even try', () async {
      final ring = KeyRing.generate(1, {Scope.org});
      await expectLater(
        KeyHierarchy.encryptOp(ring, orgId: org, scope: 'tenant:t2', opId: 'op', senderUid: 'u', plain: plain),
        throwsStateError,
      );
    });
  });

  group('revocation and key rotation', () {
    late KeyRing adminRing;
    final mgrP1 = const AccessProfile(uid: 'mgr', role: Role.manager, propertyIds: {'p1'});
    final careAll = const AccessProfile(uid: 'care', role: Role.caretaker);
    final tenant1 = const AccessProfile(uid: 'ten', role: Role.tenant, linkedTenantId: 't1');

    setUp(() {
      adminRing = KeyRing.generate(1, {Scope.org, Scope.vault, 'property:p1', 'property:p2', 'tenant:t1', 'tenant:t2', 'tenant:t3'});
    });

    test('a revoked member keeps old keys but cannot read anything created after the rotation', () async {
      final mgrRingBefore = adminRing.restrictedTo(scopes(mgrP1));
      final oldBox = await KeyHierarchy.encryptOp(adminRing, orgId: org, scope: 'property:p1', opId: 'old', senderUid: 'admin', plain: plain);
      final grants = KeyHierarchy.rotate(admin: adminRing, remaining: [careAll, tenant1], allProperties: props, tenantProperty: tenants);
      expect(adminRing.latestEpoch, 2);
      expect(grants.containsKey('mgr'), isFalse);

      final newBox = await KeyHierarchy.encryptOp(adminRing, orgId: org, scope: 'property:p1', opId: 'new', senderUid: 'admin', plain: plain);
      expect(newBox.epoch, 2);
      // The revoked member can still open OLD data (they already had it)...
      expect(
        await KeyHierarchy.decryptOp(mgrRingBefore, orgId: org, scope: 'property:p1', epoch: 1, opId: 'old', senderUid: 'admin', nonce: oldBox.nonce, ciphertext: oldBox.ciphertext),
        plain,
      );
      // ...but has no key for the new epoch, and the old key does not open new data.
      expect(mgrRingBefore.keyFor(2, 'property:p1'), isNull);
      await expectLater(
        KeyHierarchy.decryptOp(mgrRingBefore, orgId: org, scope: 'property:p1', epoch: 2, opId: 'new', senderUid: 'admin', nonce: newBox.nonce, ciphertext: newBox.ciphertext),
        throwsStateError,
      );
      final forged = KeyRing()..put(2, 'property:p1', mgrRingBefore.keyFor(1, 'property:p1')!);
      await expectLater(
        KeyHierarchy.decryptOp(forged, orgId: org, scope: 'property:p1', epoch: 2, opId: 'new', senderUid: 'admin', nonce: newBox.nonce, ciphertext: newBox.ciphertext),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('remaining members get new keys for their scopes and keep reading old data', () async {
      final oldBox = await KeyHierarchy.encryptOp(adminRing, orgId: org, scope: 'tenant:t1', opId: 'old', senderUid: 'admin', plain: plain);
      final grants = KeyHierarchy.rotate(admin: adminRing, remaining: [careAll, tenant1], allProperties: props, tenantProperty: tenants);
      final newBox = await KeyHierarchy.encryptOp(adminRing, orgId: org, scope: 'tenant:t1', opId: 'new', senderUid: 'admin', plain: plain);
      final tenantRing = grants['ten']!;
      expect(
        await KeyHierarchy.decryptOp(tenantRing, orgId: org, scope: 'tenant:t1', epoch: 1, opId: 'old', senderUid: 'admin', nonce: oldBox.nonce, ciphertext: oldBox.ciphertext),
        plain,
      );
      expect(
        await KeyHierarchy.decryptOp(tenantRing, orgId: org, scope: 'tenant:t1', epoch: 2, opId: 'new', senderUid: 'admin', nonce: newBox.nonce, ciphertext: newBox.ciphertext),
        plain,
      );
    });

    test('rotation gives every scope a brand new key', () {
      final before = {for (final s in adminRing.scopesAt(1)) s: adminRing.keyFor(1, s)!};
      KeyHierarchy.rotate(admin: adminRing, remaining: const [], allProperties: props, tenantProperty: tenants);
      for (final s in before.keys) {
        expect(adminRing.keyFor(2, s), isNot(before[s]), reason: s);
      }
    });

    test('scope isolation survives rotation: others never receive keys outside their scope', () {
      final grants = KeyHierarchy.rotate(
        admin: adminRing,
        remaining: [mgrP1, careAll, tenant1],
        allProperties: props,
        tenantProperty: tenants,
      );
      expect(grants['mgr']!.scopesAt(2), {Scope.org, 'property:p1', 'tenant:t1', 'tenant:t3'});
      expect(grants['care']!.scopesAt(2), isNot(contains(Scope.vault)));
      expect(grants['ten']!.scopesAt(2), {Scope.org, 'tenant:t1'});
      expect(grants['ten']!.scopesAt(1), {Scope.org, 'tenant:t1'});
    });

    test('a member whose vault access was removed gets no new vault key', () {
      const lost = AccessProfile(uid: 'm', role: Role.manager, vaultAccess: false);
      final grants = KeyHierarchy.rotate(admin: adminRing, remaining: [lost], allProperties: props, tenantProperty: tenants);
      expect(grants['m']!.keyFor(2, Scope.vault), isNull);
    });

    test('rings survive JSON and a full wrap, unwrap cycle', () async {
      final kp = await MemberKeyPair.generate();
      final ring = adminRing.restrictedTo({Scope.org, 'property:p1'});
      final back = KeyRing.fromJson(ring.toJson());
      expect(back.scopesAt(1), {Scope.org, 'property:p1'});
      final bundle = await KeyHierarchy.wrap(ring, recipient: kp.publicKey, orgId: org, recipientUid: 'u');
      final opened = await KeyHierarchy.unwrap(bundle, mine: kp, orgId: org, myUid: 'u');
      expect(opened.keyFor(1, Scope.org), ring.keyFor(1, Scope.org));
    });
  });
}
