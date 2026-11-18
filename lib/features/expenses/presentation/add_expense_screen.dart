import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';

/// Add an expense for one property. The amount is kept as integer poisha.
class AddExpenseScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [propertyId].
  const AddExpenseScreen({required this.propertyId, super.key});

  /// The property the expense belongs to.
  final String propertyId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _category = ValueNotifier<ExpenseCategory>(ExpenseCategory.repair);
  final _date = ValueNotifier<DateTime>(DateTime.now());
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _category.dispose();
    _date.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  String _label(AppLocalizations t, ExpenseCategory c) {
    switch (c) {
      case ExpenseCategory.repair:
        return t.catRepair;
      case ExpenseCategory.tax:
        return t.catTax;
      case ExpenseCategory.commission:
        return t.catCommission;
      case ExpenseCategory.utility:
        return t.catUtility;
      case ExpenseCategory.salary:
        return t.catSalary;
      case ExpenseCategory.other:
        return t.catOther;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _date.value = picked;
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final amount = parseTakaToPoisha(_amount.text);
    if (amount == null) {
      _error.value = t.errorInvalidAmount;
      return;
    }
    _busy.value = true;
    _error.value = null;
    try {
      final repo = await ref.read(expensesRepositoryProvider.future);
      final day = _date.value;
      // Noon in Bangladesh (06:00 UTC) so the date never slips into another month.
      await repo.record(
        propertyId: widget.propertyId,
        category: _category.value,
        amount: amount,
        spentOn: DateTime.utc(day.year, day.month, day.day, 6),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.expenseSaved)));
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
    return Scaffold(
      appBar: AppBar(title: Text(t.addExpense)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownMenu<ExpenseCategory>(
            label: Text(t.expenseCategoryLabel),
            initialSelection: _category.value,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              for (final c in ExpenseCategory.values) DropdownMenuEntry(value: c, label: _label(t, c)),
            ],
            onSelected: (c) {
              if (c != null) {
                _category.value = c;
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
          ValueListenableBuilder<DateTime>(
            valueListenable: _date,
            builder: (context, day, _) => OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('${t.spentOnLabel}: ${context.fmt.date(day)}'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: InputDecoration(labelText: t.noteLabel)),
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
                  : Text(t.saveExpense),
            ),
          ),
        ],
      ),
    );
  }
}
