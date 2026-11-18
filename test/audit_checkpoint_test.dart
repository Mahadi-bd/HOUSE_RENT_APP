import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/audit_checkpoint.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/restore_verification.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late MemoryKeyValueStore memory;
  late AuditCheckpointStore store;
  late WriteContext ctx;

  setUp(() {
    db = AppDatabase(NativeDatabaseForTest.memory());
    memory = MemoryKeyValueStore();
    store = AuditCheckpointStore(memory);
    ctx = WriteContext(orgId: 'org', userId: 'u', deviceId: 'd', checkpoints: store);
  });
  tearDown(() => db.close());

  Future<void> add(int n) async {
    for (var i = 0; i < n; i++) {
      await ctx.transaction(db, () => db.auditDao.append(
            orgId: 'org',
            userId: 'u',
            action: 'create',
            entityType: 'thing',
            entityId: 'e$i',
            newValue: '{"n":$i}',
          ));
    }
  }

  test('the trusted head is saved after each committed change, outside the database', () async {
    await add(3);
    final cp = (await store.load('org'))!;
    final last = (await db.select(db.auditLogs).get()).last;
    expect(cp.seq, last.seq);
    expect(cp.head, last.currHash);
  });

  test('a rolled-back change never moves the checkpoint', () async {
    await add(1);
    final before = (await store.load('org'))!;
    await expectLater(
      ctx.transaction(db, () async {
        await db.auditDao.append(orgId: 'org', userId: 'u', action: 'x', entityType: 't', entityId: 'e');
        throw StateError('boom');
      }),
      throwsStateError,
    );
    final after = (await store.load('org'))!;
    expect(after.seq, before.seq);
    expect((await db.select(db.auditLogs).get()), hasLength(1));
  });

  test('a lower checkpoint never replaces a higher one', () async {
    await store.save('org', const AuditCheckpoint(5, 'aaa'));
    await store.save('org', const AuditCheckpoint(3, 'bbb'));
    expect((await store.load('org'))!.head, 'aaa');
  });

  test('a good database passes restore verification', () async {
    await add(4);
    expect((await verifyRestoredDatabase(db, store, 'org')).ok, isTrue);
  });

  test('a database that is ahead of the checkpoint still passes', () async {
    await add(2);
    await db.auditDao.append(orgId: 'org', userId: 'u', action: 'late', entityType: 't', entityId: 'e');
    expect((await verifyRestoredDatabase(db, store, 'org')).ok, isTrue);
  });

  test('restore detects a modified record', () async {
    await add(4);
    await db.customStatement('DROP TRIGGER audit_logs_no_update');
    await db.customStatement("UPDATE audit_logs SET new_value = 'tampered' WHERE seq = 2");
    final r = await verifyRestoredDatabase(db, store, 'org');
    expect(r.ok, isFalse);
    expect(r.brokenAtSeq, 2);
  });

  test('restore detects a removed middle record', () async {
    await add(4);
    await db.customStatement('DROP TRIGGER audit_logs_no_delete');
    await db.customStatement('DELETE FROM audit_logs WHERE seq = 2');
    expect((await verifyRestoredDatabase(db, store, 'org')).ok, isFalse);
  });

  test('restore detects truncated tail records using the outside checkpoint', () async {
    await add(4);
    await db.customStatement('DROP TRIGGER audit_logs_no_delete');
    await db.customStatement('DELETE FROM audit_logs WHERE seq > 2');
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
    final r = await verifyRestoredDatabase(db, store, 'org');
    expect(r.ok, isFalse);
    expect(r.reason, contains('checkpoint'));
  });

  test('restore detects reordered records', () async {
    await add(4);
    await db.customStatement('DROP TRIGGER audit_logs_no_update');
    await db.customStatement('UPDATE audit_logs SET seq = -1 WHERE seq = 2');
    await db.customStatement('UPDATE audit_logs SET seq = 2 WHERE seq = 3');
    await db.customStatement('UPDATE audit_logs SET seq = 3 WHERE seq = -1');
    expect((await verifyRestoredDatabase(db, store, 'org')).ok, isFalse);
  });

  test('a replaced (older or different) database file fails against the checkpoint', () async {
    await add(4);
    final other = AppDatabase(NativeDatabaseForTest.memory());
    addTearDown(other.close);
    await other.auditDao.append(orgId: 'org', userId: 'u', action: 'a', entityType: 't', entityId: 'e');
    expect((await verifyRestoredDatabase(other, store, 'org')).ok, isFalse);
  });
}
