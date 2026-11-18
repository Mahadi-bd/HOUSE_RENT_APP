import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/security/sensitive_actions.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/empty_state.dart';

/// The expense ledger: pick a property and a month, see the total and every expense.
class ExpensesScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final _propertyId = ValueNotifier<String?>(null);
  final _month = ValueNotifier<String>(monthKeyOf(DateTime.now()));

  @override
  void dispose() {
    _propertyId.dispose();
    _month.dispose();
    super.dispose();
  }

  /// This month and the 11 before it.
  List<String> _months() {
    final now = DateTime.now().toUtc().add(bangladeshOffset);
    return [
      for (var back = 0; back < 12; back++) monthKeyOf(DateTime.utc(now.year, now.month - back, 15)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canAdd = ref.watch(memberAccessProvider).dataOrNull?.can(Permission.expenseCreate) ?? false;
    final canDelete = ref.watch(memberAccessProvider).dataOrNull?.can(Permission.deleteAny) ?? false;
    final properties = ref.watch(propertiesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.expensesTitle)),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () {
                final id = _propertyId.value ?? properties.dataOrNull?.firstOrNull?.id;
                if (id != null) {
                  context.push('${RouteNames.expenses}/new/$id');
                }
              },
              icon: const Icon(Icons.add),
              label: Text(t.addExpense),
            )
          : null,
      body: properties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.home_work_outlined,
              title: t.noPropertiesTitle,
              message: t.noPropertiesMessage,
            );
          }
          return ValueListenableBuilder<String?>(
            valueListenable: _propertyId,
            builder: (context, selected, _) {
              final propertyId = selected ?? list.first.id;
              return ValueListenableBuilder<String>(
                valueListenable: _month,
                builder: (context, month, _) => _Body(
                  properties: list,
                  propertyId: propertyId,
                  month: month,
                  months: _months(),
                  canDelete: canDelete,
                  onProperty: (id) => _propertyId.value = id,
                  onMonth: (m) => _month.value = m,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.properties,
    required this.propertyId,
    required this.month,
    required this.months,
    required this.canDelete,
    required this.onProperty,
    required this.onMonth,
  });

  final List<Property> properties;
  final String propertyId;
  final String month;
  final List<String> months;
  final bool canDelete;
  final ValueChanged<String> onProperty;
  final ValueChanged<String> onMonth;

  String _category(AppLocalizations t, String name) {
    switch (name) {
      case 'repair':
        return t.catRepair;
      case 'tax':
        return t.catTax;
      case 'commission':
        return t.catCommission;
      case 'utility':
        return t.catUtility;
      case 'salary':
        return t.catSalary;
      default:
        return t.catOther;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final fmt = context.fmt;
    final expenses = ref.watch(expensesProvider((propertyId: propertyId, month: month)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownMenu<String>(
          label: Text(t.propertyLabel),
          initialSelection: propertyId,
          expandedInsets: EdgeInsets.zero,
          dropdownMenuEntries: [for (final p in properties) DropdownMenuEntry(value: p.id, label: p.name)],
          onSelected: (id) {
            if (id != null) {
              onProperty(id);
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownMenu<String>(
          label: Text(t.monthFilterLabel),
          initialSelection: month,
          expandedInsets: EdgeInsets.zero,
          dropdownMenuEntries: [for (final m in months) DropdownMenuEntry(value: m, label: fmt.monthLabel(m))],
          onSelected: (m) {
            if (m != null) {
              onMonth(m);
            }
          },
        ),
        const SizedBox(height: 16),
        expenses.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(friendlyError(t, e)),
          data: (rows) {
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Text(t.noExpensesTitle, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(t.noExpensesMessage, textAlign: TextAlign.center),
                  ],
                ),
              );
            }
            final total = rows.fold<int>(0, (sum, e) => sum + e.amount);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.monthTotal(fmt.money(total)),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                for (final e in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_category(t, e.category.name)),
                    subtitle: Text(
                      '${fmt.date(e.spentOn.toLocal())}${e.note == null ? '' : ' · ${e.note}'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(fmt.money(e.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (canDelete)
                          IconButton(
                            tooltip: t.removeExpense,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => removeExpenseFlow(context, ref, e),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
