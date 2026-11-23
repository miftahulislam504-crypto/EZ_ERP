import 'package:flutter/material.dart';

import '../../core/permissions/permissions.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/crud_page.dart';
import '../../shared/crud/option_sources.dart';

const _typeOptions = [Option('company', 'Company'), Option('individual', 'Individual')];

/// Address fields shared by customers and suppliers.
List<FieldDef> _addressFields() => const [
      FieldDef('address_line', 'Address', section: 'Billing address', fullWidth: true),
      FieldDef('division', 'Division', type: FieldType.dropdown, options: bangladeshDivisions, section: 'Billing address'),
      FieldDef('district', 'District', section: 'Billing address'),
      FieldDef('upazila', 'Upazila or thana', section: 'Billing address'),
      FieldDef('area', 'Area', section: 'Billing address'),
      FieldDef('postal_code', 'Postal code', section: 'Billing address'),
    ];

final _customerConfig = CrudConfig(
  title: 'Customers',
  singular: 'Customer',
  subtitle: 'People and companies you sell to. Open one to see what they owe, their documents and statement.',
  table: 'parties',
  module: Modules.sales,
  hasActiveFlag: true,
  icon: Icons.people_alt_outlined,
  searchKeys: const ['name', 'code', 'phone', 'email', 'contact_person'],
  filters: const {'is_customer': true},
  extraInsert: const {'is_customer': true},
  collapsedSections: const ['Business information'],
  profilePath: (row) => '/sales/customers/${row['id']}',
  fields: [
    const FieldDef('code', 'Customer code', inList: true, flex: 2, lockOnEdit: true, hint: 'Generated automatically'),
    const FieldDef('name', 'Name', required: true, inList: true, flex: 4),
    const FieldDef('party_type', 'Type', type: FieldType.dropdown, options: _typeOptions, defaultValue: 'company', required: true),
    const FieldDef('contact_person', 'Contact person'),
    const FieldDef('phone', 'Phone', type: FieldType.phone, inList: true, flex: 3),
    const FieldDef('email', 'Email', type: FieldType.email, inList: true, flex: 3),
    FieldDef('customer_group_id', 'Customer group', type: FieldType.dropdown, optionsSource: customerGroupOptions, inList: true, flex: 2),
    ..._addressFields(),
    const FieldDef('shipping_address', 'Shipping address', type: FieldType.multiline, section: 'Billing address', hint: 'Leave empty if same as billing'),
    const FieldDef('credit_limit', 'Credit limit', type: FieldType.money, section: 'Credit and terms', inList: true, flex: 2),
    const FieldDef('payment_terms_days', 'Payment terms (days)', type: FieldType.number, section: 'Credit and terms', hint: 'For example 30'),
    const FieldDef('trade_license_no', 'Trade license number', section: 'Business information'),
    const FieldDef('tax_id', 'Tax or BIN number', section: 'Business information'),
    const FieldDef('website', 'Website', section: 'Business information'),
    const FieldDef('is_supplier', 'Also a supplier', type: FieldType.toggle, section: 'Business information', hint: 'Show this party in Suppliers as well'),
    const FieldDef('notes', 'Notes', type: FieldType.multiline, section: 'Business information'),
  ],
);

final _supplierConfig = CrudConfig(
  title: 'Suppliers',
  singular: 'Supplier',
  subtitle: 'Vendors and service providers you buy from. Open one to see what you owe, their bills and statement.',
  table: 'parties',
  module: Modules.purchase,
  hasActiveFlag: true,
  icon: Icons.domain_outlined,
  searchKeys: const ['name', 'code', 'phone', 'email', 'contact_person'],
  filters: const {'is_supplier': true},
  extraInsert: const {'is_supplier': true},
  collapsedSections: const ['Business information'],
  profilePath: (row) => '/purchase/suppliers/${row['id']}',
  fields: [
    const FieldDef('code', 'Supplier code', inList: true, flex: 2, lockOnEdit: true, hint: 'Generated automatically'),
    const FieldDef('name', 'Name', required: true, inList: true, flex: 4),
    const FieldDef('party_type', 'Type', type: FieldType.dropdown, options: _typeOptions, defaultValue: 'company', required: true),
    const FieldDef('contact_person', 'Contact person'),
    const FieldDef('phone', 'Phone', type: FieldType.phone, inList: true, flex: 3),
    const FieldDef('email', 'Email', type: FieldType.email, inList: true, flex: 3),
    FieldDef('supplier_category_id', 'Supplier category', type: FieldType.dropdown, optionsSource: supplierCategoryOptions, inList: true, flex: 2),
    ..._addressFields(),
    const FieldDef('payment_terms_days', 'Payment terms (days)', type: FieldType.number, section: 'Payment terms', hint: 'For example 30'),
    const FieldDef('trade_license_no', 'Trade license number', section: 'Business information'),
    const FieldDef('tax_id', 'Tax or BIN number', section: 'Business information'),
    const FieldDef('website', 'Website', section: 'Business information'),
    const FieldDef('is_customer', 'Also a customer', type: FieldType.toggle, section: 'Business information', hint: 'Show this party in Customers as well'),
    const FieldDef('notes', 'Notes', type: FieldType.multiline, section: 'Business information'),
  ],
);

/// Form definitions, shared with the profile pages that open the same edit form.
CrudConfig get customerCrudConfig => _customerConfig;
CrudConfig get supplierCrudConfig => _supplierConfig;

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) => CrudPage(config: _customerConfig);
}

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) => CrudPage(config: _supplierConfig);
}
