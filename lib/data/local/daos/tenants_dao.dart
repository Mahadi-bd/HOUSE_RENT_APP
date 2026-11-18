import 'package:drift/drift.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/local/tables/property_tables.dart';

part 'tenants_dao.g.dart';

/// Reads and soft-deletes tenants. More queries arrive in Phase 2.
@DriftAccessor(tables: [Tenants])
class TenantsDao extends DatabaseAccessor<AppDatabase> with _$TenantsDaoMixin {
  /// Creates the DAO.
  TenantsDao(super.attachedDatabase);

  /// Active tenants of [orgId], not deleted, newest first.
  Stream<List<Tenant>> watchActive(String orgId) {
    final query = select(tenants)
      ..where(
        (t) =>
            t.orgId.equals(orgId) &
            t.deletedAt.isNull() &
            t.status.equalsValue(TenantStatus.active),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  /// Marks a tenant of [orgId] as moved out and hidden. Call it only from
  /// TenantsRepository.softDelete, which also frees the unit, archives and audits in one
  /// transaction.
  Future<int> softDelete(String orgId, String id, DateTime at, String hlc) {
    return (update(tenants)..where((t) => t.id.equals(id) & t.orgId.equals(orgId))).write(
      TenantsCompanion(
        deletedAt: Value(at),
        updatedAt: Value(at),
        status: Value(TenantStatus.vacated),
        hlc: Value(hlc),
        syncStatus: Value(SyncStatus.pending),
      ),
    );
  }
}
