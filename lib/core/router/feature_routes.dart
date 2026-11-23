import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/dashboard_page.dart';
import '../../features/finance/cash_bank_page.dart';
import '../../features/finance/chart_of_accounts_page.dart';
import '../../features/finance/income_expense_page.dart';
import '../../features/finance/ledger_page.dart';
import '../../features/finance/voucher_detail_page.dart';
import '../../features/finance/voucher_editor_page.dart';
import '../../features/finance/vouchers_page.dart';
import '../../features/inventory/stock_adjustment_detail_page.dart';
import '../../features/inventory/stock_adjustment_editor_page.dart';
import '../../features/inventory/stock_adjustments_page.dart';
import '../../features/inventory/stock_item_page.dart';
import '../../features/inventory/stock_overview_page.dart';
import '../../features/masters/inventory_master_pages.dart';
import '../../features/masters/party_pages.dart';
import '../../features/modules/modules_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/payments/party_ledger_page.dart';
import '../../features/payments/party_profile_page.dart';
import '../../features/payments/payment_detail_page.dart';
import '../../features/payments/payment_models.dart';
import '../../features/settings/audit_log_page.dart';
import '../../features/settings/business_settings_page.dart';
import '../../features/settings/org_structure_pages.dart';
import '../../features/settings/organization_settings_page.dart';
import '../../features/settings/profile_page.dart';
import '../../features/settings/settings_hub_page.dart';
import '../../features/settings/users_roles_page.dart';
import '../../features/trade/trade_detail_page.dart';
import '../../features/trade/trade_editor_page.dart';
import '../../features/trade/trade_list_page.dart';
import '../../features/trade/trade_models.dart';

typedef RouteBuilderFn = Widget Function(GoRouterState state);

/// The four routes every purchase or sales document type needs. Order matters: the fixed
/// "new" path must come before the ":id" patterns.
Map<String, RouteBuilderFn> _tradeRoutes(TradeType t) => {
      t.path: (s) => TradeListPage(key: ValueKey('list-${t.key}'), type: t),
      '${t.path}/new': (s) => TradeEditorPage(
            key: ValueKey('new-${t.key}-${s.uri.queryParameters['from']}-${s.uri.queryParameters['supplier']}-${s.uri.queryParameters['customer']}'),
            type: t,
            fromId: s.uri.queryParameters['from'],
            // The party is a supplier on purchase documents and a customer on sales documents.
            supplierId: s.uri.queryParameters['supplier'] ?? s.uri.queryParameters['customer'],
          ),
      '${t.path}/:id/edit': (s) => TradeEditorPage(key: ValueKey('edit-${s.pathParameters['id']}'), type: t, docId: s.pathParameters['id']),
      '${t.path}/:id': (s) => TradeDetailPage(key: ValueKey('view-${s.pathParameters['id']}'), type: t, docId: s.pathParameters['id']!),
    };

/// Screens that are built. Every route listed in NavConfig but missing here
/// shows the roadmap page. When a module ships, add its route here.
final Map<String, RouteBuilderFn> featureRoutes = {
  '/dashboard': (s) => const DashboardPage(),
  '/sales/customers': (s) => const CustomersPage(),
  '/sales/customers/:id': (s) => PartyProfilePage(key: ValueKey('customer-${s.pathParameters['id']}'), side: LedgerSide.receivable, partyId: s.pathParameters['id']!),
  '/purchase/suppliers': (s) => const SuppliersPage(),
  '/purchase/suppliers/:id': (s) => PartyProfilePage(key: ValueKey('supplier-${s.pathParameters['id']}'), side: LedgerSide.payable, partyId: s.pathParameters['id']!),
  '/inventory/products': (s) => const ProductsPage(),
  '/inventory/warehouses': (s) => const WarehousesPage(),
  '/finance/accounts': (s) => const ChartOfAccountsPage(),
  '/finance/vouchers': (s) => const VouchersPage(),
  // Order matters: the fixed "new" path must come before the ":id" patterns.
  '/finance/vouchers/new': (s) => VoucherEditorPage(key: ValueKey('new-${s.uri.queryParameters['type']}'), type: s.uri.queryParameters['type']),
  '/finance/vouchers/:id/edit': (s) => VoucherEditorPage(key: ValueKey('edit-${s.pathParameters['id']}'), voucherId: s.pathParameters['id']),
  '/finance/vouchers/:id': (s) => VoucherDetailPage(key: ValueKey('view-${s.pathParameters['id']}'), voucherId: s.pathParameters['id']!),
  ..._tradeRoutes(requisitionType),
  ..._tradeRoutes(orderType),
  ..._tradeRoutes(receiptType),
  ..._tradeRoutes(billType),
  ..._tradeRoutes(quotationType),
  ..._tradeRoutes(salesOrderType),
  ..._tradeRoutes(invoiceType),
  '/finance/receivables': (s) => const PartyLedgerPage(key: ValueKey('ledger-receivable'), side: LedgerSide.receivable),
  '/finance/receivables/payments/:id': (s) => PaymentDetailPage(key: ValueKey('receipt-${s.pathParameters['id']}'), side: LedgerSide.receivable, paymentId: s.pathParameters['id']!),
  '/finance/payables': (s) => const PartyLedgerPage(key: ValueKey('ledger-payable'), side: LedgerSide.payable),
  '/finance/payables/payments/:id': (s) => PaymentDetailPage(key: ValueKey('payment-${s.pathParameters['id']}'), side: LedgerSide.payable, paymentId: s.pathParameters['id']!),
  '/inventory/stock': (s) => const StockOverviewPage(),
  '/inventory/stock/:productId': (s) => StockItemPage(key: ValueKey('stock-${s.pathParameters['productId']}'), productId: s.pathParameters['productId']!),
  '/inventory/adjustments': (s) => const StockAdjustmentsPage(),
  '/inventory/adjustments/new': (s) => const StockAdjustmentEditorPage(key: ValueKey('adj-new')),
  '/inventory/adjustments/:id/edit': (s) => StockAdjustmentEditorPage(key: ValueKey('adj-edit-${s.pathParameters['id']}'), adjustmentId: s.pathParameters['id']),
  '/inventory/adjustments/:id': (s) => StockAdjustmentDetailPage(key: ValueKey('adj-view-${s.pathParameters['id']}'), adjustmentId: s.pathParameters['id']!),
  '/finance/transactions': (s) => IncomeExpensePage(openId: s.uri.queryParameters['open']),
  '/finance/cash-bank': (s) => const CashBankPage(),
  '/finance/ledger': (s) => LedgerPage(accountId: s.uri.queryParameters['account']),
  '/notifications': (s) => const NotificationsPage(),
  '/modules': (s) => const ModulesPage(),
  '/more': (s) => const MorePage(),
  '/settings': (s) => const SettingsHubPage(),
  '/settings/organization': (s) => const OrganizationSettingsPage(),
  '/settings/branches': (s) => const BranchesPage(),
  '/settings/departments': (s) => const DepartmentsPage(),
  '/settings/business': (s) => const BusinessSettingsPage(),
  '/settings/users': (s) => const UsersRolesPage(),
  '/settings/audit': (s) => const AuditLogPage(),
  '/settings/profile': (s) => const ProfilePage(),
};
