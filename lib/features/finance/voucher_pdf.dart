import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/formatters.dart';

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
  'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _below100(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${_ones[n % 10]}'}';

String _below1000(int n) =>
    n >= 100 ? '${_ones[n ~/ 100]} Hundred${n % 100 == 0 ? '' : ' ${_below100(n % 100)}'}' : _below100(n);

/// Whole number in words using the lakh and crore system.
String _words(int value) {
  if (value == 0) return 'Zero';
  var n = value;
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add('${_words(crore)} Crore');
  if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
  if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
  if (n > 0) parts.add(_below1000(n));
  return parts.join(' ');
}

/// "Taka Twenty Five Thousand Only" style wording printed on vouchers.
String amountInWords(num amount, String currency) {
  final total = (amount * 100).round();
  final whole = total ~/ 100;
  final minor = total % 100;
  final unit = currency == 'BDT' ? 'Taka' : currency;
  final minorUnit = currency == 'BDT' ? 'Paisa' : 'cents';
  return '$unit ${_words(whole)}${minor > 0 ? ' and ${_words(minor)} $minorUnit' : ''} Only';
}

const voucherTypeLabels = {
  'journal': 'Journal voucher',
  'payment': 'Payment voucher',
  'receipt': 'Receipt voucher',
  'contra': 'Contra voucher',
  'debit_note': 'Debit note',
  'credit_note': 'Credit note',
};

Future<pw.ThemeData> _theme() async {
  try {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final bengali = await PdfGoogleFonts.notoSansBengaliRegular();
    return pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [bengali]);
  } catch (_) {
    // Offline: fall back to the built-in font (Latin characters only).
    return pw.ThemeData.base();
  }
}

Future<Uint8List> buildVoucherPdf({
  required Map<String, dynamic> voucher,
  required List<Map<String, dynamic>> lines,
  required String orgName,
  required String currency,
}) async {
  final fmt = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);
  String money(num v) => v == 0 ? '' : fmt.format(v);
  final total = (voucher['total_amount'] as num?) ?? 0;
  final type = voucherTypeLabels['${voucher['voucher_type']}'] ?? 'Voucher';
  final doc = pw.Document(theme: await _theme());

  pw.Widget field(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  pw.Widget signature(String label) => pw.Expanded(
        child: pw.Column(children: [
          pw.SizedBox(height: 34),
          pw.Container(height: 0.6, color: PdfColors.grey600, margin: const pw.EdgeInsets.symmetric(horizontal: 8)),
          pw.SizedBox(height: 4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ]),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(orgName, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            pw.Text(type.toUpperCase(), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: PdfColors.grey500, thickness: 0.8),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                field('Voucher no', '${voucher['voucher_no']}'),
                field('Date', Fmt.date(DateTime.tryParse('${voucher['voucher_date']}'))),
              ]),
            ),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                field('Reference', '${voucher['reference'] ?? '-'}'),
                field('Status', Fmt.humanize('${voucher['status']}')),
              ]),
            ),
          ],
        ),
        if (voucher['narration'] != null) ...[
          pw.SizedBox(height: 4),
          pw.Text('Narration', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text('${voucher['narration']}', style: const pw.TextStyle(fontSize: 10)),
        ],
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: ['Account', 'Details', 'Debit ($currency)', 'Credit ($currency)'],
          data: [
            for (final l in lines)
              [
                '${(l['accounts'] as Map?)?['code'] ?? ''}  ${(l['accounts'] as Map?)?['name'] ?? ''}',
                [if (l['description'] != null) l['description'], if ((l['parties'] as Map?)?['name'] != null) '(${(l['parties'] as Map)['name']})'].join(' '),
                money((l['debit'] as num?) ?? 0),
                money((l['credit'] as num?) ?? 0),
              ],
            ['', 'Total', fmt.format(total), fmt.format(total)],
          ],
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(1.6), 3: const pw.FlexColumnWidth(1.6)},
          border: const pw.TableBorder(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5), horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4)),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Amount in words', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text(amountInWords(total, currency), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 28),
        pw.Row(children: [signature('Prepared by'), signature('Checked by'), signature('Approved by'), signature('Received by')]),
      ],
    ),
  );
  return doc.save();
}

/// Opens the system print dialog, or the browser's save-as-PDF on the web.
Future<void> printVoucher({
  required Map<String, dynamic> voucher,
  required List<Map<String, dynamic>> lines,
  required String orgName,
  required String currency,
}) async {
  final bytes = await buildVoucherPdf(voucher: voucher, lines: lines, orgName: orgName, currency: currency);
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${voucher['voucher_no']}');
}
