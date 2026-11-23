import 'package:ez_erp/features/payments/payment_models.dart';
import 'package:flutter_test/flutter_test.dart';

OpenItem item(String id, String number, String due, double balance, {int past = 0}) => OpenItem(
      id: id,
      number: number,
      docType: 'sales_invoice',
      docDate: DateTime.parse('2026-01-01'),
      dueDate: DateTime.parse(due),
      total: balance,
      balance: balance,
      daysPastDue: past,
    );

void main() {
  group('agingBucketOf', () {
    test('a document that is not yet due is current', () {
      expect(agingBucketOf(-20), 'current');
      expect(agingBucketOf(0), 'current');
    });

    test('buckets follow days past the due date', () {
      expect(agingBucketOf(1), 'd1_30');
      expect(agingBucketOf(30), 'd1_30');
      expect(agingBucketOf(31), 'd31_60');
      expect(agingBucketOf(60), 'd31_60');
      expect(agingBucketOf(61), 'd61_90');
      expect(agingBucketOf(90), 'd61_90');
      expect(agingBucketOf(91), 'over_90');
      expect(agingBucketOf(400), 'over_90');
    });

    test('every bucket has a label', () {
      for (final b in agingBuckets) {
        expect(agingBucketLabels.containsKey(b), isTrue);
      }
    });
  });

  group('allocateOldestFirst', () {
    final a = item('a', 'INV-1', '2026-01-01', 100);
    final b = item('b', 'INV-2', '2026-01-10', 200);
    final c = item('c', 'INV-3', '2026-01-05', 50);

    test('pays the oldest due date first', () {
      final r = allocateOldestFirst(120, [a, b, c]);
      expect(r.map((x) => x.documentId).toList(), ['a', 'c']);
      expect(r[0].amount, 100);
      expect(r[1].amount, 20);
    });

    test('never applies more than a document owes and leaves the rest as an advance', () {
      final r = allocateOldestFirst(1000, [a, b, c]);
      expect(totalAllocated(r), 350);
      expect(advanceOf(1000, r), 650);
    });

    test('a payment of zero allocates nothing', () {
      expect(allocateOldestFirst(0, [a, b, c]), isEmpty);
    });

    test('a named document is paid first', () {
      final r = allocateOldestFirst(150, [a, b, c], firstId: 'b');
      expect(r.length, 1);
      expect(r.first.documentId, 'b');
      expect(r.first.amount, 150);
    });

    test('ties on the due date follow the document number', () {
      final x = item('x', 'INV-9', '2026-02-01', 10);
      final y = item('y', 'INV-2', '2026-02-01', 10);
      expect(allocateOldestFirst(10, [x, y]).first.documentId, 'y');
    });

    test('cents do not drift', () {
      final r = allocateOldestFirst(0.3, [item('p', 'INV-1', '2026-01-01', 0.1), item('q', 'INV-2', '2026-01-02', 0.2)]);
      expect(totalAllocated(r), 0.3);
      expect(advanceOf(0.3, r), 0);
    });

    test('serialises for the server', () {
      expect(const Allocation('d1', 12.5).toJson(), {'document_id': 'd1', 'amount': 12.5});
    });
  });

  group('limits', () {
    test('an amount must be positive and within the balance', () {
      expect(withinBalance(50, 100), isTrue);
      expect(withinBalance(100, 100), isTrue);
      expect(withinBalance(100.01, 100), isFalse);
      expect(withinBalance(0, 100), isFalse);
    });

    test('advance is never negative', () {
      expect(advanceOf(10, [const Allocation('a', 12)]), 0);
    });

    test('roundMoney rounds to cents', () {
      expect(roundMoney(1.005 * 100 / 100), anyOf(1.0, 1.01));
      expect(roundMoney(2.345), anyOf(2.34, 2.35));
      expect(roundMoney(10), 10);
    });
  });

  group('paymentStateOf', () {
    test('paid when nothing is left', () {
      expect(paymentStateOf(total: 100, paid: 100, daysOverdue: 40), 'paid');
    });

    test('overdue beats partial when the due date has passed', () {
      expect(paymentStateOf(total: 100, paid: 40, daysOverdue: 5), 'overdue');
    });

    test('partial when something is paid and it is not yet due', () {
      expect(paymentStateOf(total: 100, paid: 40, daysOverdue: 0), 'partial');
    });

    test('posted when nothing is paid and it is not yet due', () {
      expect(paymentStateOf(total: 100, paid: 0, daysOverdue: 0), 'posted');
    });
  });

  group('LedgerSide', () {
    test('receivable is the customer side', () {
      const s = LedgerSide.receivable;
      expect(s.isReceivable, isTrue);
      expect(s.paymentKind, 'receipt');
      expect(s.docType, 'sales_invoice');
      expect(s.recordLabel, 'Record receipt');
      expect(s.paymentPath('p1'), '/finance/receivables/payments/p1');
      expect(s.profilePath('c1'), '/sales/customers/c1');
    });

    test('payable is the supplier side', () {
      const s = LedgerSide.payable;
      expect(s.isReceivable, isFalse);
      expect(s.paymentKind, 'payment');
      expect(s.docType, 'supplier_bill');
      expect(s.paymentPath('p1'), '/finance/payables/payments/p1');
      expect(s.profilePath('s1'), '/purchase/suppliers/s1');
    });

    test('can be found from a payment kind or a party role', () {
      expect(LedgerSide.ofKind('receipt'), LedgerSide.receivable);
      expect(LedgerSide.ofKind('payment'), LedgerSide.payable);
      expect(LedgerSide.ofRole('customer'), LedgerSide.receivable);
      expect(LedgerSide.ofRole('supplier'), LedgerSide.payable);
    });
  });

  group('OpenItem.fromRow', () {
    test('reads what the aging function returns', () {
      final i = OpenItem.fromRow({
        'document_id': 'd1',
        'number': 'INV-00007',
        'doc_type': 'sales_invoice',
        'doc_date': '2026-03-01',
        'due_date': '2026-03-31',
        'total': 500,
        'balance': 125.5,
        'days_past_due': 12,
        'reference': 'PO-9',
        'is_opening': true,
      });
      expect(i.id, 'd1');
      expect(i.balance, 125.5);
      expect(i.overdue, isTrue);
      expect(i.isOpening, isTrue);
      expect(i.dueDate, DateTime.parse('2026-03-31'));
    });
  });
}
