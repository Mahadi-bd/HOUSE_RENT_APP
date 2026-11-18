import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/audit_hash.dart';
import 'package:rent_solution/data/local/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
      await db.auditDao.append(
        orgId: 'org',
        userId: 'user',
        action: 'create',
        entityType: 'payment',
        entityId: 'p$i',
        newValue: '{"amount":${i * 100}}',
        at: DateTime.utc(2026, 11, 9, 10, i),
      );
    }
  }

  test('SHA-256 of known input matches the standard test vector', () {
    expect(
      computeAuditHash(prevHash: '', payload: 'abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('first record links to the genesis hash and later records link to the previous one',
      () async {
    await seed(3);
    final rows = await db.select(db.auditLogs).get();
    expect(rows[0].prevHash, auditGenesisHash);
    expect(rows[1].prevHash, rows[0].currHash);
    expect(rows[2].prevHash, rows[1].currHash);
    expect(rows.map((r) => r.currHash).toSet(), hasLength(3));
  });

  test('a good chain verifies and reports its head', () async {
    await seed(5);
    final result = await db.auditDao.verifyChain('org');
    expect(result.ok, isTrue);
    expect(result.checked, 5);
    final last = (await db.select(db.auditLogs).get()).last;
    expect(result.headHash, last.currHash);
  });

  test('triggers block UPDATE and DELETE', () async {
    await seed(2);
    await expectLater(
      db.customStatement("UPDATE audit_logs SET action = 'x'"),
      throwsA(anything),
    );
    await expectLater(db.customStatement('DELETE FROM audit_logs'), throwsA(anything));
  });

  test('editing a record behind the triggers is detected', () async {
    await seed(4);
    await db.customStatement('DROP TRIGGER audit_logs_no_update');
    await db.customStatement("UPDATE audit_logs SET new_value = '{\"amount\":999999}' WHERE seq = 2");
    final result = await db.auditDao.verifyChain('org');
    expect(result.ok, isFalse);
    expect(result.brokenAtSeq, 2);
  });

  test('removing a record from the middle is detected', () async {
    await seed(4);
    await db.customStatement('DROP TRIGGER audit_logs_no_delete');
    await db.customStatement('DELETE FROM audit_logs WHERE seq = 2');
    final result = await db.auditDao.verifyChain('org');
    expect(result.ok, isFalse);
    expect(result.brokenAtSeq, 3);
  });

  test('records removed from the end are detected with the saved head hash', () async {
    await seed(4);
    final head = (await db.auditDao.verifyChain('org')).headHash;
    await db.customStatement('DROP TRIGGER audit_logs_no_delete');
    await db.customStatement('DELETE FROM audit_logs WHERE seq = 4');
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    final withHead = await db.auditDao.verifyChain('org', expectedHead: head);
    expect(withHead.ok, isFalse);
  });

  test('chains of different organizations are separate', () async {
    await seed(2);
    await db.auditDao.append(
      orgId: 'other',
      userId: 'u',
      action: 'create',
      entityType: 'tenant',
      entityId: 't',
    );
    final other = await (db.select(db.auditLogs)..where((a) => a.orgId.equals('other'))).get();
    expect(other.single.prevHash, auditGenesisHash);
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    expect((await db.auditDao.verifyChain('other')).ok, isTrue);
  });
}
