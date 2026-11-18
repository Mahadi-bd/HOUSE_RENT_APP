import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/local_secrets.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/open_database.dart';
import 'package:rent_solution/data/sync/hlc.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';

/// Creates the first organization and its owner on this device.
class OrganizationRepository {
  /// Creates the repository.
  OrganizationRepository(this._db, this._secrets);

  final AppDatabase _db;
  final LocalSecrets _secrets;

  /// Creates the organization, the owner's user row, membership and settings in one transaction.
  Future<void> createOrganization({
    required String uid,
    required String name,
    String? displayName,
    String? email,
    String? ownerName,
  }) async {
    final deviceId = await _secrets.deviceId();
    final now = DateTime.now().toUtc();
    final orgId = newId();
    final stamp = hlcNow(deviceId);
    await _db.transaction(() async {
      await _db.into(_db.organizations).insert(
            OrganizationsCompanion.insert(
              id: orgId,
              orgId: orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: uid,
              deviceId: deviceId,
              hlc: stamp,
              name: name,
              ownerUid: uid,
            ),
          );
      await _db.into(_db.appUsers).insertOnConflictUpdate(
            AppUsersCompanion.insert(
              id: uid,
              orgId: orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: uid,
              deviceId: deviceId,
              hlc: stamp,
              name: displayName ?? '',
              email: email ?? '',
            ),
          );
      await _db.into(_db.memberships).insert(
            MembershipsCompanion.insert(
              id: newId(),
              orgId: orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: uid,
              deviceId: deviceId,
              hlc: stamp,
              userId: uid,
              role: Role.owner,
              status: MemberStatus.active,
              vaultAccess: const Value(true),
            ),
          );
      await _db.into(_db.orgProfiles).insert(
            OrgProfilesCompanion.insert(
              id: newId(),
              orgId: orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: uid,
              deviceId: deviceId,
              hlc: stamp,
              displayName: name,
              ownerName: Value(ownerName),
              email: Value(email),
            ),
          );
      await _db.into(_db.appSettings).insert(
            AppSettingsCompanion.insert(
              id: newId(),
              orgId: orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: uid,
              deviceId: deviceId,
              hlc: stamp,
              userId: uid,
            ),
          );
    });
  }
}

/// The organization stored on this device, or null before setup.
final localOrganizationProvider = StreamProvider<Organization?>((ref) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query = db.select(db.organizations)..limit(1);
  yield* query.watch().map((rows) => rows.isEmpty ? null : rows.first);
});

Set<String> _stringsFromJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List<dynamic>) {
    return const {};
  }
  return {for (final value in decoded) if (value is String) value};
}

Set<Permission> _permissionsFromJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List<dynamic>) {
    return const {};
  }
  return {
    for (final name in decoded)
      for (final permission in Permission.values)
        if (permission.name == name) permission,
  };
}

/// The signed-in user's access in this organization (null if no membership row).
final memberAccessProvider = StreamProvider<MemberAccess?>((ref) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final user = ref.watch(authStateProvider).dataOrNull;
  if (user == null) {
    yield null;
    return;
  }
  final query = db.select(db.memberships)
    ..where((m) => m.userId.equals(user.uid) & m.deletedAt.isNull())
    ..limit(1);
  yield* query.watch().map((rows) {
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return MemberAccess(
      role: row.role,
      status: row.status,
      grants: _permissionsFromJson(row.grants),
      revokes: _permissionsFromJson(row.revokes),
      propertyScope: _stringsFromJson(row.propertyScope),
      vaultAccess: row.vaultAccess,
      linkedTenantId: row.linkedTenantId,
    );
  });
});

/// Runs "create organization" with loading, success and error states.
class CreateOrganizationController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates the organization named [name] for the signed-in user.
  Future<void> create(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) {
        throw const AuthFailure('not_signed_in');
      }
      final db = await ref.read(appDatabaseProvider.future);
      await OrganizationRepository(db, ref.read(localSecretsProvider))
          .createOrganization(
            uid: user.uid,
            displayName: user.displayName,
            email: user.email,
            name: name.trim(),
            ownerName: BrandConfig.ownerName,
          );
    });
  }
}

/// Controller provider for the setup screen.
final createOrganizationControllerProvider =
    NotifierProvider<CreateOrganizationController, AsyncValue<void>>(
  CreateOrganizationController.new,
);
