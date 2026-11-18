import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/data/local/daos/audit_dao.dart';
import 'package:rent_solution/data/local/daos/tenants_dao.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/local/tables/money_tables.dart';
import 'package:rent_solution/data/local/tables/operations_tables.dart';
import 'package:rent_solution/data/local/tables/organization_tables.dart';
import 'package:rent_solution/data/local/tables/property_tables.dart';
import 'package:rent_solution/data/local/tables/synced_columns.dart';
import 'package:rent_solution/data/local/tables/system_tables.dart';

part 'database.g.dart';

/// The encrypted local database (single source of truth on this device).
@DriftDatabase(
  tables: [
    Organizations,
    AppUsers,
    Memberships,
    Invitations,
    AppSettings,
    OrgProfiles,
    Properties,
    Units,
    Tenants,
    TenantVaults,
    HouseholdMembers,
    HouseholdVaults,
    Leases,
    Deposits,
    Payments,
    Bills,
    BillItems,
    MeterReadings,
    LateFeeRules,
    Expenses,
    ExtraCharges,
    MaintenanceTickets,
    Documents,
    DeletionRequests,
    Notifications,
    LegalRecords,
    ErasureRequests,
    PoliceShares,
    DeletedArchives,
    MessageTemplates,
    OcrScans,
    CctvCameras,
    AuditLogs,
    SyncOps,
  ],
  daos: [TenantsDao, AuditDao],
)
class AppDatabase extends _$AppDatabase {
  /// Creates the database on top of [super.e] (encrypted file or in-memory for tests).
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createAuditTriggers();
          await _createPartialUniqueIndexes();
        },
        beforeOpen: (details) async {
          // Synced rows may arrive out of order. The sync applier (Phase 3) must run inside a
          // transaction that first executes PRAGMA defer_foreign_keys = ON.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Unique rules that ignore soft-deleted rows, so a deleted unit number can be reused.
  Future<void> _createPartialUniqueIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_units_property_unit '
      'ON units (property_id, unit_no) WHERE deleted_at IS NULL',
    );
    // A transaction ID is unique per organization AND provider (bKash, Nagad, Rocket...), among
    // payments that are not cancelled. Two writers can never both insert the same one.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_trx '
      'ON payments (org_id, method, trx_id) WHERE deleted_at IS NULL AND trx_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_tenant_vaults_tenant '
      'ON tenant_vaults (tenant_id) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_household_vaults_member '
      'ON household_vaults (household_member_id) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_org_profiles_org '
      'ON org_profiles (org_id) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_memberships_org_user '
      'ON memberships (org_id, user_id) WHERE deleted_at IS NULL',
    );
  }

  /// Audit rows can never be changed or removed, even by app bugs.
  Future<void> _createAuditTriggers() async {
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS audit_logs_no_update BEFORE UPDATE ON audit_logs '
      "BEGIN SELECT RAISE(ABORT, 'audit_logs is append-only'); END;",
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS audit_logs_no_delete BEFORE DELETE ON audit_logs '
      "BEGIN SELECT RAISE(ABORT, 'audit_logs is append-only'); END;",
    );
  }
}
