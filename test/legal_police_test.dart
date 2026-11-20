import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/features/police/domain/police_form_pdf.dart';

import 'helpers.dart';

final Uint8List _scan = Uint8List.fromList(List.filled(200, 3));

void main() {
  late AppDatabase db;
  late Directory root;
  late MemoryKeyValueStore keys;
  late ({String propertyId, String unitId, String tenantId}) ids;
  const owner = ownerAccess;

  setUp(() async {
    db = memoryDb();
    root = Directory.systemTemp.createTempSync('rent_solution_legal_');
    keys = MemoryKeyValueStore();
    ids = await seedTenant(db);
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<String> addNotice({String? tenant}) => legalFor(db, owner, root, keyStore: keys).add(
        tenantId: tenant ?? ids.tenantId,
        kind: LegalRecordKind.legalNotice,
        issuedOn: DateTime.utc(2026, 11, 1),
        bytes: _scan,
        extension: 'jpg',
        referenceNo: ' GD-123 ',
      );

  group('legal records', () {
    test('owner stores a notice and an NOC (encrypted); they are listed; audit has no file data', () async {
      await addNotice();
      await legalFor(db, owner, root, keyStore: keys).add(
        tenantId: ids.tenantId,
        kind: LegalRecordKind.noc,
        issuedOn: DateTime.utc(2026, 11, 2),
        bytes: _scan,
        extension: 'pdf',
      );
      final list = await legalFor(db, owner, root, keyStore: keys).list(ids.tenantId);
      expect(list.map((r) => r.kind), [LegalRecordKind.noc, LegalRecordKind.legalNotice]);
      expect(list.last.referenceNo, 'GD-123');
      expect((await db.select(db.documents).get()).map((d) => d.type).toSet(), {DocumentType.legalNotice, DocumentType.noc});
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });

    test('only owner/admin; manager with vault access cannot', () async {
      for (final a in [vaultStaff, const MemberAccess(role: Role.manager), const MemberAccess(role: Role.caretaker), const MemberAccess(role: Role.tenant)]) {
        await expectLater(
          legalFor(db, a, root, keyStore: keys).add(tenantId: ids.tenantId, kind: LegalRecordKind.noc, issuedOn: DateTime.utc(2026), bytes: _scan, extension: 'jpg'),
          throwsA(isA<PermissionDenied>()),
        );
        await expectLater(legalFor(db, a, root, keyStore: keys).list(ids.tenantId), throwsA(isA<PermissionDenied>()));
      }
    });

    test('a moved-out tenant can still get a legal record; another organization cannot', () async {
      await tenantsFor(db, owner).softDelete(ids.tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId));
      await addNotice();
      await expectLater(
        legalFor(db, owner, root, keyStore: keys, orgId: 'other-org')
            .add(tenantId: ids.tenantId, kind: LegalRecordKind.noc, issuedOn: DateTime.utc(2026), bytes: _scan, extension: 'jpg'),
        throwsStateError,
      );
    });
  });

  group('legal erasure', () {
    Future<String> prepareErasable() async {
      await vaultFor(db, owner).save(ids.tenantId, nidNo: '1234567890', permanentAddress: 'Secret Village');
      await householdFor(db, owner).addMember(tenantId: ids.tenantId, type: HouseholdType.driver, name: 'Secret Driver', idNo: 'AB123456');
      await documentsFor(db, owner, root, keyStore: keys).store(tenantId: ids.tenantId, type: DocumentType.nid, bytes: _scan, extension: 'jpg');
      await documentsFor(db, owner, root, keyStore: keys).store(tenantId: ids.tenantId, type: DocumentType.photo, bytes: _scan, extension: 'jpg');
      await paymentsFor(db, owner).record(tenantId: ids.tenantId, amount: 700, method: PaymentMethod.cash);
      await policeFor(db, owner).recordShare(tenantId: ids.tenantId, channel: 'share', consentConfirmed: true);
      final noticeId = await addNotice();
      await tenantsFor(db, owner).softDelete(ids.tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId));
      return noticeId;
    }

    test('personal data is gone; legal records, police log and payments stay', () async {
      final noticeId = await prepareErasable();
      await erasureFor(db, owner, root).eraseTenant(
        ids.tenantId,
        legalRecordId: noticeId,
        confirmation: await confirmed(SensitiveAction.legalErasure, ids.tenantId),
      );
      final tenant = await (db.select(db.tenants)..where((t) => t.id.equals(ids.tenantId))).getSingle();
      expect(tenant.name, '[erased]');
      expect(tenant.phone, '');
      expect(await db.select(db.tenantVaults).get(), isEmpty);
      expect(await db.select(db.householdMembers).get(), isEmpty);
      expect(await db.select(db.householdVaults).get(), isEmpty);
      expect(await db.select(db.deletedArchives).get(), isEmpty);
      final docs = await db.select(db.documents).get();
      expect(docs.map((d) => d.type), [DocumentType.legalNotice]);
      expect(Directory('${root.path}/vault').listSync(), hasLength(1));
      expect(await db.select(db.legalRecords).get(), hasLength(1));
      expect(await db.select(db.policeShares).get(), hasLength(1));
      expect(await db.select(db.payments).get(), hasLength(1));
      final request = await db.select(db.erasureRequests).getSingle();
      expect(request.legalRecordId, noticeId);
      expect(request.erasedAt, isNotNull);
      final legalDoc = docs.single;
      expect(await documentsFor(db, owner, root, keyStore: keys).read(legalDoc.id), _scan);
      expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    });

    test('no personal text is left anywhere in the database', () async {
      final noticeId = await prepareErasable();
      await erasureFor(db, owner, root).eraseTenant(ids.tenantId, legalRecordId: noticeId, confirmation: await confirmed(SensitiveAction.legalErasure, ids.tenantId));
      for (final table in ['tenants', 'tenant_vaults', 'household_members', 'household_vaults', 'deleted_archives', 'documents', 'audit_logs', 'ocr_scans']) {
        final rows = await db.customSelect('SELECT * FROM $table').get();
        final text = rows.map((r) => r.data.values.join('|')).join('\n');
        for (final secret in ['Karim', 'Secret', '1234567890', 'AB123456', '01711111111']) {
          expect(text, isNot(contains(secret)), reason: '$secret left in $table');
        }
      }
    });

    test('refused: active tenant, no legal notice, wrong confirmation, other roles, other organization', () async {
      final noticeId = await addNotice();
      final token = () => confirmed(SensitiveAction.legalErasure, ids.tenantId);
      await expectLater(
        erasureFor(db, owner, root).eraseTenant(ids.tenantId, legalRecordId: noticeId, confirmation: await token()),
        throwsStateError,
      );
      await tenantsFor(db, owner).softDelete(ids.tenantId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId));
      await expectLater(
        erasureFor(db, owner, root).eraseTenant(ids.tenantId, legalRecordId: 'no-such-record', confirmation: await token()),
        throwsStateError,
      );
      await expectLater(
        erasureFor(db, owner, root).eraseTenant(ids.tenantId, legalRecordId: noticeId, confirmation: await confirmed(SensitiveAction.tenantDelete, ids.tenantId)),
        throwsA(isA<ConfirmationException>()),
      );
      await expectLater(
        erasureFor(db, vaultStaff, root).eraseTenant(ids.tenantId, legalRecordId: noticeId, confirmation: await token()),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        erasureFor(db, owner, root, orgId: 'other-org').eraseTenant(ids.tenantId, legalRecordId: noticeId, confirmation: await token()),
        throwsStateError,
      );
      expect((await db.select(db.tenants).getSingle()).name, 'Karim');
    });

    test('an erased tenant cannot be restored from the archive', () async {
      final noticeId = await prepareErasable();
      await erasureFor(db, owner, root).eraseTenant(ids.tenantId, legalRecordId: noticeId, confirmation: await confirmed(SensitiveAction.legalErasure, ids.tenantId));
      expect(await archiveFor(db, owner, root).list(), isEmpty);
    });
  });

  group('police form', () {
    test('only owner/admin; the form has tenant, vault data and household with private numbers', () async {
      await vaultFor(db, owner).save(ids.tenantId, nidNo: '1234567890', permanentAddress: 'Village');
      await householdFor(db, owner).addMember(tenantId: ids.tenantId, type: HouseholdType.driver, name: 'Salam', phone: '01711111111', idNo: 'AB123456');
      final data = await policeFor(db, owner).prepare(ids.tenantId);
      expect(data.tenantName, 'Karim');
      expect(data.nidNo, '1234567890');
      expect(data.unitLabel, 'Rahim Villa A1');
      expect(data.members.single.phone, '8801711111111');
      expect(data.members.single.idNo, 'AB123456');
      for (final a in [vaultStaff, const MemberAccess(role: Role.manager), const MemberAccess(role: Role.caretaker), MemberAccess(role: Role.tenant, linkedTenantId: ids.tenantId)]) {
        await expectLater(policeFor(db, a).prepare(ids.tenantId), throwsA(isA<PermissionDenied>()));
      }
      await expectLater(policeFor(db, owner, orgId: 'other-org').prepare(ids.tenantId), throwsStateError);
    });

    test('sharing needs confirmed consent; the log holds no personal data', () async {
      await expectLater(
        policeFor(db, owner).recordShare(tenantId: ids.tenantId, channel: 'share', consentConfirmed: false),
        throwsArgumentError,
      );
      expect(await db.select(db.policeShares).get(), isEmpty);
      await policeFor(db, owner).recordShare(tenantId: ids.tenantId, channel: 'share', consentConfirmed: true);
      final log = await policeFor(db, owner).log(ids.tenantId);
      expect(log.single.consentConfirmed, isTrue);
      final audit = (await db.select(db.auditLogs).get()).firstWhere((a) => a.action == 'police.share');
      expect('${audit.newValue}', allOf(contains('consent'), isNot(contains('Karim'))));
      await expectLater(
        policeFor(db, const MemberAccess(role: Role.manager)).recordShare(tenantId: ids.tenantId, channel: 'share', consentConfirmed: true),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('the PDF builds, with and without household members', () async {
      final data = await policeFor(db, owner).prepare(ids.tenantId);
      final bytes = await buildPoliceFormPdf(
        data,
        PoliceFormLabels.english,
        formatDate: (d) => '${d.year}-${d.month}-${d.day}',
        typeLabel: (t) => t,
        preparedOn: DateTime.utc(2026, 11, 10),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      await householdFor(db, owner).addMember(tenantId: ids.tenantId, type: HouseholdType.family, name: 'Rina', relation: 'Wife', age: 30);
      final withMembers = await buildPoliceFormPdf(
        await policeFor(db, owner).prepare(ids.tenantId),
        PoliceFormLabels.english,
        formatDate: (d) => '${d.year}',
        typeLabel: (t) => t,
        preparedOn: DateTime.utc(2026, 11, 10),
      );
      expect(withMembers.length, greaterThan(bytes.length - 500));
    });
  });
}
