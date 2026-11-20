import 'package:flutter/material.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/routing/route_names.dart';

/// One bottom-navigation tab.
class AppDestination {
  /// Creates a destination.
  const AppDestination({required this.path, required this.icon, required this.labelOf});

  /// Route path.
  final String path;

  /// Tab icon.
  final IconData icon;

  /// Localized tab label.
  final String Function(AppLocalizations) labelOf;
}

final _dashboard = AppDestination(
  path: RouteNames.dashboard,
  icon: Icons.dashboard_outlined,
  labelOf: (t) => t.tabDashboard,
);
final _tenants = AppDestination(
  path: RouteNames.tenants,
  icon: Icons.people_outline,
  labelOf: (t) => t.tabTenants,
);
final _payments = AppDestination(
  path: RouteNames.payments,
  icon: Icons.payments_outlined,
  labelOf: (t) => t.tabPayments,
);
final _reports = AppDestination(
  path: RouteNames.reports,
  icon: Icons.bar_chart_outlined,
  labelOf: (t) => t.tabReports,
);
final _tickets = AppDestination(
  path: RouteNames.tickets,
  icon: Icons.build_outlined,
  labelOf: (t) => t.tabTickets,
);
final _settings = AppDestination(
  path: RouteNames.settings,
  icon: Icons.settings_outlined,
  labelOf: (t) => t.tabSettings,
);

/// Tabs for each role, as defined in the Master Prompt:
/// Owner/Admin/Manager: Dashboard, Tenants, Payments, Reports, Settings.
/// Caretaker: Dashboard, Tenants, Payments, Tickets.
/// Tenant: Home, My Payments, My Tickets, Profile.
List<AppDestination> destinationsForRole(Role role) {
  switch (role) {
    case Role.owner:
    case Role.admin:
    case Role.manager:
      return [_dashboard, _tenants, _payments, _reports, _settings];
    case Role.caretaker:
      return [_dashboard, _tenants, _payments, _tickets];
    case Role.tenant:
      return [
        AppDestination(
          path: RouteNames.dashboard,
          icon: Icons.home_outlined,
          labelOf: (t) => t.tabHome,
        ),
        AppDestination(
          path: RouteNames.payments,
          icon: Icons.payments_outlined,
          labelOf: (t) => t.tabMyPayments,
        ),
        AppDestination(
          path: RouteNames.tickets,
          icon: Icons.build_outlined,
          labelOf: (t) => t.tabMyTickets,
        ),
        AppDestination(
          path: RouteNames.profile,
          icon: Icons.person_outline,
          labelOf: (t) => t.tabProfile,
        ),
      ];
  }
}

/// Tabs this member may see. Nobody (null or not active) sees none.
List<AppDestination> visibleDestinations(MemberAccess? access) {
  if (access == null || access.status != MemberStatus.active) {
    return const [];
  }
  return destinationsForRole(access.role);
}

/// Whether [access] may open the page at [location]. Unknown paths are refused.
/// The profile page is open to every active member (language, sign out).
bool canOpenPath(MemberAccess? access, String location) {
  if (access == null || access.status != MemberStatus.active) {
    return false;
  }
  if (location.startsWith(RouteNames.profile)) {
    return true;
  }
  if (location.startsWith(RouteNames.about)) {
    return true;
  }
  if (location.startsWith(RouteNames.about)) {
    return true;
  }
  if (location.startsWith(RouteNames.archive)) {
    return access.can(Permission.archiveRestore) || access.can(Permission.legalRecords);
  }
  if (location.startsWith(RouteNames.business)) {
    return access.can(Permission.settingsManage);
  }
  if (location.startsWith(RouteNames.expenses)) {
    return access.can(Permission.reportsView) || access.can(Permission.expenseCreate);
  }
  if (location.startsWith(RouteNames.properties)) {
    return access.can(Permission.tenantBasicRead);
  }
  return destinationsForRole(access.role).any((d) => location.startsWith(d.path));
}
