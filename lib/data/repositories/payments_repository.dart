import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/archive_writer.dart';
import 'package:rent_solution/data/repositories/write_context.dart';
import 'package:rent_solution/domain/money/ledger.dart';
import 'package:rent_solution/domain/money/payment_classifier.dart';
import 'package:rent_solution/domain/money/receipt_number.dart';
import 'package:rent_solution/domain/money/rent_charges.dart';

/// What the person gets after a payment is recorded (used for the receipt).
class PaymentReceipt {
  /// Creates a receipt.
  const PaymentReceipt({
    required this.paymentId,
    required this.receiptNo,
    required this.amount,
    required this.method,
    required this.paidAt,
    required this.outstandingAfter,
    required this.advanceCredit,
  });

  /// Payment row id.
  final String paymentId;

  /// Printed receipt number.
  final String receiptNo;

  /// Amount paid, in poisha.
  final int amount;

  /// How it was paid.
  final PaymentMethod method;

  /// When it was recorded (UTC).
  final DateTime paidAt;

  /// Rent still owed after this payment, in poisha.
  final int outstandingAfter;

  /// Money paid in advance after this payment, in poisha.
  final int advanceCredit;
}

/// Payments with permission checks, duplicate protection and audit records.
///
/// CORRECTION MODEL: balances are always calculated from rent, optional extra charges and the
/// payment amounts. The stored type, status and month of a payment are labels that describe the
/// payment "as it was when made". After an edit or a cancellation the labels of every payment
/// of that tenant are recalculated in order by the same rules, so a label never contradicts the
/// numbers. A receipt keeps its number; a corrected payment prints as "Amended" and the old
/// values stay in the audit log.
class PaymentsRepository {
  /// Creates the repository.
  PaymentsRepository(this._db, this._guard, this._ctx, this._confirmations);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final ConfirmationService _confirmations;

  /// Payment types that count against what the tenant owes (rent plus optional extra charges).
  /// A deposit is held money, so it does not.
  static const ledgerTypes = {
    PaymentType.rent,
    PaymentType.partial,
    PaymentType.advance,
    PaymentType.utility,
    PaymentType.lateFee,
  };

  /// Largest single payment accepted, in poisha (1,000,000,000 BDT). A typing-error guard.
  static const maxAmount = 100000000000;

  static const _needsTrxId = {PaymentMethod.bkash, PaymentMethod.nagad, PaymentMethod.rocket};

  Future<Tenant> _tenant(String tenantId) async {
    final tenant = await (_db.select(_db.tenants)
          ..where(
            (t) => t.id.equals(tenantId) & t.orgId.equals(_ctx.orgId) & t.deletedAt.isNull(),
          ))
        .getSingleOrNull();
    if (tenant == null) {
      throw StateError('Tenant not found.');
    }
    return tenant;
  }

  Future<Unit> _unit(String unitId) async {
    final unit = await (_db.select(_db.units)
          ..where((u) => u.id.equals(unitId) & u.orgId.equals(_ctx.orgId)))
        .getSingleOrNull();
    if (unit == null) {
      throw StateError('Unit not found.');
    }
    return unit;
  }

  Future<List<ExtraCharge>> _extras(String tenantId) {
    return (_db.select(_db.extraCharges)
          ..where(
            (c) => c.tenantId.equals(tenantId) & c.orgId.equals(_ctx.orgId) & c.deletedAt.isNull(),
          ))
        .get();
  }

  Future<List<Payment>> _payments(String tenantId) {
    return (_db.select(_db.payments)
          ..where(
            (p) => p.tenantId.equals(tenantId) & p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull(),
          )
          ..orderBy([
            (p) => OrderingTerm.asc(p.paidAt),
            (p) => OrderingTerm.asc(p.createdAt),
            (p) => OrderingTerm.asc(p.receiptNo),
          ]))
        .get();
  }

  List<MonthCharge> _chargesAt(Tenant tenant, List<ExtraCharge> extras, DateTime at) {
    return mergeExtraCharges(
      rentCharges(
        leaseStart: tenant.leaseStart,
        leaseEnd: tenant.leaseEnd,
        monthlyDue: tenant.monthlyRent + tenant.serviceCharge,
        now: at,
      ),
      [for (final c in extras) (month: c.month, amount: c.amount)],
    );
  }

  Future<LedgerSummary> _ledger(Tenant tenant) async {
    final payments = await _payments(tenant.id);
    final extras = await _extras(tenant.id);
    return buildLedger(
      charges: _chargesAt(tenant, extras, _ctx.now),
      payments: [
        for (final p in payments)
          if (ledgerTypes.contains(p.type)) p.amount,
      ],
    );
  }

  /// The rent ledger of [tenantId]. Tenants may read only their own.
  Future<LedgerSummary> ledgerFor(String tenantId) async {
    final tenant = await _tenant(tenantId);
    final unit = await _unit(tenant.unitId);
    _guard.requireOwnOrInProperty(
      tenantId: tenantId,
      propertyId: unit.propertyId,
      permission: Permission.paymentCreate,
    );
    return _ledger(tenant);
  }

  /// Payments of [tenantId], newest first. Tenants may read only their own.
  Future<List<Payment>> listForTenant(String tenantId) async {
    final tenant = await _tenant(tenantId);
    final unit = await _unit(tenant.unitId);
    _guard.requireOwnOrInProperty(
      tenantId: tenantId,
      propertyId: unit.propertyId,
      permission: Permission.paymentCreate,
    );
    return (await _payments(tenantId)).reversed.toList();
  }

  /// One payment (for receipts). Tenants may read only their own.
  Future<Payment> getPayment(String paymentId) async {
    final payment = await (_db.select(_db.payments)
          ..where(
            (p) => p.id.equals(paymentId) & p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull(),
          ))
        .getSingleOrNull();
    if (payment == null) {
      throw StateError('Payment not found.');
    }
    final unit = await _unit(payment.unitId);
    _guard.requireOwnOrInProperty(
      tenantId: payment.tenantId,
      propertyId: unit.propertyId,
      permission: Permission.paymentCreate,
    );
    return payment;
  }

  /// What was still owed (or paid in advance) right after [paymentId], by the numbers known at
  /// that time. Used on receipts so a re-printed receipt shows the same balance.
  Future<({int outstanding, int advance})> balanceAfter(String paymentId) async {
    final payment = await getPayment(paymentId);
    final tenant = await _tenant(payment.tenantId);
    final extras = [
      for (final c in await _extras(tenant.id))
        if (!c.createdAt.isAfter(payment.paidAt)) c,
    ];
    final upToHere = <int>[];
    for (final p in await _payments(tenant.id)) {
      if (!ledgerTypes.contains(p.type)) {
        continue;
      }
      upToHere.add(p.amount);
      if (p.id == paymentId) {
        break;
      }
    }
    final ledger = buildLedger(
      charges: _chargesAt(tenant, extras, payment.paidAt),
      payments: upToHere,
    );
    return (outstanding: ledger.outstanding, advance: ledger.advanceCredit);
  }

  /// Whether the payment was corrected after it was recorded (receipts then say "Amended").
  Future<bool> wasAmended(String paymentId) async {
    final rows = await (_db.select(_db.auditLogs)
          ..where(
            (a) =>
                a.orgId.equals(_ctx.orgId) &
                a.entityId.equals(paymentId) &
                a.action.equals('payment.edit'),
          )
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// The newest payments across all tenants, for the Payments tab. Respects property scope.
  Future<List<Payment>> recent({int limit = 50}) async {
    _guard.require(Permission.paymentCreate);
    final access = _guard.access!;
    Set<String>? allowedUnits;
    if (!access.role.isAdminLevel && access.propertyScope.isNotEmpty) {
      final units = await (_db.select(_db.units)
            ..where(
              (u) => u.orgId.equals(_ctx.orgId) & u.propertyId.isIn(access.propertyScope),
            ))
          .get();
      allowedUnits = {for (final u in units) u.id};
    }
    final query = _db.select(_db.payments)
      ..where((p) {
        Expression<bool> e = p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull();
        if (allowedUnits != null) {
          e = e & p.unitId.isIn(allowedUnits);
        }
        return e;
      })
      ..orderBy([(p) => OrderingTerm.desc(p.paidAt), (p) => OrderingTerm.desc(p.receiptNo)])
      ..limit(limit);
    return query.get();
  }

  /// Transaction IDs from [ids] that are already recorded for [method] in this organization.
  /// A restore or import calls this first and must resolve every conflict before inserting.
  Future<Set<String>> existingTrxIds(PaymentMethod method, Iterable<String> ids) async {
    final wanted = {for (final id in ids) _normalizeTrx(id)};
    final rows = await (_db.select(_db.payments)
          ..where(
            (p) =>
                p.orgId.equals(_ctx.orgId) &
                p.method.equalsValue(method) &
                p.deletedAt.isNull() &
                p.trxId.isIn(wanted),
          ))
        .get();
    return {for (final p in rows) p.trxId!};
  }

  String _normalizeTrx(String id) => id.trim().toUpperCase();

  Future<void> _requireFreshTrx(PaymentMethod method, String trx, {String? exceptPaymentId}) async {
    final rows = await (_db.select(_db.payments)
          ..where(
            (p) =>
                p.orgId.equals(_ctx.orgId) &
                p.method.equalsValue(method) &
                p.trxId.equals(trx) &
                p.deletedAt.isNull(),
          ))
        .get();
    if (rows.any((p) => p.id != exceptPaymentId)) {
      throw StateError('This transaction ID was already recorded.');
    }
  }

  /// Records a payment of [amount] poisha and returns the receipt data.
  Future<PaymentReceipt> record({
    required String tenantId,
    required int amount,
    required PaymentMethod method,
    PaymentType type = PaymentType.rent,
    String? trxId,
    String? note,
  }) async {
    _guard.require(Permission.paymentCreate);
    _validateAmount(amount);
    final cleanTrx = trxId == null || trxId.trim().isEmpty ? null : _normalizeTrx(trxId);
    if (_needsTrxId.contains(method) && cleanTrx == null) {
      throw ArgumentError('A transaction ID is required for bKash, Nagad and Rocket.');
    }
    return _ctx.transaction(_db, () async {
      final tenant = await _tenant(tenantId);
      final unit = await _unit(tenant.unitId);
      _guard.requireInProperty(Permission.paymentCreate, unit.propertyId);
      if (cleanTrx != null) {
        await _requireFreshTrx(method, cleanTrx);
      }
      final now = _ctx.now;
      final payments = await _payments(tenantId);
      final extras = await _extras(tenantId);
      final counts = ledgerTypes.contains(type);
      final classification = classifyPayment(
        charges: _chargesAt(tenant, extras, now),
        priorPayments: [
          for (final p in payments)
            if (ledgerTypes.contains(p.type)) p.amount,
        ],
        amount: amount,
        type: type,
        countsAgainstDues: counts,
        currentMonth: monthKeyOf(now),
      );
      final prefix = receiptPrefix(now, _ctx.deviceId);
      final sameMonth = await (_db.select(_db.payments)
            ..where((p) => p.orgId.equals(_ctx.orgId) & p.receiptNo.like('$prefix%')))
          .get();
      final receiptNo = formatReceiptNo(prefix, sameMonth.length + 1);
      final id = newId();
      await _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              tenantId: tenantId,
              unitId: tenant.unitId,
              amount: amount,
              method: method,
              type: classification.type,
              forMonth: classification.forMonth,
              paidAt: now,
              receiptNo: receiptNo,
              recordedBy: _ctx.userId,
              status: classification.status,
              trxId: Value(cleanTrx),
              note: Value(note),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'payment.record',
        entityType: 'payment',
        entityId: id,
        newValue: jsonEncode({
          'receiptNo': receiptNo,
          'tenantId': tenantId,
          'amount': amount,
          'method': method.name,
          'type': classification.type.name,
        }),
        at: now,
      );
      final after = await _ledger(tenant);
      return PaymentReceipt(
        paymentId: id,
        receiptNo: receiptNo,
        amount: amount,
        method: method,
        paidAt: now,
        outstandingAfter: after.outstanding,
        advanceCredit: after.advanceCredit,
      );
    });
  }

  /// Corrects a payment. Owner/Admin only. Needs a [confirmation] from the email-link flow for
  /// exactly this payment. Labels of the tenant's payments are recalculated; old and new values
  /// go to the audit log.
  Future<void> editPayment(
    String paymentId, {
    required ConfirmationToken confirmation,
    int? amount,
    PaymentMethod? method,
    String? trxId,
    String? note,
  }) async {
    _guard.require(Permission.paymentEdit);
    if (amount != null) {
      _validateAmount(amount);
    }
    _confirmations.consume(
      confirmation,
      action: SensitiveAction.paymentEdit,
      entityId: paymentId,
    );
    await _ctx.transaction(_db, () async {
      final old = await _livePayment(paymentId);
      final now = _ctx.now;
      final newMethod = method ?? old.method;
      final newTrx = trxId == null ? old.trxId : (trxId.trim().isEmpty ? null : _normalizeTrx(trxId));
      if (_needsTrxId.contains(newMethod) && newTrx == null) {
        throw ArgumentError('A transaction ID is required for bKash, Nagad and Rocket.');
      }
      if (newTrx != null) {
        await _requireFreshTrx(newMethod, newTrx, exceptPaymentId: paymentId);
      }
      await (_db.update(_db.payments)
            ..where((p) => p.id.equals(paymentId) & p.orgId.equals(_ctx.orgId)))
          .write(
        PaymentsCompanion(
          amount: Value(amount ?? old.amount),
          method: Value(newMethod),
          trxId: Value(newTrx),
          note: Value(note ?? old.note),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      final relabeled = await _relabel(await _tenant(old.tenantId));
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'payment.edit',
        entityType: 'payment',
        entityId: paymentId,
        oldValue: jsonEncode({
          'amount': old.amount,
          'method': old.method.name,
          'trxId': old.trxId,
          'type': old.type.name,
          'status': old.status.name,
          'forMonth': old.forMonth,
        }),
        newValue: jsonEncode({
          'amount': amount ?? old.amount,
          'method': newMethod.name,
          'trxId': newTrx,
          'relabeledPayments': relabeled,
        }),
        at: now,
      );
    });
  }

  /// Cancels a payment (never erased; a snapshot goes to the 2-year archive). Owner/Admin only,
  /// with a [confirmation] for exactly this payment.
  Future<void> voidPayment(
    String paymentId, {
    required String reason,
    required ConfirmationToken confirmation,
  }) async {
    _guard.require(Permission.deleteAny);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reason is required.');
    }
    _confirmations.consume(
      confirmation,
      action: SensitiveAction.paymentVoid,
      entityId: paymentId,
    );
    await _ctx.transaction(_db, () async {
      final old = await _livePayment(paymentId);
      final now = _ctx.now;
      await ArchiveWriter.archive(
        _db,
        _ctx,
        entityType: 'payment',
        entityId: paymentId,
        snapshot: old.toJson(),
      );
      await (_db.update(_db.payments)
            ..where((p) => p.id.equals(paymentId) & p.orgId.equals(_ctx.orgId)))
          .write(
        PaymentsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      final relabeled = await _relabel(await _tenant(old.tenantId));
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'payment.void',
        entityType: 'payment',
        entityId: paymentId,
        oldValue: jsonEncode({'amount': old.amount, 'receiptNo': old.receiptNo}),
        newValue: jsonEncode({'reason': reason.trim(), 'relabeledPayments': relabeled}),
        at: now,
      );
    });
  }

  /// Brings a cancelled payment back (Owner/Admin, from the archive screen). Refused when its
  /// transaction ID has been used again in the meantime. Labels are recalculated.
  Future<void> restorePayment(String paymentId) async {
    _guard.require(Permission.archiveRestore);
    await _ctx.transaction(_db, () async {
      final row = await (_db.select(_db.payments)
            ..where((p) => p.id.equals(paymentId) & p.orgId.equals(_ctx.orgId) & p.deletedAt.isNotNull()))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Payment not found.');
      }
      if (row.trxId != null) {
        await _requireFreshTrx(row.method, row.trxId!);
      }
      final tenant = await _tenant(row.tenantId);
      final now = _ctx.now;
      await (_db.update(_db.payments)
            ..where((p) => p.id.equals(paymentId) & p.orgId.equals(_ctx.orgId)))
          .write(
        PaymentsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      final relabeled = await _relabel(tenant);
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'payment.restore',
        entityType: 'payment',
        entityId: paymentId,
        newValue: jsonEncode({'relabeledPayments': relabeled}),
        at: now,
      );
    });
  }

  /// Recalculates type, status and month of every payment of [tenant], in order, with the same
  /// rules used when recording. Returns how many payments changed.
  Future<int> _relabel(Tenant tenant) async {
    final extras = await _extras(tenant.id);
    final prior = <int>[];
    var changed = 0;
    for (final p in await _payments(tenant.id)) {
      if (!ledgerTypes.contains(p.type)) {
        continue;
      }
      final known = [
        for (final c in extras)
          if (!c.createdAt.isAfter(p.paidAt)) c,
      ];
      final requested =
          p.type == PaymentType.utility || p.type == PaymentType.lateFee ? p.type : PaymentType.rent;
      final c = classifyPayment(
        charges: _chargesAt(tenant, known, p.paidAt),
        priorPayments: prior,
        amount: p.amount,
        type: requested,
        countsAgainstDues: true,
        currentMonth: monthKeyOf(p.paidAt),
      );
      prior.add(p.amount);
      if (c.type != p.type || c.status != p.status || c.forMonth != p.forMonth) {
        await (_db.update(_db.payments)
              ..where((x) => x.id.equals(p.id) & x.orgId.equals(_ctx.orgId)))
            .write(
          PaymentsCompanion(
            type: Value(c.type),
            status: Value(c.status),
            forMonth: Value(c.forMonth),
            updatedAt: Value(_ctx.now),
            hlc: Value(_ctx.hlc),
            syncStatus: Value(SyncStatus.pending),
          ),
        );
        changed++;
      }
    }
    return changed;
  }

  Future<Payment> _livePayment(String paymentId) async {
    final payment = await (_db.select(_db.payments)
          ..where(
            (p) => p.id.equals(paymentId) & p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull(),
          ))
        .getSingleOrNull();
    if (payment == null) {
      throw StateError('Payment not found.');
    }
    return payment;
  }

  void _validateAmount(int amount) {
    if (amount <= 0 || amount > maxAmount) {
      throw ArgumentError.value(amount, 'amount', 'must be between 1 and $maxAmount poisha');
    }
  }
}
