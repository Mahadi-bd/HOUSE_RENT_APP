import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/core/utils/money_input.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/payments_repository.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/ocr/data/tesseract_ocr_engine.dart';
import 'package:rent_solution/features/ocr/domain/ocr_parsers.dart';
import 'package:rent_solution/features/payments/presentation/receipt_actions.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';

/// Record a payment from a tenant. Shows what is still owed and a receipt number when saved.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  /// Creates the screen for [tenantId].
  const RecordPaymentScreen({required this.tenantId, super.key});

  /// The paying tenant.
  final String tenantId;

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  static const _mobileMoney = {PaymentMethod.bkash, PaymentMethod.nagad, PaymentMethod.rocket};

  final _amount = TextEditingController();
  final _trx = TextEditingController();
  final _note = TextEditingController();
  final _method = ValueNotifier<PaymentMethod>(PaymentMethod.cash);
  final _type = ValueNotifier<PaymentType>(PaymentType.rent);
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _amount.dispose();
    _trx.dispose();
    _note.dispose();
    _method.dispose();
    _type.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _scanScreenshot() async {
    final t = AppLocalizations.of(context);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 90);
      if (picked == null) {
        return;
      }
      final text = await ref.read(ocrEngineProvider).recognize(await picked.readAsBytes(), languages: const ['eng']);
      final scan = parseMobileMoneyText(text);
      if (scan.amountPoisha != null) {
        _amount.text = poishaToPlainTaka(scan.amountPoisha!);
      }
      if (scan.trxId != null) {
        _trx.text = scan.trxId!;
      }
      if (scan.method != null) {
        _method.value = scan.method!;
      }
      if (mounted) {
        // The person still checks every value before pressing Save.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.ocrCheckValues)));
      }
    } on Object catch (e) {
      if (mounted) {
        _error.value = friendlyError(AppLocalizations.of(context), e);
      }
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final amount = parseTakaToPoisha(_amount.text);
    if (amount == null) {
      _error.value = t.errorInvalidAmount;
      return;
    }
    final needsTrx = _mobileMoney.contains(_method.value);
    if (needsTrx && _trx.text.trim().isEmpty) {
      _error.value = t.errorTrxRequired;
      return;
    }
    _busy.value = true;
    _error.value = null;
    try {
      final repo = await ref.read(paymentsRepositoryProvider.future);
      final receipt = await repo.record(
        tenantId: widget.tenantId,
        amount: amount,
        method: _method.value,
        type: _type.value,
        trxId: needsTrx ? _trx.text : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) {
        return;
      }
      await _showReceipt(receipt);
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

  Future<void> _showReceipt(PaymentReceipt receipt) {
    final t = AppLocalizations.of(context);
    final fmt = context.fmt;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.paymentSavedTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.receiptNumber(receipt.receiptNo)),
            const SizedBox(height: 8),
            Text(fmt.money(receipt.amount), style: Theme.of(dialogContext).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (receipt.outstandingAfter > 0)
              Text(t.remainingAfter(fmt.money(receipt.outstandingAfter))),
            if (receipt.advanceCredit > 0) Text(t.advanceAfter(fmt.money(receipt.advanceCredit))),
            if (receipt.outstandingAfter == 0 && receipt.advanceCredit == 0) Text(t.allPaid),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => openReceipt(context, ref, receipt.paymentId),
            child: Text(t.shareReceipt),
          ),
          TextButton(
            onPressed: () => sendReceiptOnWhatsApp(context, ref, receipt.paymentId),
            child: Text(t.sendWhatsApp),
          ),
          TextButton(
            onPressed: () => openReceipt(context, ref, receipt.paymentId, print: true),
            child: Text(t.printReceipt),
          ),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(t.done)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final fmt = context.fmt;
    final statement = ref.watch(tenantStatementProvider(widget.tenantId));
    final tenant = ref.watch(tenantProvider(widget.tenantId));
    return Scaffold(
      appBar: AppBar(title: Text(t.recordPayment)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tenant.dataOrNull?.name ?? '', style: Theme.of(context).textTheme.titleLarge),
          statement.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                s.ledger.outstanding > 0
                    ? '${t.balanceDue}: ${fmt.money(s.ledger.outstanding)}'
                    : s.ledger.advanceCredit > 0
                        ? '${t.balanceAdvance}: ${fmt.money(s.ledger.advanceCredit)}'
                        : t.allPaid,
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _scanScreenshot,
            icon: const Icon(Icons.document_scanner_outlined),
            label: Text(t.scanPayment),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t.amountLabel),
          ),
          const SizedBox(height: 12),
          DropdownMenu<PaymentType>(
            label: Text(t.payTypeLabel),
            initialSelection: _type.value,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              DropdownMenuEntry(value: PaymentType.rent, label: t.payTypeRent),
              DropdownMenuEntry(value: PaymentType.utility, label: t.payTypeUtility),
              DropdownMenuEntry(value: PaymentType.lateFee, label: t.payTypeFine),
              DropdownMenuEntry(value: PaymentType.deposit, label: t.payTypeDeposit),
            ],
            onSelected: (v) {
              if (v != null) {
                _type.value = v;
              }
            },
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<PaymentMethod>(
            valueListenable: _method,
            builder: (context, method, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownMenu<PaymentMethod>(
                  label: Text(t.methodLabel),
                  initialSelection: method,
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final m in PaymentMethod.values)
                      DropdownMenuEntry(value: m, label: t.methodName(m.name)),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      _method.value = value;
                    }
                  },
                ),
                if (_mobileMoney.contains(method)) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _trx, decoration: InputDecoration(labelText: t.trxIdLabel)),
                ],
              ],
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
                  : Text(t.savePayment),
            ),
          ),
        ],
      ),
    );
  }
}
