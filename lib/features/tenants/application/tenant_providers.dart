import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/documents_repository.dart';
import 'package:rent_solution/data/repositories/properties_repository.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/domain/money/ledger.dart';

/// Active tenants this member may see (live).
final tenantsProvider = StreamProvider<List<Tenant>>((ref) async* {
  final repo = await ref.watch(tenantsRepositoryProvider.future);
  yield* repo.watchActive();
});

/// One tenant.
final tenantProvider = FutureProvider.family<Tenant, String>((ref, id) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(tenantsRepositoryProvider.future);
  return repo.getById(id);
});

/// Everything the tenant profile shows about money.
class TenantStatement {
  const TenantStatement({required this.ledger, required this.payments, required this.charges});
  final LedgerSummary ledger;
  final List<Payment> payments;
  final List<ExtraCharge> charges;
}

/// Money details of one tenant.
final tenantStatementProvider = FutureProvider.family<TenantStatement, String>((ref, id) async {
  ref.watch(dataRevisionProvider);
  final payments = await ref.watch(paymentsRepositoryProvider.future);
  final charges = await ref.watch(chargesRepositoryProvider.future);
  return TenantStatement(
    ledger: await payments.ledgerFor(id),
    payments: await payments.listForTenant(id),
    charges: await charges.listForTenant(id),
  );
});

/// Outstanding or advance for every tenant.
final tenantBalancesProvider = FutureProvider<Map<String, LedgerSummary>>((ref) async {
  ref.watch(dataRevisionProvider);
  final tenants = await ref.watch(tenantsProvider.future);
  final payments = await ref.watch(paymentsRepositoryProvider.future);
  final result = <String, LedgerSummary>{};
  for (final tenant in tenants) {
    result[tenant.id] = await payments.ledgerFor(tenant.id);
  }
  return result;
});

/// Unit labels such as "Rahim Villa A1".
final unitLabelsProvider = FutureProvider<Map<String, String>>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(propertiesRepositoryProvider.future);
  return repo.unitLabels();
});

/// Vacant units for the add-tenant form.
final vacantUnitsProvider = FutureProvider.autoDispose<List<UnitChoice>>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(propertiesRepositoryProvider.future);
  return repo.vacantUnits();
});

/// Properties (live).
final propertiesProvider = StreamProvider<List<Property>>((ref) async* {
  final repo = await ref.watch(propertiesRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Units of one property (live).
final unitsOfProvider = StreamProvider.family<List<Unit>, String>((ref, propertyId) async* {
  final repo = await ref.watch(propertiesRepositoryProvider.future);
  yield* repo.watchUnits(propertyId);
});

/// The newest payments (staff).
final recentPaymentsProvider = FutureProvider.autoDispose<List<Payment>>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(paymentsRepositoryProvider.future);
  return repo.recent();
});

/// Payments of one tenant.
final ownPaymentsProvider = FutureProvider.family<List<Payment>, String>((ref, tenantId) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(paymentsRepositoryProvider.future);
  return repo.listForTenant(tenantId);
});

/// Expenses of one property in one month.
final expensesProvider = FutureProvider.autoDispose.family<List<Expense>, ({String propertyId, String month})>((ref, key) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(expensesRepositoryProvider.future);
  return repo.list(key.propertyId, month: key.month);
});

/// Business details printed on receipts.
final orgProfileProvider = FutureProvider.autoDispose<OrgProfile?>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(orgProfileRepositoryProvider.future);
  return repo.get();
});

/// Household members of one tenant (basic data).
final householdProvider = FutureProvider.autoDispose.family<List<HouseholdMember>, String>((ref, tenantId) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(householdRepositoryProvider.future);
  return repo.listBasic(tenantId);
});

/// Sensitive tenant details.
final tenantVaultProvider = FutureProvider.autoDispose.family<TenantVault?, String>((ref, tenantId) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(tenantVaultRepositoryProvider.future);
  return repo.get(tenantId);
});

/// Documents visible to this member.
final tenantDocumentsProvider = FutureProvider.autoDispose.family<List<TenantDocument>, String>((ref, tenantId) async {
  ref.watch(dataRevisionProvider);
  final repo = await ref.watch(documentsRepositoryProvider.future);
  return repo.list(tenantId);
});

/// Archive entries waiting for restore or purge.
final archiveEntriesProvider = FutureProvider.autoDispose<List<DeletedArchive>>((ref) async {
  ref.watch(dataRevisionProvider);
  return (await ref.watch(archiveRepositoryProvider.future)).list();
});

/// Legal records of a tenant.
final legalRecordsProvider = FutureProvider.autoDispose.family<List<LegalRecord>, String>((ref, tenantId) async {
  ref.watch(dataRevisionProvider);
  return (await ref.watch(legalRecordsRepositoryProvider.future)).list(tenantId);
});
