import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/data/repositories/documents_repository.dart';
import 'package:rent_solution/data/repositories/household_repository.dart';
import 'package:rent_solution/data/repositories/tenant_vault_repository.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rent_solution/core/security/audit_checkpoint.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/data/local/open_database.dart';
import 'package:rent_solution/data/repositories/charges_repository.dart';
import 'package:rent_solution/data/repositories/documents_repository.dart';
import 'package:rent_solution/data/repositories/expenses_repository.dart';
import 'package:rent_solution/data/repositories/household_repository.dart';
import 'package:rent_solution/data/repositories/ocr_repository.dart';
import 'package:rent_solution/data/repositories/org_profile_repository.dart';
import 'package:rent_solution/data/repositories/payments_repository.dart';
import 'package:rent_solution/data/repositories/properties_repository.dart';
import 'package:rent_solution/data/repositories/tenant_vault_repository.dart';
import 'package:rent_solution/data/repositories/tenants_repository.dart';
import 'package:rent_solution/data/repositories/write_context.dart';
import 'package:rent_solution/data/sync/hlc.dart';
import 'package:rent_solution/features/security/firebase_reauth_provider.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';

/// Who is writing on this device (organization, user, device).
final writeContextProvider = FutureProvider<WriteContext>((ref) async {
  final org = await ref.watch(localOrganizationProvider.future);
  final user = ref.watch(authStateProvider).dataOrNull;
  if (org == null || user == null) {
    throw StateError('Not signed in.');
  }
  final deviceId = await ref.watch(localSecretsProvider).deviceId();
  const store = SecureKeyValueStore();
  await initHlc(deviceId, store);
  return WriteContext(
    orgId: org.id,
    userId: user.uid,
    deviceId: deviceId,
    checkpoints: const AuditCheckpointStore(store),
  );
});

/// Permission checker for the signed-in member.
final accessGuardProvider = Provider<AccessGuard>(
  (ref) => AccessGuard(ref.watch(memberAccessProvider).dataOrNull),
);

/// Bumped after every write so screens that read once (not streams) refresh.
class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// Tells screens that data changed.
  void bump() => state = state + 1;
}

/// The data revision counter.
final dataRevisionProvider = NotifierProvider<DataRevision, int>(DataRevision.new);

/// Properties and units.
final propertiesRepositoryProvider = FutureProvider<PropertiesRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return PropertiesRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
  );
});

/// Tenants.
final tenantsRepositoryProvider = FutureProvider<TenantsRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return TenantsRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
  );
});

/// Payments.
final paymentsRepositoryProvider = FutureProvider<PaymentsRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return PaymentsRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
  );
});

/// Optional extra charges.
final chargesRepositoryProvider = FutureProvider<ChargesRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return ChargesRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
  );
});

/// Expense ledger.
final expensesRepositoryProvider = FutureProvider<ExpensesRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return ExpensesRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
  );
});

/// Business details printed on receipts.
final orgProfileRepositoryProvider = FutureProvider<OrgProfileRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return OrgProfileRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
  );
});

/// Household members (basic data; vault parts need vault access).
final householdRepositoryProvider = FutureProvider<HouseholdRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return HouseholdRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
  );
});

/// NID number, address, emergency contact.
final tenantVaultRepositoryProvider = FutureProvider<TenantVaultRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return TenantVaultRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
  );
});

/// Encrypted documents on this phone.
final documentsRepositoryProvider = FutureProvider<DocumentsRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return DocumentsRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
    const VaultKeyStore(SecureKeyValueStore()),
    await getApplicationDocumentsDirectory(),
  );
});

/// People living with a tenant.
final householdRepositoryProvider = FutureProvider<HouseholdRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return HouseholdRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
  );
});

/// Private tenant details (NID, address, emergency contact).
final tenantVaultRepositoryProvider = FutureProvider<TenantVaultRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return TenantVaultRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
  );
});

/// Encrypted tenant documents.
final documentsRepositoryProvider = FutureProvider<DocumentsRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return DocumentsRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    ref.watch(confirmationServiceProvider),
    const VaultKeyStore(SecureKeyValueStore()),
    await getApplicationDocumentsDirectory(),
  );
});

/// Saves a reviewed NID scan.
final ocrRepositoryProvider = FutureProvider<OcrRepository>((ref) async {
  final guard = ref.watch(accessGuardProvider);
  return OcrRepository(
    await ref.watch(appDatabaseProvider.future),
    guard,
    await ref.watch(writeContextProvider.future),
    await ref.watch(documentsRepositoryProvider.future),
    await ref.watch(tenantVaultRepositoryProvider.future),
  );
});
