import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/features/payments/domain/receipt_pdf.dart';

// A valid 1x1 PNG used as a stand-in logo.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

ReceiptData _data({Uint8List? logo, bool amended = false}) => ReceiptData(
      orgName: 'LIFE EASY',
      ownerName: 'MAHADI HASAN JEWEL',
      address: 'Khulna, Bangladesh',
      phone: '+8801700000000',
      email: 'hello@example.com',
      website: 'example.com',
      footer: 'This receipt is computer generated.',
      logoBytes: logo,
      receiptNo: 'R2611-9F3A-0007',
      dateText: '10 Nov 2026',
      tenantName: 'Karim Uddin',
      unitLabel: 'Rahim Villa A1',
      forMonthText: 'September 2026',
      methodText: 'bKash',
      trxId: 'AB12CD34',
      amountText: 'BDT 10,000',
      balanceText: 'BDT 20,000',
      receivedBy: 'Caretaker',
      amended: amended,
    );

bool _isPdf(Uint8List bytes) => String.fromCharCodes(bytes.take(5)) == '%PDF-';

void main() {
  test('a receipt with business name, logo, address, phone and email is a real PDF', () async {
    final bytes = await buildReceiptPdf(_data(logo: _png), ReceiptLabels.english);
    expect(_isPdf(bytes), isTrue);
    expect(bytes.length, greaterThan(1000));
  });

  test('a receipt without a logo or optional details still builds', () async {
    final bytes = await buildReceiptPdf(
      const ReceiptData(
        orgName: 'Small Landlord',
        receiptNo: 'R1',
        dateText: 'today',
        tenantName: 'T',
        unitLabel: 'A1',
        forMonthText: 'Nov',
        methodText: 'Cash',
        amountText: 'BDT 1',
      ),
      ReceiptLabels.english,
    );
    expect(_isPdf(bytes), isTrue);
  });

  test('an amended receipt and an advance line build', () async {
    final bytes = await buildReceiptPdf(_data(logo: _png, amended: true), ReceiptLabels.english);
    expect(_isPdf(bytes), isTrue);
  });

  test('a damaged logo file does not stop the receipt', () async {
    final bytes = await buildReceiptPdf(_data(logo: Uint8List.fromList([1, 2, 3, 4])), ReceiptLabels.english);
    expect(_isPdf(bytes), isTrue);
  });

  test('very long text still fits on one build', () async {
    final long = ReceiptData(
      orgName: 'N' * 80,
      address: 'A' * 300,
      receiptNo: 'R1',
      dateText: 'today',
      tenantName: 'T' * 120,
      unitLabel: 'U' * 80,
      forMonthText: 'Nov',
      methodText: 'Cash',
      amountText: 'BDT 1',
      footer: 'F' * 400,
    );
    expect(_isPdf(await buildReceiptPdf(long, ReceiptLabels.english)), isTrue);
  });
}
