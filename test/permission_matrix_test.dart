import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';

void main() {
  group('role defaults (Master Prompt v3)', () {
    test('only owner and admin can delete, edit payments, manage members, view audit', () {
      for (final role in Role.values) {
        final access = MemberAccess(role: role);
        for (final p in adminOnlyPermissions) {
          expect(access.can(p), role.isAdminLevel, reason: '${role.name} / ${p.name}');
        }
      }
    });

    test('manager: no property edit, no settings, no sensitive data', () {
      const a = MemberAccess(role: Role.manager);
      expect(a.can(Permission.propertyWrite), isFalse);
      expect(a.can(Permission.settingsManage), isFalse);
      expect(a.can(Permission.tenantSensitiveRead), isFalse);
      expect(a.can(Permission.tenantWrite), isTrue);
      expect(a.can(Permission.reportsView), isTrue);
      expect(a.can(Permission.billAdjust), isTrue);
    });

    test('caretaker: collects payments, cannot write tenants, no reports, no expenses', () {
      const a = MemberAccess(role: Role.caretaker);
      expect(a.can(Permission.paymentCreate), isTrue);
      expect(a.can(Permission.tenantWrite), isFalse);
      expect(a.can(Permission.reportsView), isFalse);
      expect(a.can(Permission.expenseCreate), isFalse);
      expect(a.can(Permission.billSend), isTrue);
    });

    test('tenant sees only own records and can open tickets', () {
      expect(
        const MemberAccess(role: Role.tenant).effective,
        {Permission.ticketCreate, Permission.ownRecordsView},
      );
    });
  });

  group('overrides', () {
    test('grant sensitive view needs vault access too', () {
      const withoutVault = MemberAccess(
        role: Role.manager,
        grants: {Permission.tenantSensitiveRead},
      );
      const withVault = MemberAccess(
        role: Role.manager,
        grants: {Permission.tenantSensitiveRead},
        vaultAccess: true,
      );
      expect(withoutVault.can(Permission.tenantSensitiveRead), isFalse);
      expect(withVault.can(Permission.tenantSensitiveRead), isTrue);
    });

    test('admin-only permissions can never be granted', () {
      const access = MemberAccess(
        role: Role.manager,
        grants: {Permission.deleteAny, Permission.paymentEdit, Permission.membersManage},
      );
      expect(access.can(Permission.deleteAny), isFalse);
      expect(access.can(Permission.paymentEdit), isFalse);
      expect(access.can(Permission.membersManage), isFalse);
    });

    test('revokes remove default permissions', () {
      const access = MemberAccess(role: Role.manager, revokes: {Permission.paymentCreate});
      expect(access.can(Permission.paymentCreate), isFalse);
    });

    test('suspended and revoked members have no permissions', () {
      for (final status in [MemberStatus.suspended, MemberStatus.revoked]) {
        expect(MemberAccess(role: Role.owner, status: status).effective, isEmpty);
      }
    });
  });

  group('property scope and own record', () {
    test('empty scope means all properties; scoped manager sees only listed ones', () {
      const all = MemberAccess(role: Role.manager);
      const scoped = MemberAccess(role: Role.manager, propertyScope: {'p1'});
      expect(all.canAccessProperty('p9'), isTrue);
      expect(scoped.canAccessProperty('p1'), isTrue);
      expect(scoped.canAccessProperty('p2'), isFalse);
      expect(const MemberAccess(role: Role.admin, propertyScope: {'p1'}).canAccessProperty('p2'),
          isTrue);
    });

    test('tenant owns only the linked tenant record', () {
      const tenant = MemberAccess(role: Role.tenant, linkedTenantId: 't1');
      expect(tenant.isOwnTenant('t1'), isTrue);
      expect(tenant.isOwnTenant('t2'), isFalse);
    });
  });

  group('AccessGuard (repository-level enforcement)', () {
    test('nobody signed in: everything is refused', () {
      const guard = AccessGuard(null);
      expect(() => guard.require(Permission.tenantBasicRead), throwsA(isA<PermissionDenied>()));
    });

    test('scoped manager cannot touch another property', () {
      const guard = AccessGuard(MemberAccess(role: Role.manager, propertyScope: {'p1'}));
      expect(() => guard.requireInProperty(Permission.tenantWrite, 'p1'), returnsNormally);
      expect(
        () => guard.requireInProperty(Permission.tenantWrite, 'p2'),
        throwsA(isA<PermissionDenied>()),
      );
    });

    test('tenant reads own record, not others; vault only own', () {
      const guard = AccessGuard(MemberAccess(role: Role.tenant, linkedTenantId: 't1'));
      expect(
        () => guard.requireOwnOrInProperty(
          tenantId: 't1',
          propertyId: 'p1',
          permission: Permission.tenantBasicRead,
        ),
        returnsNormally,
      );
      expect(
        () => guard.requireOwnOrInProperty(
          tenantId: 't2',
          propertyId: 'p1',
          permission: Permission.tenantBasicRead,
        ),
        throwsA(isA<PermissionDenied>()),
      );
      expect(() => guard.requireVaultRead('t1'), returnsNormally);
      expect(() => guard.requireVaultRead('t2'), throwsA(isA<PermissionDenied>()));
    });

    test('manager without vault access cannot read vault', () {
      const guard = AccessGuard(MemberAccess(role: Role.manager));
      expect(() => guard.requireVaultRead('t1'), throwsA(isA<PermissionDenied>()));
    });
  });

  group('admin restrictions set by the owner', () {
    test('the owner can take permissions away from an admin, except protected ones', () {
      const admin = MemberAccess(
        role: Role.admin,
        revokes: {Permission.paymentCreate, Permission.tenantWrite, Permission.ownRecordsView},
      );
      expect(admin.can(Permission.paymentCreate), isFalse);
      expect(admin.can(Permission.tenantWrite), isFalse);
      expect(admin.can(Permission.ownRecordsView), isTrue);
      expect(admin.can(Permission.deleteAny), isTrue);
    });

    test('an owner can never be restricted', () {
      const owner = MemberAccess(role: Role.owner, revokes: {Permission.deleteAny, Permission.paymentCreate});
      expect(owner.can(Permission.deleteAny), isTrue);
      expect(owner.can(Permission.paymentCreate), isTrue);
    });
  });
}
