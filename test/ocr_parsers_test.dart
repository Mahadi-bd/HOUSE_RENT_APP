import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/features/ocr/domain/ocr_parsers.dart';

void main() {
  group('parseNidText', () {
    test('English labels with a spaced 13-digit number', () {
      final scan = parseNidText('''
National ID Card
Name: MD RAHIM   UDDIN
Father: ABDUL KARIM
Mother: RAHIMA BEGUM
Date of Birth: 12 Jan 1990
ID NO: 199 012 345 6789
''');
      expect(scan.nidNo, '1990123456789');
      expect(scan.name, 'MD RAHIM UDDIN');
      expect(scan.fatherName, 'ABDUL KARIM');
      expect(scan.motherName, 'RAHIMA BEGUM');
      expect(scan.dateOfBirth, DateTime.utc(1990, 1, 12));
      expect(scan.warnings, isEmpty);
    });

    test('Bengali labels and Bengali digits', () {
      final scan = parseNidText('জাতীয় পরিচয় পত্র\nনাম: মোঃ রহিম উদ্দিন\nপিতা: আব্দুল করিম\nমাতা: রহিমা বেগম\nজন্ম তারিখ: ১২ Jan ১৯৯০\nID NO: ১৯৯০১২৩৪৫৬৭৮৯');
      expect(scan.nidNo, '1990123456789');
      expect(scan.name, 'মোঃ রহিম উদ্দিন');
      expect(scan.fatherName, 'আব্দুল করিম');
      expect(scan.dateOfBirth, DateTime.utc(1990, 1, 12));
    });

    test('numeric date and a 10-digit number without a label', () {
      final scan = parseNidText('Name: A B\nDate of Birth 05/03/1985\n1234567890');
      expect(scan.dateOfBirth, DateTime.utc(1985, 3, 5));
      expect(scan.nidNo, '1234567890');
    });

    test('digits on the next line do not run into the NID number', () {
      final scan = parseNidText('ID NO: 1990123456789\n12 Jan 1990');
      expect(scan.nidNo, '1990123456789');
    });

    test('nothing readable gives warnings, never made-up values', () {
      final scan = parseNidText('xx ## yy\n12345');
      expect(scan.nidNo, isNull);
      expect(scan.name, isNull);
      expect(scan.dateOfBirth, isNull);
      expect(scan.warnings, containsAll(NidWarning.values));
    });

    test('an impossible date is ignored', () {
      final scan = parseNidText('Date of Birth: 31 Feb 2000\nID NO: 1234567890');
      expect(scan.dateOfBirth, isNull);
      expect(scan.warnings, contains(NidWarning.noDateOfBirth));
    });
  });

  group('parseMobileMoneyText', () {
    test('bKash screenshot', () {
      final scan = parseMobileMoneyText('bKash\nSend Money\nTk 1,500.00\nTrxID 8N7A6D5F4E\n10:32 AM');
      expect(scan.method, PaymentMethod.bkash);
      expect(scan.trxId, '8N7A6D5F4E');
      expect(scan.amountPoisha, 150000);
    });

    test('Nagad with the taka sign and Bengali digits', () {
      final scan = parseMobileMoneyText('Nagad\nTransaction ID: 71abcd12\n৳ ৫০০');
      expect(scan.method, PaymentMethod.nagad);
      expect(scan.trxId, '71ABCD12');
      expect(scan.amountPoisha, 50000);
    });

    test('unknown text gives empty suggestions', () {
      final scan = parseMobileMoneyText('hello world');
      expect(scan.method, isNull);
      expect(scan.trxId, isNull);
      expect(scan.amountPoisha, isNull);
    });
  });
}
