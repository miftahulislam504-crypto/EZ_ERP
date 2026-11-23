import 'package:ez_erp/features/trade/trade_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calcLine', () {
    test('applies discount before tax', () {
      final c = calcLine(qty: 100, price: 10, discount: 50, taxRate: 5);
      expect(c.gross, 1000);
      expect(c.discount, 50);
      expect(c.net, 950);
      expect(c.tax, 47.5);
      expect(c.total, 997.5);
    });

    test('caps the discount at the line amount', () {
      final c = calcLine(qty: 1, price: 10, discount: 99);
      expect(c.discount, 10);
      expect(c.net, 0);
    });

    test('rounds to two decimals half away from zero', () {
      expect(calcLine(qty: 2.5, price: 0.005).gross, 0.01);
      expect(calcLine(qty: 3, price: 33.333, taxRate: 5).tax, 5.0);
    });

    test('a line without price is free', () {
      final c = calcLine(qty: 4, price: 0);
      expect(c.total, 0);
    });
  });

  group('qtyText', () {
    test('drops trailing zeros', () {
      expect(qtyText(60), '60');
      expect(qtyText(100.0), '100');
      expect(qtyText(2.5), '2.5');
      expect(qtyText(0.125), '0.125');
      expect(qtyText(0), '0');
    });

    test('shows a dash for a missing value', () {
      expect(qtyText(null), '--');
    });
  });

  group('document types', () {
    test('every type has its own route set', () {
      final paths = tradeTypes.values.map((t) => t.path).toSet();
      expect(paths.length, tradeTypes.length);
      expect(orderType.newPath, '/purchase/orders/new');
      expect(billType.detailPath('abc'), '/purchase/bills/abc');
      expect(receiptType.editPath('abc'), '/purchase/receipts/abc/edit');
    });

    test('notifications and links resolve a document path', () {
      expect(tradeDocumentPath('purchase_order', '1'), '/purchase/orders/1');
      expect(tradeDocumentPath('supplier_bill', '2'), '/purchase/bills/2');
      expect(tradeDocumentPath('something_else', '3'), isNull);
    });

    test('only receipts skip approval and only requisitions skip the supplier', () {
      expect(receiptType.usesApproval, isFalse);
      expect(requisitionType.needsSupplier, isFalse);
      expect(orderType.usesApproval && billType.usesApproval && requisitionType.usesApproval, isTrue);
    });

    test('adjustment reasons that can only go one way', () {
      expect(reducingReasons, containsAll(['damaged', 'expired', 'lost', 'issue']));
      expect(increasingReasons, {'opening_stock'});
      expect(adjustmentReasons.keys, containsAll([...reducingReasons, ...increasingReasons, 'count_correction', 'other']));
    });
  });

  group('sales document types', () {
    test('are registered by key', () {
      expect(tradeTypes['sales_quotation'], same(quotationType));
      expect(tradeTypes['sales_order'], same(salesOrderType));
      expect(tradeTypes['sales_invoice'], same(invoiceType));
    });

    test('the party is a customer on sales documents and a supplier on purchases', () {
      expect(quotationType.partyLabel, 'Customer');
      expect(invoiceType.partyRole, 'customer');
      expect(billType.partyLabel, 'Supplier');
      expect(orderType.partyRole, 'supplier');
      expect(invoiceType.isSales, isTrue);
      expect(billType.isSales, isFalse);
    });

    test('only posted invoices and bills are settled by payments', () {
      expect(invoiceType.hasPayments, isTrue);
      expect(billType.hasPayments, isTrue);
      expect(salesOrderType.hasPayments, isFalse);
      expect(quotationType.hasPayments, isFalse);
      expect(receiptType.hasPayments, isFalse);
    });

    test('quotations are sent instead of approved', () {
      expect(quotationType.usesApproval, isFalse);
      expect(salesOrderType.usesApproval, isTrue);
      expect(invoiceType.usesApproval, isTrue);
    });

    test('bills and invoices can be filtered by what is still unpaid or overdue', () {
      for (final t in [billType, invoiceType]) {
        final states = t.filters.map((f) => f.paymentState).whereType<String>().toList();
        expect(states, ['open', 'overdue']);
      }
    });

    test('paths follow the section they live in', () {
      expect(invoiceType.newPath, '/sales/invoices/new');
      expect(salesOrderType.detailPath('x'), '/sales/orders/x');
      expect(tradeDocumentPath('sales_quotation', 'q1'), '/sales/quotations/q1');
      expect(partyProfilePath('customer', 'c1'), '/sales/customers/c1');
      expect(partyProfilePath('supplier', 's1'), '/purchase/suppliers/s1');
    });
  });
}
