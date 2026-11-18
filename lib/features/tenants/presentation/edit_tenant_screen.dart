import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';

/// Edit a tenant. Rent can change only before any payment exists.
class EditTenantScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const EditTenantScreen({required this.tenantId, super.key});

  /// The tenant to edit.
  final String tenantId;

  @override
  ConsumerState<EditTenantScreen> createState() => _EditTenantScreenState();
}

class _EditTenantScreenState extends ConsumerState<EditTenantScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _rent = TextEditingController();
  final _service = TextEditingController();
  final _leaseEnd = ValueNotifier<DateTime?>(null);
  final _rentLocked = ValueNotifier<bool>(true);
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _rent, _service]) {
      c.dispose();
    }
    _leaseEnd.dispose();
    _rentLocked.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _load(Tenant tenant) async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    _name.text = tenant.name;
    _phone.text = tenant.phone;
    _email.text = tenant.email ?? '';
    _rent.text = poishaToPlainTaka(tenant.monthlyRent);
    _service.text = poishaToPlainTaka(tenant.serviceCharge);
    _leaseEnd.value = tenant.leaseEnd;
    final repo = await ref.read(tenantsRepositoryProvider.future);
    final editable = await repo.canEditRent(tenant.id);
    if (mounted) {
      _rentLocked.value = !editable;
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _leaseEnd.value ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _leaseEnd.value = DateTime.utc(picked.year, picked.month, picked.day);
    }
  }

  Future<void> _save(Tenant tenant) async {
    final t = AppLocalizations.of(context);
    final rent = parseTakaToPoisha(_rent.text);
    final service = _service.text.trim().isEmpty ? 0 : parseTakaToPoisha(_service.text, allowZero: true);
    if (_name.text.trim().isEmpty) {
      _error.value = t.errorRequired;
      return;
    }
    if (!RegExp(r'^\d{10,15}$').hasMatch(_phone.text.replaceAll(RegExp(r'[\s\-+()]'), ''))) {
      _error.value = t.errorPhone;
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
      await repo.update(
        tenant.id,
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        leaseEnd: _leaseEnd.value,
        clearLeaseEnd: _leaseEnd.value == null && tenant.leaseEnd != null,
        monthlyRent: _rentLocked.value ? null : rent,
        serviceCharge: _rentLocked.value ? null : service,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.tenantSaved)));
        context.pop();
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
    final tenant = ref.watch(tenantProvider(widget.tenantId));
    return Scaffold(
      appBar: AppBar(title: Text(t.editTenant)),
      body: tenant.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (row) {
          _load(row);
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
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t.emailLabel),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                valueListenable: _rentLocked,
                builder: (context, locked, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _rent,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: t.monthlyRentLabel),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _service,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: t.serviceChargeLabel),
                    ),
                    if (locked) ...[
                      const SizedBox(height: 8),
                      Text(t.rentLockedHint, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<DateTime?>(
                valueListenable: _leaseEnd,
                builder: (context, end, _) => Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickEnd,
                        icon: const Icon(Icons.event_busy_outlined),
                        label: Text('${t.leaseEndLabel}: ${end == null ? '-' : context.fmt.date(end)}'),
                      ),
                    ),
                    if (end != null)
                      IconButton(
                        tooltip: t.clearDate,
                        icon: const Icon(Icons.clear),
                        onPressed: () => _leaseEnd.value = null,
                      ),
                  ],
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
                  onPressed: busy ? null : () => _save(row),
                  child: busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.save),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
