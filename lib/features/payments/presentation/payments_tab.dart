import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/payments/presentation/receipt_actions.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/empty_state.dart';

/// Payments tab. Staff see the newest payments of everyone they may see; a tenant sees their own.
class PaymentsTab extends ConsumerWidget {
  /// Creates the tab.
  const PaymentsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final isTenant = access?.role == Role.tenant && access?.linkedTenantId != null;
    final AsyncValue<List<Payment>> payments = isTenant
        ? ref.watch(ownPaymentsProvider(access!.linkedTenantId!))
        : ref.watch(recentPaymentsProvider);
    final names = {
      for (final tenant in ref.watch(tenantsProvider).dataOrNull ?? const <Tenant>[])
        tenant.id: tenant.name,
    };
    final fmt = context.fmt;
    final canOpenProfile = access?.can(Permission.tenantBasicRead) ?? false;
    return payments.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(t, e))),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.payments_outlined,
            title: t.paymentsEmptyTitle,
            message: t.paymentsEmptyMessage,
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final p = list[index];
            final who = names[p.tenantId];
            return ListTile(
              title: Text(who == null ? p.receiptNo : '$who · ${p.receiptNo}'),
              subtitle: Text('${t.methodName(p.method.name)} · ${fmt.date(p.paidAt.toLocal())}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fmt.money(p.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    tooltip: t.shareReceipt,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => openReceipt(context, ref, p.id),
                  ),
                ],
              ),
              onTap: canOpenProfile ? () => context.push('${RouteNames.tenants}/${p.tenantId}') : null,
            );
          },
        );
      },
    );
  }
}
