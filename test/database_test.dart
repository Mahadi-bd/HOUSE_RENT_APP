import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';

final _now = DateTime.utc(2026, 11, 9);

Future<void> _property(AppDatabase db, String id) => db.into(db.properties).insert(
      PropertiesCompanion.insert(
        id: id,
        orgId: 'org',
        createdAt: _now,
        updatedAt: _now,
        createdBy: 'u',
        deviceId: 'd',
        hlc: '1',
        name: 'House $id',
        address: 'Khulna',
      ),
    );

Future<void> _unit(AppDatabase db, String id, String propertyId, String unitNo) =>
    db.into(db.units).insert(
          UnitsCompanion.insert(
            id: id,
            orgId: 'org',
            createdAt: _now,
            updatedAt: _now,
            createdBy: 'u',
            deviceId: 'd',
            hlc: '1',
            propertyId: propertyId,
            unitNo: unitNo,
            rentAmount: 1000000,
          ),
        );

Future<void> _tenant(AppDatabase db, String id, String unitId) => db.into(db.tenants).insert(
      TenantsCompanion.insert(
        id: id,
        orgId: 'org',
        createdAt: _now,
        updatedAt: _now,
        createdBy: 'u',
        deviceId: 'd',
        hlc: '1',
        name: 'Test Tenant',
        phone: '01700000000',
        unitId: unitId,
        leaseStart: _now,
        monthlyRent: 1000000,
      ),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('foreign keys and uniqueness', () {
    test('a tenant cannot point at a unit that does not exist', () async {
      await expectLater(_tenant(db, 't1', 'missing-unit'), throwsA(anything));
    });

    test('a unit cannot point at a property that does not exist', () async {
      await expectLater(_unit(db, 'u1', 'missing-property', 'A1'), throwsA(anything));
    });

    test('tenant with real property and unit is accepted', () async {
      await _property(db, 'p1');
      await _unit(db, 'u1', 'p1', 'A1');
      await _tenant(db, 't1', 'u1');
      expect(await db.select(db.tenants).get(), hasLength(1));
    });

    test('unit number is unique per property, but reusable after soft delete', () async {
      await _property(db, 'p1');
      await _unit(db, 'u1', 'p1', 'A1');
      await expectLater(_unit(db, 'u2', 'p1', 'A1'), throwsA(anything));
      await (db.update(db.units)..where((u) => u.id.equals('u1')))
          .write(UnitsCompanion(deletedAt: Value(_now)));
      await _unit(db, 'u2', 'p1', 'A1');
      expect(await db.select(db.units).get(), hasLength(2));
    });

    test('bill is unique per tenant, month and version', () async {
      await _property(db, 'p1');
      await _unit(db, 'u1', 'p1', 'A1');
      await _tenant(db, 't1', 'u1');
      Future<void> bill(String id, int version) => db.into(db.bills).insert(
            BillsCompanion.insert(
              id: id,
              orgId: 'org',
              createdAt: _now,
              updatedAt: _now,
              createdBy: 'u',
              deviceId: 'd',
              hlc: '1',
              tenantId: 't1',
              unitId: 'u1',
              month: '2026-11',
              baseRent: 1000000,
              total: 1000000,
              generatedAt: _now,
              version: Value(version),
            ),
          );
      await bill('b1', 1);
      await expectLater(bill('b2', 1), throwsA(anything));
      await bill('b3', 2);
    });

    test('payment receipt numbers are unique per organization', () async {
      await _property(db, 'p1');
      await _unit(db, 'u1', 'p1', 'A1');
      await _tenant(db, 't1', 'u1');
      Future<void> pay(String id, String receipt) => db.into(db.payments).insert(
            PaymentsCompanion.insert(
              id: id,
              orgId: 'org',
              createdAt: _now,
              updatedAt: _now,
              createdBy: 'u',
              deviceId: 'd',
              hlc: '1',
              tenantId: 't1',
              unitId: 'u1',
              amount: 500000,
              method: PaymentMethod.cash,
              type: PaymentType.rent,
              forMonth: '2026-11',
              paidAt: _now,
              receiptNo: receipt,
              recordedBy: 'u',
              status: PaymentStatus.paid,
            ),
          );
      await pay('p-1', 'R-0001');
      await expectLater(pay('p-2', 'R-0001'), throwsA(anything));
    });
  });

  group('soft delete', () {
    test('soft-deleted tenants disappear from the active list', () async {
      await _property(db, 'p1');
      await _unit(db, 'u1', 'p1', 'A1');
      await _tenant(db, 't1', 'u1');
      expect(await db.tenantsDao.watchActive('org').first, hasLength(1));
      await db.tenantsDao.softDelete('org', 't1', _now, 'hlc-1');
      expect(await db.tenantsDao.watchActive('org').first, isEmpty);
    });

    test('active list never mixes organizations', () async {
      await _property(db, 'p1');
      await _unit(db, 'u1', 'p1', 'A1');
      await _tenant(db, 't1', 'u1');
      expect(await db.tenantsDao.watchActive('other-org').first, isEmpty);
    });
  });

  group('sync operations', () {
    test('a full operation record can be stored and starts as pending', () async {
      await db.into(db.syncOps).insert(
            SyncOpsCompanion.insert(
              id: 'op1',
              orgId: 'org',
              entityType: 'payment',
              entityId: 'pay1',
              deviceId: 'dev',
              senderUid: 'uid',
              hlc: '000001700000000-0000-dev',
              channel: SyncChannel.basic,
              direction: SyncDirection.outbox,
              keyVersion: 1,
              nonce: 'bm9uY2U=',
              ciphertext: 'Y2lwaGVy',
              createdAt: _now,
              expireAt: _now.add(const Duration(days: 30)),
            ),
          );
      final op = await db.select(db.syncOps).getSingle();
      expect(op.state, SyncOpState.pending);
      expect(op.acknowledgedAt, isNull);
    });
  });
}
