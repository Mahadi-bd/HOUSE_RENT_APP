import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Text labels on the receipt, already in the right language.
class ReceiptLabels {
  /// Creates labels.
  const ReceiptLabels({
    required this.title,
    required this.receiptNo,
    required this.date,
    required this.receivedFrom,
    required this.unit,
    required this.forMonth,
    required this.method,
    required this.transactionId,
    required this.amountReceived,
    required this.balanceAfter,
    required this.advance,
    required this.receivedBy,
    required this.amended,
    required this.proprietor,
    required this.signature,
    required this.thanks,
  });

  /// English labels, safe with the built-in PDF font.
  static const english = ReceiptLabels(
    title: 'PAYMENT RECEIPT',
    receiptNo: 'Receipt no.',
    date: 'Date',
    receivedFrom: 'Received from',
    unit: 'Unit',
    forMonth: 'For month',
    method: 'Payment method',
    transactionId: 'Transaction ID',
    amountReceived: 'Amount received',
    balanceAfter: 'Balance after this payment',
    advance: 'Paid in advance',
    receivedBy: 'Received by',
    amended: 'AMENDED (corrected after first issue)',
    proprietor: 'Proprietor',
    signature: 'Signature',
    thanks: 'Thank you.',
  );

  /// Receipt title.
  final String title;

  /// "Receipt no.".
  final String receiptNo;

  /// "Date".
  final String date;

  /// "Received from".
  final String receivedFrom;

  /// "Unit".
  final String unit;

  /// "For month".
  final String forMonth;

  /// "Payment method".
  final String method;

  /// "Transaction ID".
  final String transactionId;

  /// "Amount received".
  final String amountReceived;

  /// "Balance after this payment".
  final String balanceAfter;

  /// "Paid in advance".
  final String advance;

  /// "Received by".
  final String receivedBy;

  /// Marker for a corrected receipt.
  final String amended;

  /// "Proprietor".
  final String proprietor;

  /// "Signature".
  final String signature;

  /// Closing line.
  final String thanks;
}

/// Everything printed on a receipt. Money and dates are formatted by the caller.
class ReceiptData {
  /// Creates receipt data.
  const ReceiptData({
    required this.orgName,
    required this.receiptNo,
    required this.dateText,
    required this.tenantName,
    required this.unitLabel,
    required this.forMonthText,
    required this.methodText,
    required this.amountText,
    this.ownerName,
    this.address,
    this.phone,
    this.email,
    this.website,
    this.footer,
    this.logoBytes,
    this.trxId,
    this.balanceText,
    this.advanceText,
    this.receivedBy,
    this.amended = false,
  });

  /// Business name (company/organization).
  final String orgName;

  /// Proprietor name.
  final String? ownerName;

  /// Business address.
  final String? address;

  /// Business phone.
  final String? phone;

  /// Business email.
  final String? email;

  /// Business website.
  final String? website;

  /// Note at the bottom.
  final String? footer;

  /// Logo image bytes (PNG or JPEG).
  final Uint8List? logoBytes;

  /// Receipt number.
  final String receiptNo;

  /// Date text.
  final String dateText;

  /// Tenant name.
  final String tenantName;

  /// Unit label.
  final String unitLabel;

  /// Month the payment is for.
  final String forMonthText;

  /// Payment method text.
  final String methodText;

  /// Transaction ID (mobile money).
  final String? trxId;

  /// Amount text.
  final String amountText;

  /// Balance still owed after this payment (null = not shown).
  final String? balanceText;

  /// Advance paid (null = not shown).
  final String? advanceText;

  /// Name of the person who received the money.
  final String? receivedBy;

  /// True when the payment was corrected after it was first recorded.
  final bool amended;
}

/// Builds an A5 receipt PDF. [regular] and [bold] should be a font that has every character
/// used (for Bengali text, Noto Sans Bengali). Without them the built-in font is used, which
/// shows Latin letters and digits only.
Future<Uint8List> buildReceiptPdf(
  ReceiptData d,
  ReceiptLabels l, {
  pw.Font? regular,
  pw.Font? bold,
}) async {
  final doc = pw.Document(
    title: '${l.title} ${d.receiptNo}',
    author: d.orgName,
    theme: regular == null ? null : pw.ThemeData.withFont(base: regular, bold: bold ?? regular),
  );
  pw.ImageProvider? logo;
  if (d.logoBytes != null) {
    try {
      logo = pw.MemoryImage(d.logoBytes!);
    } on Object {
      logo = null;
    }
  }
  final grey = PdfColors.grey700;
  pw.Widget row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(label, style: pw.TextStyle(fontSize: 10, color: grey)),
            ),
            pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 11))),
          ],
        ),
      );
  final contact = [
    if (d.phone != null) d.phone!,
    if (d.email != null) d.email!,
    if (d.website != null) d.website!,
  ].join('  |  ');

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) ...[
                pw.SizedBox(width: 56, height: 56, child: pw.Image(logo, fit: pw.BoxFit.contain)),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      d.orgName,
                      style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
                    ),
                    if (d.ownerName != null)
                      pw.Text('${l.proprietor}: ${d.ownerName}', style: const pw.TextStyle(fontSize: 9)),
                    if (d.address != null) pw.Text(d.address!, style: const pw.TextStyle(fontSize: 9)),
                    if (contact.isNotEmpty) pw.Text(contact, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(l.title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ),
          if (d.amended)
            pw.Center(
              child: pw.Text(l.amended, style: pw.TextStyle(fontSize: 9, color: PdfColors.red800)),
            ),
          pw.SizedBox(height: 10),
          row(l.receiptNo, d.receiptNo),
          row(l.date, d.dateText),
          row(l.receivedFrom, d.tenantName),
          row(l.unit, d.unitLabel),
          row(l.forMonth, d.forMonthText),
          row(l.method, d.methodText),
          if (d.trxId != null) row(l.transactionId, d.trxId!),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 1),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(l.amountReceived, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(d.amountText, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          if (d.balanceText != null) row(l.balanceAfter, d.balanceText!),
          if (d.advanceText != null) row(l.advance, d.advanceText!),
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                d.receivedBy == null ? l.thanks : '${l.receivedBy}: ${d.receivedBy}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Column(
                children: [
                  pw.SizedBox(width: 110, child: pw.Divider(thickness: 0.7)),
                  pw.Text(l.signature, style: pw.TextStyle(fontSize: 8, color: grey)),
                ],
              ),
            ],
          ),
          if (d.footer != null) ...[
            pw.SizedBox(height: 6),
            pw.Text(d.footer!, style: pw.TextStyle(fontSize: 8, color: grey)),
          ],
        ],
      ),
    ),
  );
  return doc.save();
}
