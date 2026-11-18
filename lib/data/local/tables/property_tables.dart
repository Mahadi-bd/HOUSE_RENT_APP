// ignore_for_file: public_member_api_docs
import 'package:drift/drift.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/local/tables/synced_columns.dart';

@DataClassName('Property')
class Properties extends Table with SyncedColumns {
  TextColumn get name => text()();
  TextColumn get address => text()();
  TextColumn get type => text().withDefault(const Constant('building'))();
  IntColumn get billDay => integer().withDefault(const Constant(1))();
}

@TableIndex(name: 'idx_units_property', columns: {#propertyId})
class Units extends Table with SyncedColumns {
  TextColumn get propertyId => text().references(Properties, #id)();
  TextColumn get unitNo => text()();
  TextColumn get floor => text().nullable()();
  IntColumn get rentAmount => integer()();
  TextColumn get status =>
      textEnum<UnitStatus>().withDefault(Constant(UnitStatus.vacant.name))();
}

/// Basic tenant data. Sensitive data lives in [TenantVaults].
@TableIndex(name: 'idx_tenants_org_unit', columns: {#orgId, #unitId})
class Tenants extends Table with SyncedColumns {
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get phone => text()();
  TextColumn get email => text().nullable()();
  TextColumn get unitId => text().references(Units, #id)();
  DateTimeColumn get leaseStart => dateTime()();
  DateTimeColumn get leaseEnd => dateTime().nullable()();
  IntColumn get monthlyRent => integer()();
  IntColumn get serviceCharge => integer().withDefault(const Constant(0))();
  TextColumn get status =>
      textEnum<TenantStatus>().withDefault(Constant(TenantStatus.active.name))();
}

/// Sensitive tenant data: only Owner/Admin (and the tenant) may read it.
class TenantVaults extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get nidNo => text().nullable()();
  TextColumn get nidFrontDocId => text().nullable()();
  TextColumn get nidBackDocId => text().nullable()();
  TextColumn get permanentAddress => text().nullable()();
  TextColumn get emergencyContact => text().nullable()();
}

@TableIndex(name: 'idx_household_tenant', columns: {#tenantId})
class HouseholdMembers extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get type => textEnum<HouseholdType>()();
  TextColumn get name => text()();
  TextColumn get relation => text().nullable()();
  IntColumn get age => integer().nullable()();
  TextColumn get note => text().nullable()();
}

/// Sensitive household member data (phone, ID number, photo).
class HouseholdVaults extends Table with SyncedColumns {
  TextColumn get householdMemberId => text().references(HouseholdMembers, #id)();
  TextColumn get phone => text().nullable()();
  TextColumn get idNo => text().nullable()();
  TextColumn get photoDocId => text().nullable()();
}

@TableIndex(name: 'idx_leases_tenant', columns: {#tenantId})
class Leases extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get unitId => text().references(Units, #id)();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get rentAmount => integer()();
  IntColumn get deposit => integer().withDefault(const Constant(0))();
  RealColumn get annualIncreasePercent => real().withDefault(const Constant(0))();
  TextColumn get terms => text().nullable()();
  TextColumn get documentId => text().nullable()();
  TextColumn get status =>
      textEnum<LeaseStatus>().withDefault(Constant(LeaseStatus.active.name))();
}

class Deposits extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  IntColumn get amount => integer()();
  IntColumn get adjustedAmount => integer().withDefault(const Constant(0))();
  IntColumn get refundedAmount => integer().withDefault(const Constant(0))();
  TextColumn get status =>
      textEnum<DepositStatus>().withDefault(Constant(DepositStatus.held.name))();
}
