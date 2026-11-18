import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/domain/money/ledger.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/empty_state.dart';

/// The Tenants tab: everyone who rents, with what they still owe. Built for staff first.
class TenantsTab extends ConsumerWidget {
  /// Creates the tab.
  const TenantsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final canAdd = access?.can(Permission.tenantWrite) ?? false;
    final tenants = ref.watch(tenantsProvider);
    final balances = ref.watch(tenantBalancesProvider).dataOrNull ?? const <String, LedgerSummary>{};
    final labels = ref.watch(unitLabelsProvider).dataOrNull ?? const <String, String>{};
    final hasTenants = tenants.dataOrNull?.isNotEmpty ?? false;
    return Scaffold(
      floatingActionButton: canAdd && hasTenants
          ? FloatingActionButton.extended(
              onPressed: () => context.push('${RouteNames.tenants}/new'),
              icon: const Icon(Icons.person_add_alt),
              label: Text(t.addTenant),
            )
          : null,
      body: tenants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.people_outline,
              title: t.emptyTenantsTitle,
              message: t.emptyTenantsMessage,
              actionLabel: canAdd ? t.addTenant : null,
              onAction: canAdd ? () => context.push('${RouteNames.tenants}/new') : null,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tenant = list[index];
              return ListTile(
                title: Text(tenant.name),
                subtitle: Text(labels[tenant.unitId] ?? ''),
                trailing: _BalanceText(summary: balances[tenant.id]),
                onTap: () => context.push('${RouteNames.tenants}/${tenant.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _BalanceText extends StatelessWidget {
  const _BalanceText({required this.summary});

  final LedgerSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (s.outstanding > 0) {
      return Text(
        t.dueAmount(context.fmt.money(s.outstanding)),
        style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold),
      );
    }
    if (s.advanceCredit > 0) {
      return Text(
        t.advanceAmount(context.fmt.money(s.advanceCredit)),
        style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.bold),
      );
    }
    return Text(t.allPaid, style: TextStyle(color: scheme.tertiary));
  }
}
