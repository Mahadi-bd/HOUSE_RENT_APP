import 'package:drift/native.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/data/local/database.dart';
import 'dart:io';

import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/repositories/archive_repository.dart';
import 'package:rent_solution/data/repositories/charges_repository.dart';
import 'package:rent_solution/data/repositories/documents_repository.dart';
import 'package:rent_solution/data/repositories/household_repository.dart';
import 'package:rent_solution/data/repositories/legal_repositories.dart';
import 'package:rent_solution/data/repositories/police_repository.dart';
import 'package:rent_solution/data/repositories/tenant_vault_repository.dart';
import 'package:rent_solution/data/repositories/expenses_repository.dart';
import 'package:rent_solution/data/repositories/payments_repository.dart';
import 'package:rent_solution/data/repositories/properties_repository.dart';
import 'package:rent_solution/data/repositories/tenants_repository.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Fixed "today" for money tests: 10 Nov 2026, 12:00 in Bangladesh.
final testNow = DateTime.utc(2026, 11, 10, 6);

/// A stand-in for Firebase: the "email link" is accepted unless [failWith] is set.
class FakeReauthProvider implements ReauthProvider {
  FakeReauthProvider({this.uid = 'owner-uid', this.email = 'owner@example.com'});

  String? uid;
  String? email;
  String? failWith;
  String? returnUid;
  int linksSent = 0;

  @override
  String? get currentUid => uid;

  @override
  String? get currentEmail => email;

  @override
  Future<void> sendLink(String email) async {
    if (failWith == 'offline') {
      throw const ConfirmationException('offline');
    }
    linksSent++;
  }

  @override
  Future<String> reauthenticate({required String email, required String link}) async {
    if (failWith != null) {
      throw ConfirmationException(failWith!);
    }
    return returnUid ?? uid!;
  }
}

/// The confirmation service shared by the test repositories.
final fakeReauth = FakeReauthProvider();
final confirmations = ConfirmationService(fakeReauth);

/// Runs the real begin/complete flow with the fake provider and returns a one-time token.
Future<ConfirmationToken> confirmed(SensitiveAction action, String entityId) async {
  final pending = await confirmations.begin(action: action, entityId: entityId);
  return confirmations.complete(pending, 'https://link.example/ok');
}

AppDatabase memoryDb() => AppDatabase(NativeDatabase.memory());

WriteContext contextAt(
  DateTime now, {
  String userId = 'owner-uid',
  String deviceId = 'device-1',
  String orgId = 'org',
}) =>
    WriteContext(orgId: orgId, userId: userId, deviceId: deviceId, clock: () => now);

AccessGuard guardFor(MemberAccess? access) => AccessGuard(access);

const ownerAccess = MemberAccess(role: Role.owner);

PropertiesRepository propertiesFor(AppDatabase db, MemberAccess? a, [DateTime? now, String orgId = 'org']) =>
    PropertiesRepository(db, guardFor(a), contextAt(now ?? testNow, orgId: orgId));
TenantsRepository tenantsFor(AppDatabase db, MemberAccess? a, [DateTime? now, String orgId = 'org']) =>
    TenantsRepository(db, guardFor(a), contextAt(now ?? testNow, orgId: orgId), confirmations);
PaymentsRepository paymentsFor(AppDatabase db, MemberAccess? a, [DateTime? now, String orgId = 'org']) =>
    PaymentsRepository(db, guardFor(a), contextAt(now ?? testNow, orgId: orgId), confirmations);
ChargesRepository chargesFor(AppDatabase db, MemberAccess? a, [DateTime? now, String orgId = 'org']) =>
    ChargesRepository(db, guardFor(a), contextAt(now ?? testNow, orgId: orgId), confirmations);
ExpensesRepository expensesFor(AppDatabase db, MemberAccess? a, [DateTime? now, String orgId = 'org']) =>
    ExpensesRepository(db, guardFor(a), contextAt(now ?? testNow, orgId: orgId), confirmations);

HouseholdRepository householdFor(AppDatabase db, MemberAccess? a, [DateTime? now, String orgId = 'org']) =>
    HouseholdRepository(db, guardFor(a), contextAt(now ?? testNow, orgId: orgId), confirmations);
TenantVaultRepository vaultFor(AppDatabase db, MemberAccess? a, [DateTime? now, String orgId = 'org']) =>
    TenantVaultRepository(db, guardFor(a), contextAt(now ?? testNow, orgId: orgId));
DocumentsRepository documentsFor(
  AppDatabase db,
  MemberAccess? a,
  Directory root, {
  KeyValueStore? keyStore,
  String orgId = 'org',
}) =>
    DocumentsRepository(
      db,
      guardFor(a),
      contextAt(testNow, orgId: orgId),
      confirmations,
      VaultKeyStore(keyStore ?? sharedKeyStore),
      root,
    );

ArchiveRepository archiveFor(
  AppDatabase db,
  MemberAccess? a,
  Directory root, {
  DateTime? now,
  String orgId = 'org',
}) {
  final at = now ?? testNow;
  return ArchiveRepository(
    db,
    guardFor(a),
    contextAt(at, orgId: orgId),
    paymentsFor(db, a, at, orgId),
    root,
  );
}

LegalRecordsRepository legalFor(AppDatabase db, MemberAccess? a, Directory root, {KeyValueStore? keyStore, String orgId = 'org'}) =>
    LegalRecordsRepository(db, guardFor(a), contextAt(testNow, orgId: orgId), documentsFor(db, a, root, keyStore: keyStore, orgId: orgId));

LegalErasureRepository erasureFor(AppDatabase db, MemberAccess? a, Directory root, {String orgId = 'org'}) =>
    LegalErasureRepository(db, guardFor(a), contextAt(testNow, orgId: orgId), confirmations, archiveFor(db, a, root, orgId: orgId));

PoliceFormRepository policeFor(AppDatabase db, MemberAccess? a, {String orgId = 'org'}) =>
    PoliceFormRepository(db, guardFor(a), contextAt(testNow, orgId: orgId));

/// Key store shared by document tests unless a test brings its own.
final sharedKeyStore = MemoryKeyValueStore();

/// Staff with approved vault access (read and write).
const vaultStaff = MemberAccess(
  role: Role.manager,
  vaultAccess: true,
  grants: {Permission.tenantSensitiveRead, Permission.tenantSensitiveWrite},
);

/// A property, a unit (rent 10,000 BDT) and a tenant whose lease started 1 Sep 2026.
Future<({String propertyId, String unitId, String tenantId})> seedTenant(
  AppDatabase db, {
  int monthlyRent = 1000000,
  String unitNo = 'A1',
  String? propertyId,
}) async {
  final props = propertiesFor(db, ownerAccess);
  final pid = propertyId ?? await props.createProperty(name: 'Rahim Villa', address: 'Khulna');
  final uid = await props.createUnit(propertyId: pid, unitNo: unitNo, rentAmount: monthlyRent);
  final tid = await tenantsFor(db, ownerAccess).create(
    name: 'Karim',
    phone: '01711111111',
    unitId: uid,
    leaseStart: DateTime.utc(2026, 9, 1),
    monthlyRent: monthlyRent,
  );
  return (propertyId: pid, unitId: uid, tenantId: tid);
}

/// In-memory database executor for tests.
class NativeDatabaseForTest {
  const NativeDatabaseForTest._();

  /// A fresh in-memory executor.
  static NativeDatabase memory() => NativeDatabase.memory();
}
