import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/documents_repository.dart';

import 'helpers.dart';

// Starts like a PNG so we can check it is NOT visible on disk.
final Uint8List _image = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(500, 7)]);

void main() {
  late AppDatabase db;
  late Directory root;
  late String tenantId;
  late MemoryKeyValueStore keys;

  setUp(() async {
    db = memoryDb();
    root = Directory.systemTemp.createTempSync('rent_solution_docs_');
    keys = MemoryKeyValueStore();
    tenantId = (await seedTenant(db)).tenantId;
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  const owner = ownerAccess;
  DocumentsRepository repo(MemberAccess? access) => documentsFor(db, access, root, keyStore: keys);

  test('a stored document is encrypted on disk and comes back identical', () async {
    final id = await repo(owner).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: '.PNG');
    final row = await db.select(db.documents).getSingle();
    expect(row.sizeBytes, _image.length);
    final onDisk = File('${root.path}/${row.localPath}').readAsBytesSync();
    expect(onDisk.sublist(0, 4), isNot([0x89, 0x50, 0x4E, 0x47]));
    expect(onDisk.length, _image.length + 29);
    expect(await repo(owner).read(id), _image);
  });

  test('only PNG, JPG and PDF up to 10 MB are accepted, and nothing is left behind on failure', () async {
    final r = repo(owner);
    await expectLater(r.store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'exe'), throwsArgumentError);
    await expectLater(r.store(tenantId: tenantId, type: DocumentType.nid, bytes: Uint8List(0), extension: 'png'), throwsArgumentError);
    await expectLater(r.store(tenantId: tenantId, type: DocumentType.nid, bytes: Uint8List(10 * 1024 * 1024 + 1), extension: 'png'), throwsArgumentError);
    await expectLater(r.store(tenantId: 'nope', type: DocumentType.nid, bytes: _image, extension: 'png'), throwsStateError);
    expect(await db.select(db.documents).get(), isEmpty);
    expect(Directory('${root.path}/vault').existsSync() ? Directory('${root.path}/vault').listSync() : [], isEmpty);
  });

  test('who may add: vault-approved staff and admin for sensitive files; manager for the tenant photo', () async {
    await repo(vaultStaff).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg');
    await repo(const MemberAccess(role: Role.manager)).store(tenantId: tenantId, type: DocumentType.photo, bytes: _image, extension: 'jpg');
    await expectLater(repo(const MemberAccess(role: Role.manager)).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg'), throwsA(isA<PermissionDenied>()));
    for (final role in [Role.caretaker, Role.tenant]) {
      await expectLater(repo(MemberAccess(role: role)).store(tenantId: tenantId, type: DocumentType.photo, bytes: _image, extension: 'jpg'), throwsA(isA<PermissionDenied>()));
    }
  });

  test('staff without vault access see only the tenant photo; vault staff and the tenant see all', () async {
    final photo = await repo(owner).store(tenantId: tenantId, type: DocumentType.photo, bytes: _image, extension: 'jpg');
    final nid = await repo(owner).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg');
    for (final role in [Role.manager, Role.caretaker]) {
      final seen = await repo(MemberAccess(role: role)).list(tenantId);
      expect(seen.map((d) => d.id), [photo]);
      await repo(MemberAccess(role: role)).read(photo);
      await expectLater(repo(MemberAccess(role: role)).read(nid), throwsA(isA<PermissionDenied>()));
    }
    expect((await repo(vaultStaff).list(tenantId)).map((d) => d.id).toSet(), {photo, nid});
    final own = MemberAccess(role: Role.tenant, linkedTenantId: tenantId);
    expect((await repo(own).list(tenantId)).length, 2);
    expect(await repo(own).read(nid), _image);
    final other = MemberAccess(role: Role.tenant, linkedTenantId: 'someone-else');
    await expectLater(repo(other).list(tenantId), throwsA(isA<PermissionDenied>()));
    await expectLater(repo(other).read(nid), throwsA(isA<PermissionDenied>()));
  });

  test('a scoped manager cannot reach documents of another property', () async {
    final id = await repo(owner).store(tenantId: tenantId, type: DocumentType.photo, bytes: _image, extension: 'jpg');
    final scoped = MemberAccess(role: Role.manager, propertyScope: {'other'});
    await expectLater(repo(scoped).read(id), throwsA(isA<PermissionDenied>()));
    await expectLater(repo(scoped).list(tenantId), throwsA(isA<PermissionDenied>()));
  });

  test('another organization cannot read or list', () async {
    final id = await repo(owner).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg');
    final intruder = documentsFor(db, owner, root, keyStore: keys, orgId: 'other-org');
    await expectLater(intruder.read(id), throwsStateError);
    await expectLater(intruder.list(tenantId), throwsStateError);
  });

  test('a changed file is detected, and a swapped file is detected', () async {
    final a = await repo(owner).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg');
    final b = await repo(owner).store(tenantId: tenantId, type: DocumentType.lease, bytes: _image, extension: 'pdf');
    final rows = {for (final d in await db.select(db.documents).get()) d.id: d};
    final fileA = File('${root.path}/${rows[a]!.localPath}');
    final fileB = File('${root.path}/${rows[b]!.localPath}');
    final bytes = fileA.readAsBytesSync()..[40] ^= 1;
    fileA.writeAsBytesSync(bytes);
    await expectLater(repo(owner).read(a), throwsA(isA<DocumentTamperedException>()));
    fileA.writeAsBytesSync(fileB.readAsBytesSync());
    await expectLater(repo(owner).read(a), throwsA(isA<DocumentTamperedException>()));
    fileA.deleteSync();
    await expectLater(repo(owner).read(a), throwsStateError);
  });

  test('a lost vault key never creates a new key when documents exist', () async {
    await repo(owner).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg');
    final lost = MemoryKeyValueStore();
    await expectLater(documentsFor(db, owner, root, keyStore: lost).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg'), throwsA(isA<VaultKeyMissingException>()));
    expect(await lost.read('vault_key_v1'), isNull);
  });

  test('removing needs owner/admin and a confirmation for that document; it is archived and audited', () async {
    final id = await repo(owner).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg');
    await expectLater(repo(vaultStaff).remove(id, reason: 'x', confirmation: await confirmed(SensitiveAction.documentRemove, id)), throwsA(isA<PermissionDenied>()));
    await expectLater(repo(owner).remove(id, reason: 'x', confirmation: await confirmed(SensitiveAction.documentRemove, 'another')), throwsA(isA<ConfirmationException>()));
    await repo(owner).remove(id, reason: 'wrong scan', confirmation: await confirmed(SensitiveAction.documentRemove, id));
    expect(await repo(owner).list(tenantId), isEmpty);
    expect(await db.select(db.deletedArchives).get(), hasLength(1));
    final actions = (await db.select(db.auditLogs).get()).map((a) => a.action);
    expect(actions, containsAll(['document.add', 'document.remove']));
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
  });

  test('the audit log holds no file names or contents', () async {
    await repo(owner).store(tenantId: tenantId, type: DocumentType.nid, bytes: _image, extension: 'jpg');
    final audit = (await db.select(db.auditLogs).get()).firstWhere((a) => a.action == 'document.add');
    expect(audit.newValue, allOf(contains('nid'), isNot(contains('vault/'))));
  });
}
