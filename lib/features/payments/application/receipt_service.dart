import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/date_utils.dart';
import 'package:rent_solution/core/utils/formatters.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';
import 'package:rent_solution/features/payments/domain/receipt_pdf.dart';

/// A finished receipt PDF and a good file name for it.
class ReceiptFile {
  /// Creates the file description.
  const ReceiptFile(this.bytes, this.fileName);

  /// PDF bytes.
  final Uint8List bytes;

  /// File name such as `receipt-R2611-9F3A-0007.pdf`.
  final String fileName;
}

/// Builds receipts with the business name, logo, address, phone and email, and shares or prints them.
class ReceiptService {
  const ReceiptService._();

  /// Bundled Bengali font files. Put them in `assets/fonts/` (see README). Without them the
  /// receipt uses English labels and "BDT", because the built-in PDF font cannot draw Bengali.
  static const regularFontAsset = 'assets/fonts/NotoSansBengali-Regular.ttf';
  static const boldFontAsset = 'assets/fonts/NotoSansBengali-Bold.ttf';

  static Future<pw.Font?> _font(String asset) async {
    try {
      return pw.Font.ttf(await rootBundle.load(asset));
    } on Object {
      return null;
    }
  }

  /// Builds the receipt of [paymentId] in the app language when the Bengali font is present,
  /// otherwise in English.
  static Future<ReceiptFile> build(
    WidgetRef ref,
    AppLocalizations t,
    String languageCode,
    String paymentId,
  ) async {
    final payments = await ref.read(paymentsRepositoryProvider.future);
    final tenants = await ref.read(tenantsRepositoryProvider.future);
    final properties = await ref.read(propertiesRepositoryProvider.future);
    final profiles = await ref.read(orgProfileRepositoryProvider.future);

    final payment = await payments.getPayment(paymentId);
    final tenant = await tenants.getById(payment.tenantId);
    final balance = await payments.balanceAfter(paymentId);
    final amended = await payments.wasAmended(paymentId);
    final unitLabel = (await properties.unitLabels())[payment.unitId] ?? '';
    final profile = await profiles.get();

    final regular = await _font(regularFontAsset);
    final bold = await _font(boldFontAsset);
    final localized = regular != null;
    final fmt = AppFormatters(localized ? languageCode : 'en');
    final labels = localized ? _localizedLabels(t) : ReceiptLabels.english;
    String money(int poisha) => localized ? fmt.money(poisha) : fmt.moneyCode(poisha);

    Uint8List? logo;
    final custom = profile?.logoPath;
    if (custom != null && File(custom).existsSync()) {
      logo = await File(custom).readAsBytes();
    } else {
      try {
        logo = (await rootBundle.load(BrandConfig.logoAsset)).buffer.asUint8List();
      } on Object {
        logo = null;
      }
    }

    final data = ReceiptData(
      orgName: profile?.displayName ?? BrandConfig.companyName,
      ownerName: profile?.ownerName,
      address: profile?.address,
      phone: profile?.phone,
      email: profile?.email,
      website: profile?.website,
      footer: profile?.receiptFooter,
      logoBytes: logo,
      receiptNo: payment.receiptNo,
      dateText: fmt.date(payment.paidAt.toLocal()),
      tenantName: tenant.name,
      unitLabel: unitLabel,
      forMonthText: fmt.monthLabel(payment.forMonth),
      methodText: localized ? t.methodName(payment.method.name) : _englishMethod(payment.method.name),
      trxId: payment.trxId,
      amountText: money(payment.amount),
      balanceText: balance.outstanding > 0 ? money(balance.outstanding) : null,
      advanceText: balance.advance > 0 ? money(balance.advance) : null,
      receivedBy: ref.read(authRepositoryProvider).currentUser?.displayName,
      amended: amended,
    );
    final bytes = await buildReceiptPdf(data, labels, regular: regular, bold: bold);
    return ReceiptFile(bytes, 'receipt-${payment.receiptNo}.pdf');
  }

  /// Opens the system share sheet (WhatsApp, email, Drive...) with the PDF.
  static Future<void> share(ReceiptFile file) =>
      Printing.sharePdf(bytes: file.bytes, filename: file.fileName);

  /// Opens the system print preview.
  static Future<void> printIt(ReceiptFile file) =>
      Printing.layoutPdf(onLayout: (_) async => file.bytes, name: file.fileName);

  static String _englishMethod(String name) {
    switch (name) {
      case 'bkash':
        return 'bKash';
      case 'nagad':
        return 'Nagad';
      case 'rocket':
        return 'Rocket';
      case 'bank':
        return 'Bank';
      case 'qr':
        return 'QR';
      default:
        return 'Cash';
    }
  }

  static ReceiptLabels _localizedLabels(AppLocalizations t) => ReceiptLabels(
        title: t.rcpTitle,
        receiptNo: t.rcpNo,
        date: t.rcpDate,
        receivedFrom: t.rcpReceivedFrom,
        unit: t.rcpUnit,
        forMonth: t.rcpForMonth,
        method: t.rcpMethod,
        transactionId: t.rcpTrx,
        amountReceived: t.rcpAmount,
        balanceAfter: t.rcpBalance,
        advance: t.rcpAdvance,
        receivedBy: t.rcpReceivedBy,
        amended: t.rcpAmended,
        proprietor: t.rcpProprietor,
        signature: t.rcpSignature,
        thanks: t.rcpThanks,
      );
}
