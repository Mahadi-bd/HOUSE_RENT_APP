import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/localization/role_labels.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/tenants/presentation/tenant_home_screen.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/brand_header.dart';
import 'package:rent_solution/shared/widgets/empty_state.dart';

/// Dashboard: for staff, the business header and shortcuts (real totals arrive in Phase 4);
/// for a tenant member, their own home screen.
class DashboardTab extends ConsumerWidget {
  /// Creates the tab.
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final org = ref.watch(localOrganizationProvider).dataOrNull;
    if (access?.role == Role.tenant) {
      return const TenantHomeScreen();
    }
    final canProperties = access?.can(Permission.tenantBasicRead) ?? false;
    final canExpenses = access?.can(Permission.reportsView) ?? false;
    final canBusiness = access?.can(Permission.settingsManage) ?? false;
    final canArchive = access?.can(Permission.archiveRestore) ?? false;
    if (canArchive) {
      // Once per app start: remove archive items older than 2 years.
      ref.watch(autoPurgeProvider);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BrandHeader(name: org?.name),
        const SizedBox(height: 8),
        if (access != null) Text(t.signedInAs(roleLabel(t, access.role))),
        const SizedBox(height: 8),
        Text(t.dashboardHint),
        const SizedBox(height: 24),
        if (canProperties)
          FilledButton.icon(
            onPressed: () => context.push(RouteNames.properties),
            icon: const Icon(Icons.home_work_outlined),
            label: Text(t.propertiesTitle),
          ),
        if (canExpenses) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(RouteNames.expenses),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(t.openExpenses),
          ),
        ],
        OutlinedButton.icon(
          onPressed: () => context.push(RouteNames.about),
          icon: const Icon(Icons.info_outline),
          label: Text(t.openAbout),
        ),
        if (canArchive) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(RouteNames.archive),
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(t.openArchive),
          ),
        ],
        if (canBusiness) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(RouteNames.business),
            icon: const Icon(Icons.business_outlined),
            label: Text(t.businessDetails),
          ),
        ],
        const BrandFooter(),
      ],
    );
  }
}

/// Reports placeholder.
class ReportsTab extends StatelessWidget {
  /// Creates the tab.
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.bar_chart_outlined,
      title: t.tabReports,
      message: t.reportsEmptyMessage,
    );
  }
}

/// Tickets placeholder (maintenance tickets arrive in Phase 6).
class TicketsTab extends StatelessWidget {
  /// Creates the tab.
  const TicketsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.build_outlined,
      title: t.ticketsEmptyTitle,
      message: t.ticketsEmptyMessage,
    );
  }
}
