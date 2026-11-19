import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/crud_page.dart';
import '../../shared/crud/option_sources.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';
import 'numbering_tab.dart';

CrudConfig _lookup({
  required String kind,
  required String title,
  required String singular,
  required String subtitle,
  IconData icon = Icons.label_outline_rounded,
  bool hasParent = false,
}) {
  return CrudConfig(
    title: title,
    singular: singular,
    subtitle: subtitle,
    table: 'lookups',
    module: Modules.settings,
    hasActiveFlag: true,
    icon: icon,
    searchKeys: const ['name', 'code'],
    filters: {'kind': kind},
    extraInsert: {'kind': kind},
    fields: [
      const FieldDef('name', 'Name', required: true, inList: true, flex: 3),
      const FieldDef('code', 'Short code', inList: true, flex: 1, hint: 'Optional'),
      if (hasParent)
        FieldDef('parent_id', 'Parent category', type: FieldType.dropdown, optionsSource: productCategoryOptions, inList: true, flex: 2, hint: 'None (top level)'),
    ],
  );
}

final _units = _lookup(kind: 'unit', title: 'Units', singular: 'Unit', subtitle: 'Units of measure and packaging', icon: Icons.straighten_outlined);
final _productCategories = _lookup(
  kind: 'product_category',
  title: 'Product categories',
  singular: 'Category',
  subtitle: 'Group products and services, with optional sub-categories',
  icon: Icons.category_outlined,
  hasParent: true,
);
final _brands = _lookup(kind: 'brand', title: 'Brands', singular: 'Brand', subtitle: 'Brands of the items you stock', icon: Icons.sell_outlined);
final _customerGroups = _lookup(
  kind: 'customer_group',
  title: 'Customer groups',
  singular: 'Group',
  subtitle: 'Segment customers, for example Retail or Corporate',
  icon: Icons.people_alt_outlined,
);
final _supplierCategories = _lookup(
  kind: 'supplier_category',
  title: 'Supplier categories',
  singular: 'Category',
  subtitle: 'Segment suppliers, for example Raw materials or Services',
  icon: Icons.domain_outlined,
);
final _paymentMethods = _lookup(
  kind: 'payment_method',
  title: 'Payment methods',
  singular: 'Method',
  subtitle: 'Ways money is received and paid',
  icon: Icons.payments_outlined,
);
final _documentCategories = _lookup(
  kind: 'document_category',
  title: 'Document categories',
  singular: 'Category',
  subtitle: 'Folders for contracts, licenses and other files',
  icon: Icons.folder_open_outlined,
);

final _taxRates = CrudConfig(
  title: 'Tax rates',
  singular: 'Tax rate',
  subtitle: 'Rates you can apply to items. You decide which rates are right for your business.',
  table: 'tax_rates',
  module: Modules.settings,
  hasActiveFlag: true,
  icon: Icons.percent_rounded,
  fields: [
    const FieldDef('name', 'Name', required: true, inList: true, flex: 3, hint: 'For example Standard VAT'),
    const FieldDef('rate', 'Rate (%)', type: FieldType.number, required: true, defaultValue: 0, inList: true, flex: 1),
    const FieldDef(
      'applies_to',
      'Applies to',
      type: FieldType.dropdown,
      required: true,
      defaultValue: 'both',
      inList: true,
      flex: 2,
      options: [Option('both', 'Sales and purchases'), Option('sales', 'Sales only'), Option('purchase', 'Purchases only')],
    ),
    const FieldDef('description', 'Description', type: FieldType.multiline),
  ],
);

/// Lookup lists, tax rates and document numbering in one place.
class BusinessSettingsPage extends ConsumerStatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  ConsumerState<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends ConsumerState<BusinessSettingsPage> {
  int _tab = 0;

  static const _labels = [
    'Units',
    'Product categories',
    'Brands',
    'Customer groups',
    'Supplier categories',
    'Payment methods',
    'Document categories',
    'Tax rates',
    'Numbering',
  ];

  Widget _content() {
    final configs = [_units, _productCategories, _brands, _customerGroups, _supplierCategories, _paymentMethods, _documentCategories, _taxRates];
    if (_tab == configs.length) return const NumberingTab();
    return CrudPage(key: ValueKey('business-$_tab'), config: configs[_tab], embedded: true);
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    if (!perms.canView(Modules.settings)) return const NoAccessView();
    return AppPage(
      title: 'Business settings',
      subtitle: 'The lists and rules your forms and documents draw from',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PillTabs(labels: _labels, index: _tab, onChanged: (i) => setState(() => _tab = i)),
        ),
        const SizedBox(height: 16),
        _content(),
      ],
    );
  }
}
