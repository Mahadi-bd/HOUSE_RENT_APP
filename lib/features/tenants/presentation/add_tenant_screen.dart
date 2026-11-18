import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/repositories/properties_repository.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';

/// Add a tenant to a vacant unit.
class AddTenantScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AddTenantScreen({super.key});

  @override
  ConsumerState<AddTenantScreen> createState() => _AddTenantScreenState();
}

class _AddTenantScreenState extends ConsumerState<AddTenantScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _rent = TextEditingController();
  final _service = TextEditingController();
  final _unit = ValueNotifier<UnitChoice?>(null);
  final _start = ValueNotifier<DateTime>(DateTime.now());
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _rent.dispose();
    _service.dispose();
    _unit.dispose();
    _start.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _start.value = picked;
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final phone = _phone.text.replaceAll(RegExp(r'[\s\-+()]'), '');
    final rent = parseTakaToPoisha(_rent.text);
    final service = _service.text.trim().isEmpty ? 0 : parseTakaToPoisha(_service.text, allowZero: true);
    final unit = _unit.value;
    if (_name.text.trim().isEmpty) {
      _error.value = t.errorRequired;
      return;
    }
    if (!RegExp(r'^\d{10,15}$').hasMatch(phone)) {
      _error.value = t.errorPhone;
      return;
    }
    if (unit == null) {
      _error.value = t.errorPickUnit;
      return;
    }
    if (rent == null || service == null) {
      _error.value = t.errorInvalidAmount;
      return;
    }
    _busy.value = true;
    _error.value = null;
    try {
      final repo = await ref.read(tenantsRepositoryProvider.future);
      final day = _start.value;
      final id = await repo.create(
        name: _name.text,
        phone: phone,
        unitId: unit.unit.id,
        leaseStart: DateTime.utc(day.year, day.month, day.day),
        monthlyRent: rent,
        serviceCharge: service,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        context.pushReplacement('${RouteNames.tenants}/$id');
      }
    } on Object catch (e) {
      if (mounted) {
        _error.value = friendlyError(AppLocalizations.of(context), e);
      }
    } finally {
      if (mounted) {
        _busy.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(vacantUnitsProvider);
    final canAddProperty =
        ref.watch(memberAccessProvider).dataOrNull?.can(Permission.propertyWrite) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(t.addTenant)),
      body: units.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (choices) {
          if (choices.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(t.noVacantUnits, textAlign: TextAlign.center),
                  if (canAddProperty) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.push(RouteNames.properties),
                      child: Text(t.goToProperties),
                    ),
                  ],
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: t.tenantName)),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.phoneLabel),
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                label: Text(t.unitPickLabel),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final c in choices)
                    DropdownMenuEntry(
                      value: c.unit.id,
                      label: '${c.propertyName} ${c.unit.unitNo} · ${context.fmt.money(c.unit.rentAmount)}',
                    ),
                ],
                onSelected: (id) {
                  if (id == null) {
                    return;
                  }
                  final choice = choices.firstWhere((c) => c.unit.id == id);
                  _unit.value = choice;
                  _rent.text = poishaToPlainTaka(choice.unit.rentAmount);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rent,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t.monthlyRentLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _service,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t.serviceChargeLabel),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<DateTime>(
                valueListenable: _start,
                builder: (context, day, _) => OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('${t.leaseStartLabel}: ${context.fmt.date(day)}'),
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String?>(
                valueListenable: _error,
                builder: (context, message, _) => message == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _busy,
                builder: (context, busy, _) => FilledButton(
                  onPressed: busy ? null : _save,
                  child: busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.saveTenant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
