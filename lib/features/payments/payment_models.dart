/// Pure helpers for payments, allocation and aging. They have no Flutter
/// imports, so they are easy to test.

double roundMoney(double v) => (v * 100).roundToDouble() / 100;

/// The customer side (receivable, receipts, invoices) or the supplier side
/// (payable, payments, bills) of the books. Screens are built once and
/// parameterised with one of these.
class LedgerSide {
  const LedgerSide._({
    required this.key,
    required this.paymentKind,
    required this.role,
    required this.docType,
    required this.title,
    required this.partyLabel,
    required this.paymentLabel,
    required this.documentLabel,
    required this.advanceLabel,
    required this.basePath,
    required this.profileBase,
    required this.module,
  });

  /// Value used by the aging functions: receivable or payable.
  final String key;

  /// Value of payments.kind: receipt or payment.
  final String paymentKind;
  final String role;
  final String docType;
  final String title;
  final String partyLabel;
  final String paymentLabel;
  final String documentLabel;
  final String advanceLabel;
  final String basePath;
  final String profileBase;

  /// Permission module of the people who work with this side day to day.
  final String module;

  bool get isReceivable => key == 'receivable';

  String get recordLabel => isReceivable ? 'Record receipt' : 'Record payment';
  String get paymentsTabLabel => isReceivable ? 'Receipts' : 'Payments';
  String paymentPath(String id) => '$basePath/payments/$id';
  String profilePath(String id) => '$profileBase/$id';

  static const receivable = LedgerSide._(
    key: 'receivable',
    paymentKind: 'receipt',
    role: 'customer',
    docType: 'sales_invoice',
    title: 'Receivables',
    partyLabel: 'Customer',
    paymentLabel: 'Receipt',
    documentLabel: 'invoice',
    advanceLabel: 'Customer advance',
    basePath: '/finance/receivables',
    profileBase: '/sales/customers',
    module: 'sales',
  );

  static const payable = LedgerSide._(
    key: 'payable',
    paymentKind: 'payment',
    role: 'supplier',
    docType: 'supplier_bill',
    title: 'Payables',
    partyLabel: 'Supplier',
    paymentLabel: 'Payment',
    documentLabel: 'bill',
    advanceLabel: 'Advance to supplier',
    basePath: '/finance/payables',
    profileBase: '/purchase/suppliers',
    module: 'purchase',
  );

  static LedgerSide ofKind(String paymentKind) => paymentKind == 'receipt' ? receivable : payable;
  static LedgerSide ofRole(String role) => role == 'customer' ? receivable : payable;
}

// ---------------------------------------------------------------------
// Aging
// ---------------------------------------------------------------------
const agingBuckets = ['current', 'd1_30', 'd31_60', 'd61_90', 'over_90'];

const agingBucketLabels = {
  'current': 'Not yet due',
  'd1_30': '1 to 30 days',
  'd31_60': '31 to 60 days',
  'd61_90': '61 to 90 days',
  'over_90': 'Over 90 days',
};

/// Bucket of an open document by days past its due date. Zero or less means
/// it is not yet due. This matches what the database reports.
String agingBucketOf(int daysPastDue) {
  if (daysPastDue <= 0) return 'current';
  if (daysPastDue <= 30) return 'd1_30';
  if (daysPastDue <= 60) return 'd31_60';
  if (daysPastDue <= 90) return 'd61_90';
  return 'over_90';
}

/// An invoice or bill that still has an amount to pay.
class OpenItem {
  const OpenItem({
    required this.id,
    required this.number,
    required this.docType,
    required this.docDate,
    required this.dueDate,
    required this.total,
    required this.balance,
    required this.daysPastDue,
    this.reference,
    this.isOpening = false,
  });

  factory OpenItem.fromRow(Map<String, dynamic> r) => OpenItem(
        id: r['document_id'] as String,
        number: '${r['number']}',
        docType: '${r['doc_type']}',
        docDate: DateTime.parse('${r['doc_date']}'),
        dueDate: DateTime.parse('${r['due_date']}'),
        total: (r['total'] as num).toDouble(),
        balance: (r['balance'] as num).toDouble(),
        daysPastDue: (r['days_past_due'] as num).toInt(),
        reference: r['reference'] as String?,
        isOpening: r['is_opening'] == true,
      );

  final String id;
  final String number;
  final String docType;
  final DateTime docDate;
  final DateTime dueDate;
  final double total;
  final double balance;
  final int daysPastDue;
  final String? reference;
  final bool isOpening;

  bool get overdue => daysPastDue > 0;
}

// ---------------------------------------------------------------------
// Allocation
// ---------------------------------------------------------------------
class Allocation {
  const Allocation(this.documentId, this.amount);

  final String documentId;
  final double amount;

  Map<String, dynamic> toJson() => {'document_id': documentId, 'amount': amount};
}

/// Spreads a payment over open documents, oldest due date first, never more
/// than a document still owes. Whatever is left over is an advance. A document
/// named in [firstId] is paid before the others.
List<Allocation> allocateOldestFirst(double amount, List<OpenItem> items, {String? firstId}) {
  final sorted = [...items]..sort((a, b) {
      if (firstId != null && a.id != b.id) {
        if (a.id == firstId) return -1;
        if (b.id == firstId) return 1;
      }
      final c = a.dueDate.compareTo(b.dueDate);
      return c != 0 ? c : a.number.compareTo(b.number);
    });
  var left = roundMoney(amount);
  final out = <Allocation>[];
  for (final i in sorted) {
    if (left <= 0) break;
    final take = left < i.balance ? left : i.balance;
    if (take > 0) out.add(Allocation(i.id, roundMoney(take)));
    left = roundMoney(left - take);
  }
  return out;
}

double totalAllocated(Iterable<Allocation> a) => roundMoney(a.fold<double>(0, (s, x) => s + x.amount));

/// The part of a payment that is not applied to any document.
double advanceOf(double amount, Iterable<Allocation> a) {
  final v = roundMoney(amount - totalAllocated(a));
  return v < 0 ? 0 : v;
}

/// Whether a payment of this much is within what is allowed against a document.
bool withinBalance(double amount, double balance) => amount > 0 && roundMoney(amount) <= roundMoney(balance);

/// Status shown for a posted invoice or bill: paid, partial, overdue or posted.
String paymentStateOf({required double total, required double paid, required int daysOverdue}) {
  if (total - paid <= 0.004) return 'paid';
  if (daysOverdue > 0) return 'overdue';
  if (paid > 0) return 'partial';
  return 'posted';
}
