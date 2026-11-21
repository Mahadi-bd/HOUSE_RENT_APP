import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/security/confirm_action_dialog.dart';
import 'package:rent_solution/shared/widgets/fields_dialog.dart';

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<String?> _askReason(BuildContext context, String title, {String? message}) async {
  final t = AppLocalizations.of(context);
  final values = await showDialog<List<String>>(
    context: context,
    builder: (_) => FieldsDialog(
      title: title,
      message: message,
      labels: [t.reasonLabel],
      confirmLabel: t.save,
      cancelLabel: t.cancel,
    ),
  );
  if (values == null || !context.mounted) {
    return null;
  }
  if (values.first.trim().isEmpty) {
    _snack(context, t.errorReasonRequired);
    return null;
  }
  return values.first.trim();
}

Future<void> _run(BuildContext context, WidgetRef ref, String doneText, Future<void> Function() body) async {
  try {
    await body();
    ref.read(dataRevisionProvider.notifier).bump();
    if (context.mounted) {
      _snack(context, doneText);
    }
  } on Object catch (e) {
    if (context.mounted) {
      _snack(context, friendlyError(AppLocalizations.of(context), e));
    }
  }
}

/// Cancel a payment: reason, email confirmation, then the change.
Future<void> voidPaymentFlow(BuildContext context, WidgetRef ref, Payment payment) async {
  final t = AppLocalizations.of(context);
  final reason = await _askReason(context, t.voidPayment);
  if (reason == null || !context.mounted) {
    return;
  }
  final token = await confirmSensitiveAction(
    context,
    ref,
    action: SensitiveAction.paymentVoid,
    entityId: payment.id,
  );
  if (token == null || !context.mounted) {
    return;
  }
  final repo = await ref.read(paymentsRepositoryProvider.future);
  if (!context.mounted) {
    return;
  }
  await _run(
    context,
    ref,
    t.paymentCancelled,
    () => repo.voidPayment(payment.id, reason: reason, confirmation: token),
  );
}

/// Correct the amount or note of a payment.
Future<void> editPaymentFlow(BuildContext context, WidgetRef ref, Payment payment) async {
  final t = AppLocalizations.of(context);
  final values = await showDialog<List<String>>(
    context: context,
    builder: (_) => FieldsDialog(
      title: t.editPayment,
      labels: [t.amountLabel, t.noteLabel],
      keyboards: const [TextInputType.numberWithOptions(decimal: true), TextInputType.text],
      initial: [poishaToPlainTaka(payment.amount), payment.note ?? ''],
      confirmLabel: t.save,
      cancelLabel: t.cancel,
    ),
  );
  if (values == null || !context.mounted) {
    return;
  }
  final amount = parseTakaToPoisha(values[0]);
  if (amount == null) {
    _snack(context, t.errorInvalidAmount);
    return;
  }
  final token = await confirmSensitiveAction(
    context,
    ref,
    action: SensitiveAction.paymentEdit,
    entityId: payment.id,
  );
  if (token == null || !context.mounted) {
    return;
  }
  final repo = await ref.read(paymentsRepositoryProvider.future);
  if (!context.mounted) {
    return;
  }
  await _run(
    context,
    ref,
    t.paymentCorrected,
    () => repo.editPayment(
      payment.id,
      confirmation: token,
      amount: amount,
      note: values[1].trim().isEmpty ? null : values[1].trim(),
    ),
  );
}

/// Remove an extra charge.
Future<void> removeChargeFlow(BuildContext context, WidgetRef ref, ExtraCharge charge) async {
  final t = AppLocalizations.of(context);
  final reason = await _askReason(context, t.removeCharge);
  if (reason == null || !context.mounted) {
    return;
  }
  final token = await confirmSensitiveAction(
    context,
    ref,
    action: SensitiveAction.chargeVoid,
    entityId: charge.id,
  );
  if (token == null || !context.mounted) {
    return;
  }
  final repo = await ref.read(chargesRepositoryProvider.future);
  if (!context.mounted) {
    return;
  }
  await _run(
    context,
    ref,
    t.chargeRemoved,
    () => repo.voidCharge(charge.id, reason: reason, confirmation: token),
  );
}

/// Remove an expense.
Future<void> removeExpenseFlow(BuildContext context, WidgetRef ref, Expense expense) async {
  final t = AppLocalizations.of(context);
  final reason = await _askReason(context, t.removeExpense);
  if (reason == null || !context.mounted) {
    return;
  }
  final token = await confirmSensitiveAction(
    context,
    ref,
    action: SensitiveAction.expenseVoid,
    entityId: expense.id,
  );
  if (token == null || !context.mounted) {
    return;
  }
  final repo = await ref.read(expensesRepositoryProvider.future);
  if (!context.mounted) {
    return;
  }
  await _run(
    context,
    ref,
    t.expenseRemoved,
    () => repo.voidExpense(expense.id, reason: reason, confirmation: token),
  );
}

/// Move a tenant out. Returns true when it happened.
Future<bool> moveTenantOutFlow(BuildContext context, WidgetRef ref, Tenant tenant) async {
  final t = AppLocalizations.of(context);
  final reason = await _askReason(context, t.moveTenantOut, message: t.moveOutHint);
  if (reason == null || !context.mounted) {
    return false;
  }
  final token = await confirmSensitiveAction(
    context,
    ref,
    action: SensitiveAction.tenantDelete,
    entityId: tenant.id,
  );
  if (token == null || !context.mounted) {
    return false;
  }
  final repo = await ref.read(tenantsRepositoryProvider.future);
  if (!context.mounted) {
    return false;
  }
  var done = false;
  await _run(context, ref, t.tenantMovedOut, () async {
    await repo.softDelete(tenant.id, confirmation: token);
    done = true;
  });
  return done;
}

/// Remove a household member (archived for 2 years).
Future<void> removeHouseholdFlow(BuildContext context, WidgetRef ref, HouseholdMember member) async {
  final t = AppLocalizations.of(context);
  final reason = await _askReason(context, t.removeMember);
  if (reason == null || !context.mounted) {
    return;
  }
  final token = await confirmSensitiveAction(
    context,
    ref,
    action: SensitiveAction.householdRemove,
    entityId: member.id,
  );
  if (token == null || !context.mounted) {
    return;
  }
  final repo = await ref.read(householdRepositoryProvider.future);
  if (!context.mounted) {
    return;
  }
  await _run(
    context,
    ref,
    t.memberRemoved,
    () => repo.removeMember(member.id, reason: reason, confirmation: token),
  );
}

/// Remove a stored document.
Future<void> removeDocumentFlow(BuildContext context, WidgetRef ref, String documentId) async {
  final t = AppLocalizations.of(context);
  final reason = await _askReason(context, t.removeDocument);
  if (reason == null || !context.mounted) {
    return;
  }
  final token = await confirmSensitiveAction(
    context,
    ref,
    action: SensitiveAction.documentRemove,
    entityId: documentId,
  );
  if (token == null || !context.mounted) {
    return;
  }
  final repo = await ref.read(documentsRepositoryProvider.future);
  if (!context.mounted) {
    return;
  }
  await _run(
    context,
    ref,
    t.documentRemoved,
    () => repo.remove(documentId, reason: reason, confirmation: token),
  );
}
