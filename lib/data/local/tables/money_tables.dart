// ignore_for_file: public_member_api_docs
import 'package:drift/drift.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/local/tables/property_tables.dart';
import 'package:rent_solution/data/local/tables/synced_columns.dart';

@TableIndex(name: 'idx_payments_tenant_month', columns: {#tenantId, #forMonth})
class Payments extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get unitId => text().references(Units, #id)();
  TextColumn get billId => text().nullable().references(Bills, #id)();
  IntColumn get amount => integer()();
  TextColumn get method => textEnum<PaymentMethod>()();
  TextColumn get trxId => text().nullable()();
  TextColumn get type => textEnum<PaymentType>()();
  // Month the payment is for, like 2026-11.
  TextColumn get forMonth => text()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get receiptNo => text()();
  TextColumn get recordedBy => text()();
  TextColumn get note => text().nullable()();
  TextColumn get status => textEnum<PaymentStatus>()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {orgId, receiptNo},
      ];
}

@TableIndex(name: 'idx_bills_org_month_status', columns: {#orgId, #month, #status})
class Bills extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get unitId => text().references(Units, #id)();
  // Month like 2026-11.
  TextColumn get month => text()();
  IntColumn get baseRent => integer()();
  IntColumn get serviceCharge => integer().withDefault(const Constant(0))();
  IntColumn get utilities => integer().withDefault(const Constant(0))();
  IntColumn get lateFee => integer().withDefault(const Constant(0))();
  IntColumn get carriedForward => integer().withDefault(const Constant(0))();
  IntColumn get advanceCredit => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get status =>
      textEnum<BillStatus>().withDefault(Constant(BillStatus.generated.name))();
  DateTimeColumn get generatedAt => dateTime()();
  DateTimeColumn get whatsappOpenedAt => dateTime().nullable()();
  TextColumn get pdfDocumentId => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {tenantId, month, version},
      ];
}

@TableIndex(name: 'idx_bill_items_bill', columns: {#billId})
class BillItems extends Table with SyncedColumns {
  TextColumn get billId => text().references(Bills, #id)();
  TextColumn get label => text()();
  IntColumn get amount => integer()();
  TextColumn get kind => textEnum<BillItemKind>()();
}

class MeterReadings extends Table with SyncedColumns {
  TextColumn get unitId => text().references(Units, #id)();
  TextColumn get utility => textEnum<UtilityKind>()();
  RealColumn get previous => real()();
  RealColumn get current => real()();
  // Price per unit in poisha.
  IntColumn get rate => integer()();
  TextColumn get month => text()();
  IntColumn get amount => integer()();
}

class LateFeeRules extends Table with SyncedColumns {
  TextColumn get propertyId => text().references(Properties, #id)();
  IntColumn get graceDays => integer().withDefault(const Constant(0))();
  TextColumn get type => textEnum<LateFeeType>()();
  // Poisha for fixed and per day; basis points (100 = 1%) for percent.
  IntColumn get value => integer()();
}

@TableIndex(name: 'idx_expenses_property_date', columns: {#propertyId, #spentOn})
class Expenses extends Table with SyncedColumns {
  TextColumn get propertyId => text().references(Properties, #id)();
  TextColumn get category => textEnum<ExpenseCategory>()();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get spentOn => dateTime()();
  TextColumn get recordedBy => text()();
}

/// Optional extra charges for a tenant and month: electricity, gas, water, fines and so on.
/// They add to what the tenant owes. A month with no extra charges is perfectly normal.
@TableIndex(name: 'idx_extra_charges_tenant_month', columns: {#tenantId, #month})
class ExtraCharges extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get unitId => text().references(Units, #id)();
  // Month like 2026-11.
  TextColumn get month => text()();
  TextColumn get kind => textEnum<ChargeKind>()();
  TextColumn get label => text().nullable()();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
}
