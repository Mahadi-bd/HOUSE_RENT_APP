import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';

/// Add an optional extra charge (electricity, gas, water, internet, fine, damage, other).
class AddChargeScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [tenantId].
  const AddChargeScreen({required this.tenantId, super.key});

  /// The tenant being charged.
  final String tenantId;

  @override
  ConsumerState<AddChargeScreen> createState() => _AddChargeScreenState();
}

class _AddChargeScreenState extends ConsumerState<AddChargeScreen> {
  final _amount = TextEditingController();
  final _label = TextEditingController();
  final _kind = ValueNotifier<ChargeKind>(ChargeKind.electricity);
  final _month = ValueNotifier<String>(monthKeyOf(DateTime.now()));
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    _kind.dispose();
    _month.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  /// Two months back to one month ahead of today (Bangladesh time).
  List<String> _monthChoices() {
    final now = DateTime.now().toUtc().add(bangladeshOffset);
    return [
      for (var offset = -2; offset <= 1; offset++)
        monthKeyOf(DateTime.utc(now.year, now.month + offset, 15)),
    ];
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final amount = parseTakaToPoisha(_amount.text);
    if (amount == null) {
      _error.value = t.errorInvalidAmount;
      return;
    }
    if (_kind.value == ChargeKind.other && _label.text.trim().isEmpty) {
      _error.value = t.errorRequired;
      return;
    }
    _busy.value = true;
    _error.value = null;
    try {
      final repo = await ref.read(chargesRepositoryProvider.future);
      await repo.addCharge(
        tenantId: widget.tenantId,
        month: _month.value,
        kind: _kind.value,
        amount: amount,
        label: _label.text.trim().isEmpty ? null : _label.text.trim(),
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
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
      appBar: AppBar(title: Text(t.addCharge)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tenant.dataOrNull?.name ?? '', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(t.chargeOptionalHint),
          const SizedBox(height: 16),
          DropdownMenu<ChargeKind>(
            label: Text(t.chargeKindLabel),
            initialSelection: _kind.value,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              for (final k in ChargeKind.values) DropdownMenuEntry(value: k, label: t.chargeName(k.name)),
            ],
            onSelected: (value) {
              if (value != null) {
                _kind.value = value;
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            label: Text(t.chargeMonthLabel),
            initialSelection: _month.value,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              for (final m in _monthChoices()) DropdownMenuEntry(value: m, label: context.fmt.monthLabel(m)),
            ],
            onSelected: (value) {
              if (value != null) {
                _month.value = value;
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t.amountLabel),
          ),
          const SizedBox(height: 12),
          TextField(controller: _label, decoration: InputDecoration(labelText: t.chargeLabelHint)),
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
                  : Text(t.saveCharge),
            ),
          ),
        ],
      ),
    );
  }
}
