enum PermAction { view, create, edit, delete, approve, export }

class AppModule {
  const AppModule(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;
}

/// Permission module keys. They match role_permissions.module in the database.
class Modules {
  Modules._();

  static const dashboard = 'dashboard';
  static const sales = 'sales';
  static const purchase = 'purchase';
  static const requisitions = 'requisitions';
  static const inventory = 'inventory';
  static const finance = 'finance';
  static const expenses = 'expenses';
  static const projects = 'projects';
  static const assets = 'assets';
  static const service = 'service';
  static const documents = 'documents';
  static const reports = 'reports';
  static const approvals = 'approvals';
  static const hrAdmin = 'hr_admin';
  static const branches = 'branches';
  static const settings = 'settings';
  static const users = 'users';
  static const audit = 'audit';
  static const financialData = 'financial_data';

  static const all = <AppModule>[
    AppModule(dashboard, 'Dashboard', 'Company dashboards and widgets'),
    AppModule(sales, 'Sales and customers', 'Customers, quotations, orders, invoices'),
    AppModule(purchase, 'Purchase and suppliers', 'Suppliers, purchase orders, goods receipts, bills'),
    AppModule(requisitions, 'Purchase requisitions', 'Requesting goods or services to be purchased'),
    AppModule(inventory, 'Inventory and warehouses', 'Products, stock, transfers, adjustments'),
    AppModule(finance, 'Finance and accounting', 'Vouchers, ledgers, cash and bank, receivables, payables'),
    AppModule(expenses, 'Income and expense', 'Expense requests and income entries'),
    AppModule(projects, 'Projects and tasks', 'Projects, tasks and monitoring'),
    AppModule(assets, 'Assets and maintenance', 'Asset register, depreciation, maintenance'),
    AppModule(service, 'Service and support', 'Tickets, visits, warranty and AMC'),
    AppModule(documents, 'Documents', 'Central file storage'),
    AppModule(reports, 'Reports', 'Business and management reports'),
    AppModule(approvals, 'Approvals', 'Approval inbox and workflow actions'),
    AppModule(hrAdmin, 'Organization and HR summary', 'Departments, org chart, directory'),
    AppModule(branches, 'Branches and companies', 'Branch and multi-company management'),
    AppModule(settings, 'Settings', 'Organization, business and notification settings'),
    AppModule(users, 'Users and roles', 'Invitations, members, roles and permissions'),
    AppModule(audit, 'Audit log', 'Who changed what and when'),
    AppModule(financialData, 'Financial figures', 'Visibility of amounts, costs and margins'),
  ];
}

class PermissionSet {
  const PermissionSet._(this.isOwner, this._grants);

  final bool isOwner;
  final Map<String, Set<PermAction>> _grants;

  static const empty = PermissionSet._(false, {});
  static const owner = PermissionSet._(true, {});

  factory PermissionSet.fromRows(List<Map<String, dynamic>> rows) {
    final grants = <String, Set<PermAction>>{};
    for (final row in rows) {
      final set = <PermAction>{};
      for (final a in PermAction.values) {
        if (row['can_${a.name}'] == true) set.add(a);
      }
      grants[row['module'] as String] = set;
    }
    return PermissionSet._(false, grants);
  }

  bool can(String module, PermAction action) => isOwner || (_grants[module]?.contains(action) ?? false);
  bool canView(String module) => can(module, PermAction.view);
}
