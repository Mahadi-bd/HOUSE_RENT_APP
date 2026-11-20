import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rent_solution/data/repositories/police_repository.dart';

/// Labels on the police form, already in the right language.
class PoliceFormLabels {
  /// Creates labels.
  const PoliceFormLabels({
    required this.title,
    required this.owner,
    required this.property,
    required this.tenantSection,
    required this.name,
    required this.phone,
    required this.email,
    required this.nid,
    required this.address,
    required this.emergency,
    required this.leaseFrom,
    required this.leaseTo,
    required this.household,
    required this.type,
    required this.relation,
    required this.age,
    required this.idNumber,
    required this.noMembers,
    required this.consent,
    required this.date,
    required this.ownerSignature,
    required this.tenantSignature,
    required this.openEnded,
  });

  /// English labels (safe with the built-in PDF font).
  static const english = PoliceFormLabels(
    title: 'TENANT INFORMATION FORM',
    owner: 'Owner / business',
    property: 'Property and unit',
    tenantSection: 'Tenant',
    name: 'Name',
    phone: 'Phone',
    email: 'Email',
    nid: 'NID number',
    address: 'Permanent address',
    emergency: 'Emergency contact',
    leaseFrom: 'Living here from',
    leaseTo: 'Until',
    household: 'People living in the home',
    type: 'Who',
    relation: 'Relation',
    age: 'Age',
    idNumber: 'ID number',
    noMembers: 'No other people listed.',
    consent: 'The tenant has agreed that this information is shared with the police.',
    date: 'Date',
    ownerSignature: 'Owner signature',
    tenantSignature: 'Tenant signature',
    openEnded: 'not fixed',
  );

  /// Title.
  final String title;

  /// Owner heading.
  final String owner;

  /// Property heading.
  final String property;

  /// Tenant heading.
  final String tenantSection;

  /// Name label.
  final String name;

  /// Phone label.
  final String phone;

  /// Email label.
  final String email;

  /// NID label.
  final String nid;

  /// Address label.
  final String address;

  /// Emergency label.
  final String emergency;

  /// Lease start label.
  final String leaseFrom;

  /// Lease end label.
  final String leaseTo;

  /// Household heading.
  final String household;

  /// Type column.
  final String type;

  /// Relation column.
  final String relation;

  /// Age column.
  final String age;

  /// ID column.
  final String idNumber;

  /// Text when nobody else is listed.
  final String noMembers;

  /// Consent sentence.
  final String consent;

  /// Date label.
  final String date;

  /// Owner signature label.
  final String ownerSignature;

  /// Tenant signature label.
  final String tenantSignature;

  /// Text for an open-ended lease.
  final String openEnded;
}

/// Builds the police form (A4). Dates and type names are formatted by the caller through
/// [formatDate] and [typeLabel], so the PDF is in the same language as the labels.
Future<Uint8List> buildPoliceFormPdf(
  PoliceFormData d,
  PoliceFormLabels l, {
  required String Function(DateTime) formatDate,
  required String Function(String typeName) typeLabel,
  required DateTime preparedOn,
  pw.Font? regular,
  pw.Font? bold,
}) async {
  final doc = pw.Document(
    title: l.title,
    author: d.orgName,
    theme: regular == null ? null : pw.ThemeData.withFont(base: regular, bold: bold ?? regular),
  );
  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      );
  pw.Widget row(String label, String? value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 130, child: pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(value == null || value.isEmpty ? '-' : value, style: const pw.TextStyle(fontSize: 11))),
          ],
        ),
      );
  pw.Widget cell(String text, {bool head = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(
          text.isEmpty ? '-' : text,
          style: pw.TextStyle(fontSize: 9, fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Center(child: pw.Text(l.title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
        heading(l.owner),
        row(l.name, [d.orgName, d.ownerName].whereType<String>().join(' / ')),
        row(l.address, d.orgAddress),
        row(l.phone, d.orgPhone),
        heading(l.property),
        row(l.property, d.unitLabel),
        row(l.leaseFrom, formatDate(d.leaseStart)),
        row(l.leaseTo, d.leaseEnd == null ? l.openEnded : formatDate(d.leaseEnd!)),
        heading(l.tenantSection),
        row(l.name, d.tenantName),
        row(l.phone, d.tenantPhone),
        row(l.email, d.tenantEmail),
        row(l.nid, d.nidNo),
        row(l.address, d.permanentAddress),
        row(l.emergency, d.emergencyContact),
        heading(l.household),
        if (d.members.isEmpty)
          pw.Text(l.noMembers, style: const pw.TextStyle(fontSize: 10))
        else
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(3),
              5: pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                children: [
                  cell(l.name, head: true),
                  cell(l.type, head: true),
                  cell(l.relation, head: true),
                  cell(l.age, head: true),
                  cell(l.phone, head: true),
                  cell(l.idNumber, head: true),
                ],
              ),
              for (final m in d.members)
                pw.TableRow(
                  children: [
                    cell(m.name),
                    cell(typeLabel(m.typeName)),
                    cell(m.relation ?? ''),
                    cell(m.age == null ? '' : '${m.age}'),
                    cell(m.phone ?? ''),
                    cell(m.idNo ?? ''),
                  ],
                ),
            ],
          ),
        pw.SizedBox(height: 18),
        pw.Text(l.consent, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('${l.date}: ${formatDate(preparedOn)}', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 40),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(children: [pw.SizedBox(width: 160, child: pw.Divider()), pw.Text(l.ownerSignature, style: const pw.TextStyle(fontSize: 9))]),
            pw.Column(children: [pw.SizedBox(width: 160, child: pw.Divider()), pw.Text(l.tenantSignature, style: const pw.TextStyle(fontSize: 9))]),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
