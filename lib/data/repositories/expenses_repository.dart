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
import 'package:rent_solution/data/repositories/payments_repository.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// The expense ledger (repairs, taxes, commission, salary, other).
class ExpensesRepository {
  /// Creates the repository.
  ExpensesRepository(this._db, this._guard, this._ctx, this._confirmations);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final ConfirmationService _confirmations;

  /// Records an expense of [amount] poisha for [propertyId] and returns its id.
  Future<String> record({
    required String propertyId,
    required ExpenseCategory category,
    required int amount,
    required DateTime spentOn,
    String? note,
  }) async {
    _guard.requireInProperty(Permission.expenseCreate, propertyId);
    if (amount <= 0 || amount > PaymentsRepository.maxAmount) {
      throw ArgumentError.value(amount, 'amount', 'must be above zero (poisha)');
    }
    final id = newId();
    final now = _ctx.now;
    await _ctx.transaction(_db, () async {
      final property = await (_db.select(_db.properties)
            ..where(
              (p) => p.id.equals(propertyId) & p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (property == null) {
        throw StateError('Property not found.');
      }
      await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              propertyId: propertyId,
              category: category,
              amount: amount,
              spentOn: spentOn,
              recordedBy: _ctx.userId,
              note: Value(note),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'expense.record',
        entityType: 'expense',
        entityId: id,
        newValue: jsonEncode({
          'propertyId': propertyId,
          'category': category.name,
          'amount': amount,
        }),
        at: now,
      );
    });
    return id;
  }

  /// Expenses of [propertyId] (optionally only [month], `yyyy-MM`, Bangladesh time), newest first.
  Future<List<Expense>> list(String propertyId, {String? month}) async {
    _guard.requireInProperty(Permission.reportsView, propertyId);
    final query = _db.select(_db.expenses)
      ..where((e) {
        Expression<bool> cond =
            e.orgId.equals(_ctx.orgId) & e.propertyId.equals(propertyId) & e.deletedAt.isNull();
        if (month != null) {
          final start = _monthStartUtc(month);
          final end = _monthStartUtc(nextMonthKey(month));
          cond = cond & e.spentOn.isBiggerOrEqualValue(start) & e.spentOn.isSmallerThanValue(end);
        }
        return cond;
      })
      ..orderBy([(e) => OrderingTerm.desc(e.spentOn), (e) => OrderingTerm.desc(e.createdAt)]);
    return query.get();
  }

  /// Total spent on [propertyId] in [month], in poisha.
  Future<int> monthTotal(String propertyId, String month) async {
    final rows = await list(propertyId, month: month);
    return rows.fold<int>(0, (sum, e) => sum + e.amount);
  }

  /// Removes an expense (kept, marked deleted). Owner/Admin only, after email confirmation.
  Future<void> voidExpense(
    String expenseId, {
    required String reason,
    required ConfirmationToken confirmation,
  }) async {
    _guard.require(Permission.deleteAny);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A reason is required.');
    }
    _confirmations.consume(
      confirmation,
      action: SensitiveAction.expenseVoid,
      entityId: expenseId,
    );
    await _ctx.transaction(_db, () async {
      final old = await (_db.select(_db.expenses)
            ..where(
              (e) => e.id.equals(expenseId) & e.orgId.equals(_ctx.orgId) & e.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (old == null) {
        throw StateError('Expense not found.');
      }
      final now = _ctx.now;
      await ArchiveWriter.archive(
        _db,
        _ctx,
        entityType: 'expense',
        entityId: expenseId,
        snapshot: old.toJson(),
      );
      await (_db.update(_db.expenses)
            ..where((e) => e.id.equals(expenseId) & e.orgId.equals(_ctx.orgId)))
          .write(
        ExpensesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'expense.void',
        entityType: 'expense',
        entityId: expenseId,
        oldValue: jsonEncode({'category': old.category.name, 'amount': old.amount}),
        newValue: jsonEncode({'reason': reason.trim()}),
        at: now,
      );
    });
  }

  /// First instant of [month] in Bangladesh time, as UTC.
  DateTime _monthStartUtc(String month) {
    final year = int.parse(month.substring(0, 4));
    final m = int.parse(month.substring(5, 7));
    return DateTime.utc(year, m).subtract(bangladeshOffset);
  }
}
