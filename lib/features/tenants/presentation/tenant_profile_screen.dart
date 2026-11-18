import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/payments/presentation/receipt_actions.dart';
import 'package:rent_solution/features/security/sensitive_actions.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/features/tenants/presentation/household_section.dart';
import 'package:rent_solution/features/tenants/presentation/vault_section.dart';

/// One tenant: contact, what is owed, optional extra charges, and payments.
class TenantProfileScreen extends ConsumerWidget {
  /// Creates the screen.
  const TenantProfileScreen({required this.tenantId, super.key});

  /// The tenant to show.
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final tenant = ref.watch(tenantProvider(tenantId));
    final statement = ref.watch(tenantStatementProvider(tenantId));
    final labels = ref.watch(unitLabelsProvider).dataOrNull ?? const <String, String>{};
    final canPay = access?.can(Permission.paymentCreate) ?? false;
    final canCharge = access?.can(Permission.chargeWrite) ?? false;
    final canEditPayment = access?.can(Permission.paymentEdit) ?? false;
    final canDelete = access?.can(Permission.deleteAny) ?? false;
    final canEditTenant = access?.can(Permission.tenantWrite) ?? false;
    final fmt = context.fmt;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tenant.dataOrNull?.name ?? ''),
        actions: [
          if (tenant.dataOrNull != null && (canEditTenant || canDelete))
            PopupMenuButton<String>(
              onSelected: (value) async {
                final row = tenant.dataOrNull!;
                if (value == 'edit') {
                  context.push('${RouteNames.tenants}/$tenantId/edit');
                } else if (value == 'out') {
                  final done = await moveTenantOutFlow(context, ref, row);
                  if (done && context.mounted) {
                    context.pop();
                  }
                }
              },
              itemBuilder: (_) => [
                if (canEditTenant) PopupMenuItem(value: 'edit', child: Text(t.editTenant)),
                if (canDelete) PopupMenuItem(value: 'out', child: Text(t.moveTenantOut)),
              ],
            ),
        ],
      ),
      body: tenant.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (tenantRow) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(labels[tenantRow.unitId] ?? '', style: Theme.of(context).textTheme.titleMedium),
            Text(tenantRow.phone),
            const SizedBox(height: 16),
            HouseholdSection(tenantId: tenantId),
            const SizedBox(height: 16),
            VaultSection(tenantId: tenantId),
            const SizedBox(height: 16),
            DocumentsSection(tenantId: tenantId),
            const SizedBox(height: 16),
            statement.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(friendlyError(t, e)),
              data: (s) {
                final ledger = s.ledger;
                final owing = ledger.outstanding > 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.balanceTitle, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            if (owing) ...[
                              Text(t.balanceDue),
                              Text(
                                fmt.money(ledger.outstanding),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(color: scheme.error),
                              ),
                            ] else if (ledger.advanceCredit > 0) ...[
                              Text(t.balanceAdvance),
                              Text(
                                fmt.money(ledger.advanceCredit),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(color: scheme.tertiary),
                              ),
                            ] else
                              Text(t.allPaid, style: Theme.of(context).textTheme.headlineSmall),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (canPay)
                      FilledButton.icon(
                        onPressed: () => context.push('${RouteNames.tenants}/$tenantId/pay'),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(t.recordPayment),
                      ),
                    if (canCharge) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => context.push('${RouteNames.tenants}/$tenantId/charge'),
                        icon: const Icon(Icons.add),
                        label: Text(t.addCharge),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(t.monthByMonth, style: Theme.of(context).textTheme.titleMedium),
                    for (final m in ledger.months.reversed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(fmt.monthLabel(m.month)),
                        subtitle: Text(t.paidOf(fmt.money(m.paid), fmt.money(m.charged))),
                        trailing: m.remaining > 0
                            ? Text(
                                fmt.money(m.remaining),
                                style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold),
                              )
                            : Icon(Icons.check_circle, color: scheme.tertiary),
                      ),
                    const SizedBox(height: 24),
                    Text(t.extraChargesTitle, style: Theme.of(context).textTheme.titleMedium),
                    if (s.charges.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(t.noExtraCharges),
                      ),
                    for (final c in s.charges)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          c.label == null || c.label!.isEmpty
                              ? t.chargeName(c.kind.name)
                              : '${t.chargeName(c.kind.name)}: ${c.label}',
                        ),
                        subtitle: Text(fmt.monthLabel(c.month)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(fmt.money(c.amount)),
                            if (canDelete)
                              IconButton(
                                tooltip: t.removeCharge,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => removeChargeFlow(context, ref, c),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(t.paymentsTitle, style: Theme.of(context).textTheme.titleMedium),
                    if (s.payments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(t.noPaymentsForTenant),
                      ),
                    for (final p in s.payments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.receiptNo),
                        subtitle: Text('${t.methodName(p.method.name)} · ${fmt.date(p.paidAt.toLocal())}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(fmt.money(p.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'share':
                                    openReceipt(context, ref, p.id);
                                  case 'wa':
                                    sendReceiptOnWhatsApp(context, ref, p.id);
                                  case 'print':
                                    openReceipt(context, ref, p.id, print: true);
                                  case 'edit':
                                    editPaymentFlow(context, ref, p);
                                  case 'void':
                                    voidPaymentFlow(context, ref, p);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'share', child: Text(t.shareReceipt)),
                                PopupMenuItem(value: 'wa', child: Text(t.sendWhatsApp)),
                                PopupMenuItem(value: 'print', child: Text(t.printReceipt)),
                                if (canEditPayment)
                                  PopupMenuItem(value: 'edit', child: Text(t.editPayment)),
                                if (canDelete) PopupMenuItem(value: 'void', child: Text(t.voidPayment)),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
