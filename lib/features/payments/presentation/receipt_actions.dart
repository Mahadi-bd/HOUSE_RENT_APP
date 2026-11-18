import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/utils/formatters.dart';
import 'package:rent_solution/core/utils/phone_utils.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/features/payments/application/receipt_service.dart';

/// Builds the receipt PDF of [paymentId] and opens the share sheet (or the print preview).
Future<void> openReceipt(
  BuildContext context,
  WidgetRef ref,
  String paymentId, {
  bool print = false,
}) async {
  final t = AppLocalizations.of(context);
  final language = Localizations.localeOf(context).languageCode;
  try {
    final file = await ReceiptService.build(ref, t, language, paymentId);
    if (print) {
      await ReceiptService.printIt(file);
    } else {
      await ReceiptService.share(file);
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.receiptFailed)));
    }
  }
}

/// Opens WhatsApp with the receipt summary typed in (the person taps Send; the PDF can be shared
/// separately from the receipt menu). Works with the tenant's saved number, or lets the person
/// pick the contact when the number is not valid.
Future<void> sendReceiptOnWhatsApp(BuildContext context, WidgetRef ref, String paymentId) async {
  final t = AppLocalizations.of(context);
  final language = Localizations.localeOf(context).languageCode;
  try {
    final payments = await ref.read(paymentsRepositoryProvider.future);
    final tenants = await ref.read(tenantsRepositoryProvider.future);
    final profiles = await ref.read(orgProfileRepositoryProvider.future);
    final payment = await payments.getPayment(paymentId);
    final tenant = await tenants.getById(payment.tenantId);
    final profile = await profiles.get();
    final fmt = AppFormatters(language);
    final text = t.waReceiptMessage(
      profile?.displayName ?? BrandConfig.companyName,
      fmt.money(payment.amount),
      fmt.monthLabel(payment.forMonth),
      payment.receiptNo,
    );
    final opened = await launchUrl(
      whatsAppUri(tenant.phone, text),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.whatsAppFailed)));
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.whatsAppFailed)));
    }
  }
}
