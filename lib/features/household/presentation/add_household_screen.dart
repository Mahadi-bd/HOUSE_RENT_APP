import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';

/// Label of a household type.
String householdTypeLabel(AppLocalizations t, HouseholdType type) {
  switch (type) {
    case HouseholdType.family:
      return t.typeFamily;
    case HouseholdType.domesticWorker:
      return t.typeDomesticWorker;
    case HouseholdType.driver:
      return t.typeDriver;
    case HouseholdType.guard:
      return t.typeGuard;
    case HouseholdType.other:
      return t.typeOther;
  }
}

/// Add a person who lives with or works for the tenant.
class AddHouseholdScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AddHouseholdScreen({required this.tenantId, super.key});

  /// The tenant.
  final String tenantId;

  @override
  ConsumerState<AddHouseholdScreen> createState() => _AddHouseholdScreenState();
}

class _AddHouseholdScreenState extends ConsumerState<AddHouseholdScreen> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _age = TextEditingController();
  final _phone = TextEditingController();
  final _idNo = TextEditingController();
  final _type = ValueNotifier<HouseholdType>(HouseholdType.family);
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);

  @override
  void dispose() {
    for (final c in [_name, _relation, _age, _phone, _idNo]) {
      c.dispose();
    }
    _type.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      _error.value = t.errorRequired;
      return;
    }
    final ageText = _age.text.trim();
    final age = ageText.isEmpty ? null : int.tryParse(ageText);
    if (ageText.isNotEmpty && (age == null || age < 0 || age > 120)) {
      _error.value = t.errorNeedAge;
      return;
    }
    _busy.value = true;
    _error.value = null;
    try {
      final repo = await ref.read(householdRepositoryProvider.future);
      await repo.addMember(
        tenantId: widget.tenantId,
        type: _type.value,
        name: _name.text,
        relation: _relation.text,
        age: age,
        phone: _phone.text,
        idNo: _idNo.text,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.memberSaved)));
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
    final canVault = ref.watch(memberAccessProvider).dataOrNull?.can(Permission.tenantSensitiveWrite) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(t.addMember)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownMenu<HouseholdType>(
            label: Text(t.memberType),
            initialSelection: _type.value,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              for (final h in HouseholdType.values) DropdownMenuEntry(value: h, label: householdTypeLabel(t, h)),
            ],
            onSelected: (v) {
              if (v != null) {
                _type.value = v;
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: InputDecoration(labelText: t.tenantName)),
          const SizedBox(height: 12),
          TextField(controller: _relation, decoration: InputDecoration(labelText: t.relationLabel)),
          const SizedBox(height: 12),
          TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t.ageLabel),
          ),
          const SizedBox(height: 12),
          if (canVault) ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t.memberPhoneLabel),
            ),
            const SizedBox(height: 12),
            TextField(controller: _idNo, decoration: InputDecoration(labelText: t.memberIdLabel)),
          ] else
            Text(t.vaultOnlyField, style: Theme.of(context).textTheme.bodySmall),
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
                  : Text(t.save),
            ),
          ),
        ],
      ),
    );
  }
}
