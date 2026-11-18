import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/fields_dialog.dart';
import 'package:rent_solution/shared/widgets/empty_state.dart';

/// Properties with all their units visible at once (no hidden sections).
class PropertiesScreen extends ConsumerWidget {
  /// Creates the screen.
  const PropertiesScreen({super.key});

  Future<void> _addProperty(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => FieldsDialog(
        title: t.addProperty,
        labels: [t.propertyName, t.propertyAddress],
        keyboards: const [TextInputType.text, TextInputType.streetAddress],
        confirmLabel: t.save,
        cancelLabel: t.cancel,
      ),
    );
    if (values == null || !context.mounted) {
      return;
    }
    if (values[0].trim().isEmpty || values[1].trim().isEmpty) {
      _snack(context, t.errorRequired);
      return;
    }
    try {
      final repo = await ref.read(propertiesRepositoryProvider.future);
      await repo.createProperty(name: values[0], address: values[1]);
      ref.read(dataRevisionProvider.notifier).bump();
    } on Object catch (e) {
      if (context.mounted) {
        _snack(context, friendlyError(AppLocalizations.of(context), e));
      }
    }
  }

  Future<void> _addUnit(BuildContext context, WidgetRef ref, Property property) async {
    final t = AppLocalizations.of(context);
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => FieldsDialog(
        title: '${t.addUnit}: ${property.name}',
        labels: [t.unitNumber, t.unitRent],
        keyboards: const [TextInputType.text, TextInputType.numberWithOptions(decimal: true)],
        confirmLabel: t.save,
        cancelLabel: t.cancel,
      ),
    );
    if (values == null || !context.mounted) {
      return;
    }
    final rent = parseTakaToPoisha(values[1]);
    if (values[0].trim().isEmpty) {
      _snack(context, t.errorRequired);
      return;
    }
    if (rent == null) {
      _snack(context, t.errorInvalidAmount);
      return;
    }
    try {
      final repo = await ref.read(propertiesRepositoryProvider.future);
      await repo.createUnit(propertyId: property.id, unitNo: values[0], rentAmount: rent);
      ref.read(dataRevisionProvider.notifier).bump();
    } on Object catch (e) {
      if (context.mounted) {
        _snack(context, friendlyError(AppLocalizations.of(context), e));
      }
    }
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final canWrite =
        ref.watch(memberAccessProvider).dataOrNull?.can(Permission.propertyWrite) ?? false;
    final properties = ref.watch(propertiesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.propertiesTitle)),
      floatingActionButton: canWrite && (properties.dataOrNull?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => _addProperty(context, ref),
              icon: const Icon(Icons.add_home_outlined),
              label: Text(t.addProperty),
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
              actionLabel: canWrite ? t.addProperty : null,
              onAction: canWrite ? () => _addProperty(context, ref) : null,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final property = list[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(property.name, style: Theme.of(context).textTheme.titleLarge),
                      Text(property.address),
                      const SizedBox(height: 12),
                      _UnitsWrap(propertyId: property.id),
                      if (canWrite) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _addUnit(context, ref, property),
                          icon: const Icon(Icons.add),
                          label: Text(t.addUnit),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _UnitsWrap extends ConsumerWidget {
  const _UnitsWrap({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(unitsOfProvider(propertyId));
    return units.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(friendlyError(t, e)),
      data: (list) {
        if (list.isEmpty) {
          return Text(t.noUnitsYet);
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final u in list)
              Chip(
                label: Text('${t.unitLabel(u.unitNo)} · ${_status(t, u.status)} · ${context.fmt.money(u.rentAmount)}'),
              ),
          ],
        );
      },
    );
  }

  String _status(AppLocalizations t, UnitStatus status) {
    switch (status) {
      case UnitStatus.vacant:
        return t.unitVacant;
      case UnitStatus.occupied:
        return t.unitOccupied;
      case UnitStatus.maintenance:
        return t.unitMaintenance;
    }
  }
}
