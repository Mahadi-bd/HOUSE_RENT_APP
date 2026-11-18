import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/language_dropdown.dart';

/// The profile of a tenant member: their own details, language and sign out (not Settings).
class TenantMyProfileScreen extends ConsumerWidget {
  /// Creates the screen.
  const TenantMyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final fmt = context.fmt;
    final tenantId = ref.watch(memberAccessProvider).dataOrNull?.linkedTenantId;
    final labels = ref.watch(unitLabelsProvider).dataOrNull ?? const <String, String>{};
    final tenant = tenantId == null ? null : ref.watch(tenantProvider(tenantId));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.tabProfile, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (tenant == null)
          Text(t.onlyYourRecords)
        else
          tenant.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(friendlyError(t, e)),
            data: (row) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.profileSection, style: Theme.of(context).textTheme.titleMedium),
                ListTile(contentPadding: EdgeInsets.zero, title: Text(row.name), subtitle: Text(t.tenantName)),
                ListTile(contentPadding: EdgeInsets.zero, title: Text(row.phone), subtitle: Text(t.phoneLabel)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(labels[row.unitId] ?? ''),
                  subtitle: Text(t.unitPickLabel),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(fmt.date(row.leaseStart.toLocal())),
                  subtitle: Text(t.leaseStartLabel),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(fmt.money(row.monthlyRent)),
                  subtitle: Text(t.monthlyRentLabel),
                ),
                const SizedBox(height: 8),
                Text(t.onlyYourRecords, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const LanguageDropdown(),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => context.push(RouteNames.about),
          child: Text(t.openAbout),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          child: Text(t.signOut),
        ),
        const BrandFooter(),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => context.push(RouteNames.about),
          icon: const Icon(Icons.info_outline),
          label: Text(t.aboutTitle),
        ),
        const BrandFooter(),
      ],
    );
  }
}
