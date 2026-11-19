import 'package:flutter/material.dart';

import '../permissions/permissions.dart';

/// One screen reachable from the sidebar, the Modules page and global search.
class NavLeaf {
  const NavLeaf(this.label, this.route, this.icon, this.module, {this.phase = 1, this.desc = ''});

  final String label;
  final String route;
  final IconData icon;

  /// Permission module that must be viewable to see this entry.
  final String module;

  /// Roadmap phase the screen ships in (see docs/FEATURE_TRACKER.md).
  final int phase;
  final String desc;
}

class NavGroup {
  const NavGroup(this.label, this.icon, this.leaves, {this.flat = false});

  final String label;
  final IconData icon;
  final List<NavLeaf> leaves;

  /// A flat group renders as a single top-level item without a header.
  final bool flat;
}

/// The complete product map. Every module in the feature plan has an entry
/// here; screens that are not built yet open a roadmap page instead.
class NavConfig {
  NavConfig._();

  static const groups = <NavGroup>[
    NavGroup('Overview', Icons.space_dashboard_outlined, [
      NavLeaf('Dashboard', '/dashboard', Icons.space_dashboard_outlined, Modules.dashboard,
          desc: 'Role based business overview with period, branch and department filters.'),
    ], flat: true),
    NavGroup('Sales', Icons.storefront_outlined, [
      NavLeaf('Customers', '/sales/customers', Icons.people_alt_outlined, Modules.sales,
          desc: 'Customer profiles, groups, credit limits, payment terms and transaction history.'),
      NavLeaf('Quotations', '/sales/quotations', Icons.request_quote_outlined, Modules.sales,
          desc: 'Create and send quotations, then convert them into sales orders.'),
      NavLeaf('Sales orders', '/sales/orders', Icons.assignment_outlined, Modules.sales,
          desc: 'Sales orders with approval and delivery tracking.'),
      NavLeaf('Invoices', '/sales/invoices', Icons.receipt_long_outlined, Modules.sales,
          desc: 'Sales invoices with partial payments, due tracking, PDF, print and share.'),
      NavLeaf('Delivery challans', '/sales/challans', Icons.local_shipping_outlined, Modules.sales,
          phase: 2, desc: 'Delivery challans linked to orders and invoices.'),
      NavLeaf('Returns and credit notes', '/sales/returns', Icons.assignment_return_outlined, Modules.sales,
          phase: 2, desc: 'Sales returns, credit notes and discounts.'),
      NavLeaf('Leads and pipeline', '/sales/leads', Icons.filter_alt_outlined, Modules.sales,
          phase: 3, desc: 'Lead tracking from New to Won with conversion reports.'),
    ]),
    NavGroup('Purchase', Icons.shopping_cart_outlined, [
      NavLeaf('Suppliers', '/purchase/suppliers', Icons.domain_outlined, Modules.purchase,
          desc: 'Supplier profiles, categories, documents, dues and payment history.'),
      NavLeaf('Requisitions', '/purchase/requisitions', Icons.playlist_add_check_outlined, Modules.requisitions,
          desc: 'Purchase requisitions with department approval.'),
      NavLeaf('Purchase orders', '/purchase/orders', Icons.shopping_bag_outlined, Modules.purchase,
          desc: 'Purchase orders with approval limits and pending PO tracking.'),
      NavLeaf('Goods receipts', '/purchase/receipts', Icons.move_to_inbox_outlined, Modules.purchase,
          desc: 'Goods receive notes that update stock and accounts.'),
      NavLeaf('Supplier bills', '/purchase/bills', Icons.description_outlined, Modules.purchase,
          desc: 'Bill verification, approval and partial payments.'),
      NavLeaf('Supplier quotations', '/purchase/quotations', Icons.compare_arrows_outlined, Modules.purchase,
          phase: 2, desc: 'Collect and compare quotations from multiple suppliers.'),
      NavLeaf('Purchase returns', '/purchase/returns', Icons.undo_outlined, Modules.purchase,
          phase: 2, desc: 'Purchase returns and supplier debit or credit adjustments.'),
    ]),
    NavGroup('Inventory', Icons.inventory_2_outlined, [
      NavLeaf('Products and services', '/inventory/products', Icons.category_outlined, Modules.inventory,
          desc: 'Items with SKU, barcode, categories, pricing and reorder levels.'),
      NavLeaf('Warehouses', '/inventory/warehouses', Icons.warehouse_outlined, Modules.inventory,
          desc: 'Warehouses and stores with locations and per-warehouse stock.'),
      NavLeaf('Stock overview', '/inventory/stock', Icons.bar_chart_outlined, Modules.inventory,
          desc: 'Current stock, valuation, movement history and low stock alerts.'),
      NavLeaf('Stock adjustments', '/inventory/adjustments', Icons.tune_outlined, Modules.inventory,
          desc: 'Stock issue, adjustment, damaged, expired and lost stock.'),
      NavLeaf('Stock transfers', '/inventory/transfers', Icons.swap_horiz_outlined, Modules.inventory,
          phase: 2, desc: 'Transfer requests with approval, dispatch and receive confirmation.'),
      NavLeaf('Stock counts', '/inventory/counts', Icons.fact_check_outlined, Modules.inventory,
          phase: 2, desc: 'Physical stock count against system stock.'),
    ]),
    NavGroup('Finance', Icons.account_balance_outlined, [
      NavLeaf('Chart of accounts', '/finance/accounts', Icons.account_tree_outlined, Modules.finance,
          desc: 'Assets, liabilities, equity, income and expenses with parent accounts.'),
      NavLeaf('Vouchers', '/finance/vouchers', Icons.edit_note_outlined, Modules.finance,
          desc: 'Journal, payment, receipt and contra vouchers with approval and reversal.'),
      NavLeaf('Income and expense', '/finance/transactions', Icons.swap_vert_outlined, Modules.expenses,
          desc: 'Income and expense entries, expense requests and approvals.'),
      NavLeaf('Receivables', '/finance/receivables', Icons.south_west_outlined, Modules.finance,
          desc: 'Customer dues, payments received, statements and aging.'),
      NavLeaf('Payables', '/finance/payables', Icons.north_east_outlined, Modules.finance,
          desc: 'Supplier dues, payments made, statements and aging.'),
      NavLeaf('Cash and bank', '/finance/cash-bank', Icons.account_balance_wallet_outlined, Modules.finance,
          desc: 'Cash and bank accounts, deposits, withdrawals and transfers.'),
      NavLeaf('Ledger', '/finance/ledger', Icons.menu_book_outlined, Modules.finance,
          desc: 'Account ledgers, cashbook and bankbook with running balances.'),
      NavLeaf('Bank reconciliation', '/finance/reconciliation', Icons.rule_outlined, Modules.finance,
          phase: 2, desc: 'Match bank statements with recorded transactions.'),
      NavLeaf('Cheques', '/finance/cheques', Icons.payments_outlined, Modules.finance,
          phase: 2, desc: 'Issue, deposit, clear and track bounced cheques.'),
      NavLeaf('Budgets', '/finance/budgets', Icons.savings_outlined, Modules.finance,
          phase: 2, desc: 'Annual and monthly budgets with actual versus budget tracking.'),
    ]),
    NavGroup('Operations', Icons.engineering_outlined, [
      NavLeaf('Projects and tasks', '/projects', Icons.task_alt_outlined, Modules.projects,
          phase: 2, desc: 'Projects, milestones, tasks, Kanban, budgets and profitability.'),
      NavLeaf('Assets', '/assets', Icons.devices_other_outlined, Modules.assets,
          phase: 2, desc: 'Asset register, depreciation, maintenance and disposal.'),
      NavLeaf('Documents', '/documents', Icons.folder_open_outlined, Modules.documents,
          phase: 2, desc: 'Central file storage with search, preview and expiry reminders.'),
      NavLeaf('Service and support', '/service', Icons.support_agent_outlined, Modules.service,
          phase: 3, desc: 'Service tickets, technicians, visits, warranty and AMC tracking.'),
    ]),
    NavGroup('Organization', Icons.apartment_outlined, [
      NavLeaf('Org chart and directory', '/organization', Icons.account_tree_outlined, Modules.hrAdmin,
          phase: 2, desc: 'Departments, designations, approval hierarchy and employee directory.'),
      NavLeaf('Branches and companies', '/companies', Icons.business_outlined, Modules.branches,
          phase: 2, desc: 'Multi-branch operations now, multi-company consolidation in Phase 3.'),
    ]),
    NavGroup('Management', Icons.insights_outlined, [
      NavLeaf('Approvals', '/approvals', Icons.verified_outlined, Modules.approvals,
          desc: 'One inbox for every pending approval with history and comments.'),
      NavLeaf('Reports', '/reports', Icons.assessment_outlined, Modules.reports,
          desc: 'Financial, sales, purchase, inventory and operations reports with drill-down.'),
      NavLeaf('Notifications', '/notifications', Icons.notifications_none_rounded, Modules.dashboard,
          desc: 'Alerts and reminders for approvals, dues, stock and deadlines.'),
    ]),
    NavGroup('Administration', Icons.settings_outlined, [
      NavLeaf('Settings', '/settings', Icons.settings_outlined, Modules.settings,
          desc: 'Organization, branches, departments, users, roles and audit log.'),
    ], flat: true),
  ];

  /// Settings sub pages. They appear in global search, not in the sidebar.
  static const settingsPages = <NavLeaf>[
    NavLeaf('Organization settings', '/settings/organization', Icons.business_center_outlined, Modules.settings),
    NavLeaf('Branches', '/settings/branches', Icons.store_mall_directory_outlined, Modules.settings),
    NavLeaf('Departments', '/settings/departments', Icons.groups_2_outlined, Modules.settings),
    NavLeaf('Business settings', '/settings/business', Icons.tune_outlined, Modules.settings),
    NavLeaf('Users and roles', '/settings/users', Icons.manage_accounts_outlined, Modules.users),
    NavLeaf('Audit log', '/settings/audit', Icons.history_rounded, Modules.audit),
    NavLeaf('My account', '/settings/profile', Icons.person_outline_rounded, Modules.dashboard),
  ];

  static List<NavLeaf> get leaves => [for (final g in groups) ...g.leaves];

  /// Groups and entries the given permissions allow the user to see.
  static List<NavGroup> visible(PermissionSet perms) => [
        for (final g in groups)
          if (g.leaves.any((l) => perms.canView(l.module)))
            NavGroup(g.label, g.icon, g.leaves.where((l) => perms.canView(l.module)).toList(), flat: g.flat),
      ];

  static List<NavLeaf> searchable(PermissionSet perms) =>
      [...leaves, ...settingsPages].where((l) => perms.canView(l.module)).toList();
}
