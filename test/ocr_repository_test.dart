import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/ocr_repository.dart';

import 'helpers.dart';

OcrRepository ocrFor(AppDatabase db, MemberAccess? a, Directory root, KeyValueStore keys, [String org = 'org']) {
  final docs = documentsFor(db, a, root, keyStore: keys, orgId: org);
  return OcrRepository(db, guardFor(a), contextAt(testNow, orgId: org), docs, vaultFor(db, a, null, org));
}

void main() {
  late AppDatabase db;
  late Directory root;
  late MemoryKeyValueStore keys;
  late String tenantId;
  final image = Uint8List.fromList(List.filled(300, 9));

  setUp(() async {
    db = memoryDb();
    root = Directory.systemTemp.createTempSync('rent_solution_ocr_');
    keys = MemoryKeyValueStore();
    tenantId = (await seedTenant(db)).tenantId;
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('a reviewed scan saves the NID, the encrypted photo and who confirmed it', () async {
    final scanId = await ocrFor(db, ownerAccess, root, keys).confirmNidScan(
      tenantId: tenantId,
      image: image,
      extension: 'jpg',
      reviewedNid: '1990 1234 56789',
      suggestedNid: '1990123456789',
    );
    expect(scanId, isNotEmpty);
    expect((await vaultFor(db, ownerAccess).get(tenantId))!.nidNo, '1990123456789');
    final doc = await db.select(db.documents).getSingle();
    expect(doc.type, DocumentType.nid);
    final scan = await db.select(db.ocrScans).getSingle();
    expect(scan.confirmedBy, 'owner-uid');
    expect(scan.confirmedAt, isNotNull);
    expect(scan.imageDocId, doc.id);
    expect(scan.extractedJson, contains('"matchedSuggestion":true'));
    expect(scan.extractedJson, isNot(contains('1990')));
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
  });

  test('the person may correct the reader: the corrected number is what is saved', () async {
    await ocrFor(db, ownerAccess, root, keys).confirmNidScan(
      tenantId: tenantId,
      image: image,
      extension: 'png',
      reviewedNid: '1234567890',
      suggestedNid: '9999999999',
    );
    expect((await vaultFor(db, ownerAccess).get(tenantId))!.nidNo, '1234567890');
    expect((await db.select(db.ocrScans).getSingle()).extractedJson, contains('"matchedSuggestion":false'));
  });

  test('an invalid NID is refused BEFORE anything is stored', () async {
    await expectLater(
      ocrFor(db, ownerAccess, root, keys).confirmNidScan(tenantId: tenantId, image: image, extension: 'jpg', reviewedNid: '12345'),
      throwsArgumentError,
    );
    expect(await db.select(db.documents).get(), isEmpty);
    expect(await db.select(db.ocrScans).get(), isEmpty);
    expect(await db.select(db.tenantVaults).get(), isEmpty);
  });

  test('without vault write permission nothing is saved', () async {
    for (final role in [Role.manager, Role.caretaker, Role.tenant]) {
      await expectLater(
        ocrFor(db, MemberAccess(role: role), root, keys)
            .confirmNidScan(tenantId: tenantId, image: image, extension: 'jpg', reviewedNid: '1234567890'),
        throwsA(isA<PermissionDenied>()),
      );
    }
    expect(await db.select(db.documents).get(), isEmpty);
  });

  test('vault-approved staff can confirm; another organization cannot', () async {
    await ocrFor(db, vaultStaff, root, keys)
        .confirmNidScan(tenantId: tenantId, image: image, extension: 'jpg', reviewedNid: '1234567890');
    await expectLater(
      ocrFor(db, ownerAccess, root, keys, 'other-org')
          .confirmNidScan(tenantId: tenantId, image: image, extension: 'jpg', reviewedNid: '1234567890'),
      throwsStateError,
    );
  });

  test('the photo is encrypted on disk', () async {
    await ocrFor(db, ownerAccess, root, keys)
        .confirmNidScan(tenantId: tenantId, image: image, extension: 'jpg', reviewedNid: '1234567890');
    final doc = await db.select(db.documents).getSingle();
    final onDisk = File('${root.path}/${doc.localPath}').readAsBytesSync();
    expect(onDisk.contains(9) && onDisk.where((b) => b == 9).length > 250, isFalse);
    expect(await documentsFor(db, ownerAccess, root, keyStore: keys).read(doc.id), image);
  });
}
