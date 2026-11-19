import 'package:ez_erp/core/permissions/permissions.dart';
import 'package:ez_erp/core/utils/formatters.dart';
import 'package:ez_erp/core/utils/ids.dart';
import 'package:ez_erp/features/finance/voucher_pdf.dart';
import 'package:ez_erp/features/finance/finance_providers.dart';
import 'package:ez_erp/shared/crud/crud_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fmt', () {
    test('groups money in lakh and crore style', () {
      expect(Fmt.money(1234567.5), '৳12,34,567.50');
    });

    test('compact figures use K, L and Cr', () {
      expect(Fmt.compact(1500), '1.5 K');
      expect(Fmt.compact(250000), '2.50 L');
      expect(Fmt.compact(32000000), '3.20 Cr');
    });

    test('initials', () {
      expect(Fmt.initials('Olivia Owner'), 'OO');
      expect(Fmt.initials(''), '?');
    });
  });

  group('amountInWords', () {
    test('uses lakh and crore wording', () {
      expect(amountInWords(25000, 'BDT'), 'Taka Twenty Five Thousand Only');
      expect(amountInWords(1234567, 'BDT'), 'Taka Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven Only');
      expect(amountInWords(30000000, 'BDT'), 'Taka Three Crore Only');
    });

    test('includes paisa and other currencies', () {
      expect(amountInWords(100.5, 'BDT'), 'Taka One Hundred and Fifty Paisa Only');
      expect(amountInWords(7, 'USD'), 'USD Seven Only');
    });
  });

  group('signedBalance', () {
    test('assets and expenses grow with debits, the rest with credits', () {
      expect(signedBalance('asset', 100, 40), 60);
      expect(signedBalance('expense', 100, 40), 60);
      expect(signedBalance('liability', 40, 100), 60);
      expect(signedBalance('income', 0, 75), 75);
    });
  });

  group('newUuid', () {
    test('is a version 4 uuid and unique', () {
      final a = newUuid();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$').hasMatch(a), isTrue);
      expect(newUuid(), isNot(a));
    });
  });

  group('CrudQuery', () {
    test('equal when table, org and filters match regardless of filter order', () {
      final a = CrudQuery(table: 'parties', select: '*', orderBy: 'name', orgId: 'o1', filters: {'is_customer': true, 'is_active': true});
      final b = CrudQuery(table: 'parties', select: '*', orderBy: 'name', orgId: 'o1', filters: {'is_active': true, 'is_customer': true});
      final c = CrudQuery(table: 'parties', select: '*', orderBy: 'name', orgId: 'o1', filters: {'is_supplier': true});
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('PermissionSet', () {
    test('owner can do everything', () {
      expect(PermissionSet.owner.can(Modules.finance, PermAction.delete), isTrue);
    });

    test('rows grant only what they list', () {
      final set = PermissionSet.fromRows([
        {'module': 'sales', 'can_view': true, 'can_create': true, 'can_edit': false, 'can_delete': false, 'can_approve': false, 'can_export': false},
      ]);
      expect(set.can(Modules.sales, PermAction.create), isTrue);
      expect(set.can(Modules.sales, PermAction.edit), isFalse);
      expect(set.canView(Modules.finance), isFalse);
    });
  });
}
