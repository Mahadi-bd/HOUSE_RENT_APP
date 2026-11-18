import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/brand_header.dart';

/// Home for a tenant member: only their own due, advance and current month.
class TenantHomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const TenantHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final fmt = context.fmt;
    final scheme = Theme.of(context).colorScheme;
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final tenantId = access?.linkedTenantId;
    final org = ref.watch(localOrganizationProvider).dataOrNull;
    if (tenantId == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [Text(t.onlyYourRecords)]);
    }
    final statement = ref.watch(tenantStatementProvider(tenantId));
    final tenant = ref.watch(tenantProvider(tenantId));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BrandHeader(name: org?.name ?? BrandConfig.companyName),
        const SizedBox(height: 16),
        Text(tenant.dataOrNull?.name ?? '', style: Theme.of(context).textTheme.titleLarge),
        if (tenant.dataOrNull != null)
          Text(t.leaseFrom(fmt.date(tenant.dataOrNull!.leaseStart.toLocal()))),
        const SizedBox(height: 16),
        statement.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(friendlyError(t, e)),
          data: (s) {
            final ledger = s.ledger;
            final thisMonth = ledger.months.where((m) => m.month == monthKeyOf(DateTime.now())).firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ledger.outstanding > 0) ...[
                          Text(t.homeYouOwe),
                          Text(
                            fmt.money(ledger.outstanding),
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: scheme.error),
                          ),
                        ] else if (ledger.advanceCredit > 0) ...[
                          Text(t.homeYouPaidAdvance),
                          Text(
                            fmt.money(ledger.advanceCredit),
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: scheme.tertiary),
                          ),
                        ] else
                          Text(t.homeNothingOwed, style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                ),
                if (thisMonth != null) ...[
                  const SizedBox(height: 16),
                  Text(t.homeThisMonth, style: Theme.of(context).textTheme.titleMedium),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(fmt.monthLabel(thisMonth.month)),
                    subtitle: Text(t.paidOf(fmt.money(thisMonth.paid), fmt.money(thisMonth.charged))),
                  ),
                ],
                const SizedBox(height: 8),
                Text(t.onlyYourRecords, style: Theme.of(context).textTheme.bodySmall),
                const BrandFooter(),
              ],
            );
          },
        ),
      ],
    );
  }
}
