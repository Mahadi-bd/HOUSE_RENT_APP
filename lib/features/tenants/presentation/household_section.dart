import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/security/sensitive_actions.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';

String _typeLabel(AppLocalizations t, HouseholdType type) {
  switch (type) {
    case HouseholdType.family:
      return t.memberTypeFamily;
    case HouseholdType.domesticWorker:
      return t.memberTypeDomesticWorker;
    case HouseholdType.driver:
      return t.memberTypeDriver;
    case HouseholdType.guard:
      return t.memberTypeGuard;
    case HouseholdType.other:
      return t.memberTypeOther;
  }
}

/// Everyone living with or working for the tenant. Staff see names, relations and ages
/// (basic data for security); phone and ID number are private.
class HouseholdSection extends ConsumerWidget {
  /// Creates the section.
  const HouseholdSection({required this.tenantId, super.key});

  /// The tenant.
  final String tenantId;

  Future<void> _add(BuildContext context, WidgetRef ref, {required bool withVault}) async {
    final t = AppLocalizations.of(context);
    final result = await showDialog<_NewMember>(
      context: context,
      builder: (_) => _AddMemberDialog(withVault: withVault),
    );
    if (result == null || !context.mounted) {
      return;
    }
    try {
      final repo = await ref.read(householdRepositoryProvider.future);
      await repo.addMember(
        tenantId: tenantId,
        type: result.type,
        name: result.name,
        relation: result.relation,
        age: int.tryParse(result.age.trim()),
        note: result.note,
        phone: result.phone,
        idNo: result.idNo,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.memberAdded)));
      }
    } on Object catch (e) {
      if (context.mounted) {
        final message = e is ArgumentError ? t.errorPersonInvalid : friendlyError(t, e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final canAdd = access?.can(Permission.tenantWrite) ?? false;
    final withVault = access?.can(Permission.tenantSensitiveWrite) ?? false;
    final canRemove = access?.can(Permission.deleteAny) ?? false;
    final members = ref.watch(householdProvider(tenantId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.householdTitle, style: Theme.of(context).textTheme.titleMedium),
        members.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(friendlyError(t, e)),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(t.memberCount('${list.length + 1}')),
              ),
              if (list.isEmpty) Text(t.noHousehold),
              for (final m in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.name),
                  subtitle: Text(
                    [
                      _typeLabel(t, m.type),
                      if (m.relation != null) m.relation!,
                      if (m.age != null) '${m.age}',
                    ].join(' · '),
                  ),
                  trailing: canRemove
                      ? IconButton(
                          tooltip: t.removeMember,
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => removeHouseholdFlow(context, ref, m),
                        )
                      : null,
                ),
            ],
          ),
        ),
        if (canAdd)
          OutlinedButton.icon(
            onPressed: () => _add(context, ref, withVault: withVault),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(t.addMember),
          ),
      ],
    );
  }
}

class _NewMember {
  const _NewMember({
    required this.type,
    required this.name,
    required this.relation,
    required this.age,
    required this.note,
    required this.phone,
    required this.idNo,
  });

  final HouseholdType type;
  final String name;
  final String relation;
  final String age;
  final String note;
  final String phone;
  final String idNo;
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.withVault});

  final bool withVault;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _age = TextEditingController();
  final _note = TextEditingController();
  final _phone = TextEditingController();
  final _id = TextEditingController();
  final _type = ValueNotifier<HouseholdType>(HouseholdType.family);

  @override
  void dispose() {
    for (final c in [_name, _relation, _age, _note, _phone, _id]) {
      c.dispose();
    }
    _type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.addMember),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<HouseholdType>(
              label: Text(t.memberTypeLabel),
              initialSelection: _type.value,
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final v in HouseholdType.values) DropdownMenuEntry(value: v, label: _typeLabel(t, v)),
              ],
              onSelected: (v) {
                if (v != null) {
                  _type.value = v;
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: t.memberName)),
            const SizedBox(height: 12),
            TextField(controller: _relation, decoration: InputDecoration(labelText: t.memberRelation)),
            const SizedBox(height: 12),
            TextField(
              controller: _age,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t.memberAge),
            ),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: InputDecoration(labelText: t.memberNote)),
            if (widget.withVault) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.memberPhoneVault),
              ),
              const SizedBox(height: 12),
              TextField(controller: _id, decoration: InputDecoration(labelText: t.memberIdVault)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _NewMember(
              type: _type.value,
              name: _name.text,
              relation: _relation.text,
              age: _age.text,
              note: _note.text,
              phone: _phone.text,
              idNo: _id.text,
            ),
          ),
          child: Text(t.save),
        ),
      ],
    );
  }
}
