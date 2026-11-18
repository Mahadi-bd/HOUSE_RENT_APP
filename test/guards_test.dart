import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/routing/app_destinations.dart';
import 'package:rent_solution/core/routing/guards.dart';
import 'package:rent_solution/core/routing/route_names.dart';

void main() {
  const owner = MemberAccess(role: Role.owner);
  const manager = MemberAccess(role: Role.manager);
  const caretaker = MemberAccess(role: Role.caretaker);
  const tenant = MemberAccess(role: Role.tenant, linkedTenantId: 't1');

  List<String> tabs(MemberAccess a) => visibleDestinations(a).map((d) => d.path).toList();

  group('tabs per role (Master Prompt v3)', () {
    test('owner, admin, manager', () {
      const expected = [
        RouteNames.dashboard,
        RouteNames.tenants,
        RouteNames.payments,
        RouteNames.reports,
        RouteNames.settings,
      ];
      expect(tabs(owner), expected);
      expect(tabs(const MemberAccess(role: Role.admin)), expected);
      expect(tabs(manager), expected);
    });

    test('caretaker', () {
      expect(tabs(caretaker), [
        RouteNames.dashboard,
        RouteNames.tenants,
        RouteNames.payments,
        RouteNames.tickets,
      ]);
    });

    test('tenant', () {
      expect(tabs(tenant), [
        RouteNames.dashboard,
        RouteNames.payments,
        RouteNames.tickets,
        RouteNames.profile,
      ]);
    });

    test('suspended member sees no tabs', () {
      const suspended = MemberAccess(role: Role.manager, status: MemberStatus.suspended);
      expect(tabs(suspended), isEmpty);
    });
  });

  group('redirectFor', () {
    test('loading goes to splash; signed out to sign-in; new user to setup', () {
      expect(
        redirectFor(location: RouteNames.dashboard, stage: SessionStage.loading),
        RouteNames.splash,
      );
      expect(
        redirectFor(location: RouteNames.dashboard, stage: SessionStage.signedOut),
        RouteNames.signIn,
      );
      expect(
        redirectFor(location: RouteNames.dashboard, stage: SessionStage.needsOrganization),
        RouteNames.createOrganization,
      );
    });

    test('ready members leave entry screens for the dashboard', () {
      expect(
        redirectFor(location: RouteNames.signIn, stage: SessionStage.ready, access: owner),
        RouteNames.dashboard,
      );
    });

    test('route protection per role', () {
      String? go(String path, MemberAccess a) =>
          redirectFor(location: path, stage: SessionStage.ready, access: a);
      expect(go(RouteNames.reports, caretaker), RouteNames.dashboard);
      expect(go(RouteNames.settings, caretaker), RouteNames.dashboard);
      expect(go(RouteNames.tenants, tenant), RouteNames.dashboard);
      expect(go(RouteNames.reports, tenant), RouteNames.dashboard);
      expect(go(RouteNames.tickets, caretaker), isNull);
      expect(go(RouteNames.reports, manager), isNull);
      expect(go(RouteNames.profile, caretaker), isNull);
    });

    test('unknown paths are refused by default', () {
      expect(
        redirectFor(location: '/admin/secret', stage: SessionStage.ready, access: owner),
        RouteNames.dashboard,
      );
    });

    test('suspended, revoked or missing membership goes to no-access', () {
      for (final status in [MemberStatus.suspended, MemberStatus.revoked]) {
        final a = MemberAccess(role: Role.manager, status: status);
        expect(
          redirectFor(location: RouteNames.dashboard, stage: SessionStage.ready, access: a),
          RouteNames.noAccess,
        );
      }
      expect(
        redirectFor(location: RouteNames.dashboard, stage: SessionStage.ready),
        RouteNames.noAccess,
      );
    });
  });

  group('recovery and new routes', () {
    test('a missing database key sends everyone to the recovery screen', () {
      expect(
        redirectFor(location: RouteNames.dashboard, stage: SessionStage.recovery),
        RouteNames.recovery,
      );
      expect(redirectFor(location: RouteNames.recovery, stage: SessionStage.recovery), isNull);
    });

    test('business details need settings permission; expenses need reports or expense permission', () {
      String? go(String path, MemberAccess a) =>
          redirectFor(location: path, stage: SessionStage.ready, access: a);
      expect(go('/settings/business', owner), isNull);
      expect(go('/settings/business', manager), RouteNames.dashboard);
      expect(go('/expenses', manager), isNull);
      expect(go('/expenses/new/p1', owner), isNull);
      expect(go('/expenses', caretaker), RouteNames.dashboard);
      expect(go('/expenses', tenant), RouteNames.dashboard);
      expect(go('/tenants/abc/edit', manager), isNull);
      expect(go('/tenants/abc/edit', tenant), RouteNames.dashboard);
    });
  });
}
