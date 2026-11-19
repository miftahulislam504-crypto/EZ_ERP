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
import '../../features/masters/inventory_master_pages.dart';
import '../../features/masters/party_pages.dart';
import '../../features/modules/modules_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/settings/audit_log_page.dart';
import '../../features/settings/business_settings_page.dart';
import '../../features/settings/org_structure_pages.dart';
import '../../features/settings/organization_settings_page.dart';
import '../../features/settings/profile_page.dart';
import '../../features/settings/settings_hub_page.dart';
import '../../features/settings/users_roles_page.dart';

typedef RouteBuilderFn = Widget Function(GoRouterState state);

/// Screens that are built. Every route listed in NavConfig but missing here
/// shows the roadmap page. When a module ships, add its route here.
final Map<String, RouteBuilderFn> featureRoutes = {
  '/dashboard': (s) => const DashboardPage(),
  '/sales/customers': (s) => const CustomersPage(),
  '/purchase/suppliers': (s) => const SuppliersPage(),
  '/inventory/products': (s) => const ProductsPage(),
  '/inventory/warehouses': (s) => const WarehousesPage(),
  '/finance/accounts': (s) => const ChartOfAccountsPage(),
  '/finance/vouchers': (s) => const VouchersPage(),
  // Order matters: the fixed "new" path must come before the ":id" patterns.
  '/finance/vouchers/new': (s) => VoucherEditorPage(key: ValueKey('new-${s.uri.queryParameters['type']}'), type: s.uri.queryParameters['type']),
  '/finance/vouchers/:id/edit': (s) => VoucherEditorPage(key: ValueKey('edit-${s.pathParameters['id']}'), voucherId: s.pathParameters['id']),
  '/finance/vouchers/:id': (s) => VoucherDetailPage(key: ValueKey('view-${s.pathParameters['id']}'), voucherId: s.pathParameters['id']!),
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
