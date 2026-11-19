import 'package:flutter/material.dart';

import '../../core/permissions/permissions.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/crud_page.dart';
import '../../shared/crud/option_sources.dart';

final _productConfig = CrudConfig(
  title: 'Products and services',
  singular: 'Item',
  subtitle: 'Everything you buy, stock and sell',
  table: 'products',
  module: Modules.inventory,
  hasActiveFlag: true,
  icon: Icons.category_outlined,
  searchKeys: const ['name', 'sku', 'barcode'],
  collapsedSections: const ['Stock control', 'Details'],
  fields: [
    const FieldDef('sku', 'SKU', inList: true, flex: 2, lockOnEdit: true, hint: 'Generated automatically'),
    const FieldDef('name', 'Name', required: true, inList: true, flex: 4),
    const FieldDef(
      'item_type',
      'Item type',
      type: FieldType.dropdown,
      required: true,
      defaultValue: 'product',
      inList: true,
      flex: 2,
      options: [
        Option('product', 'Product'),
        Option('service', 'Service'),
        Option('raw_material', 'Raw material'),
        Option('asset', 'Asset item'),
      ],
    ),
    const FieldDef('barcode', 'Barcode', hint: 'Scan or type'),
    FieldDef('category_id', 'Category', type: FieldType.dropdown, optionsSource: productCategoryOptions, inList: true, flex: 2),
    FieldDef('brand_id', 'Brand', type: FieldType.dropdown, optionsSource: brandOptions),
    FieldDef('unit_id', 'Unit', type: FieldType.dropdown, optionsSource: unitOptions, required: true),
    const FieldDef('sales_price', 'Sales price', type: FieldType.money, defaultValue: 0, section: 'Pricing', inList: true, flex: 2),
    const FieldDef('purchase_price', 'Purchase price', type: FieldType.money, defaultValue: 0, sensitive: true, section: 'Pricing'),
    const FieldDef('standard_cost', 'Standard cost', type: FieldType.money, defaultValue: 0, sensitive: true, section: 'Pricing'),
    FieldDef('tax_rate_id', 'Tax rate', type: FieldType.dropdown, optionsSource: taxRateOptions, section: 'Pricing'),
    const FieldDef(
      'track_inventory',
      'Track stock quantity',
      type: FieldType.toggle,
      defaultValue: true,
      section: 'Stock control',
      hint: 'Turn off for items that are not counted. Services never track stock.',
    ),
    const FieldDef('min_stock', 'Minimum stock', type: FieldType.number, defaultValue: 0, section: 'Stock control'),
    const FieldDef('reorder_level', 'Reorder level', type: FieldType.number, defaultValue: 0, section: 'Stock control', hint: 'Alert when stock falls to this level'),
    const FieldDef('description', 'Description and specifications', type: FieldType.multiline, section: 'Details'),
    const FieldDef('image_url', 'Image', type: FieldType.image, section: 'Details'),
  ],
);

final _warehouseConfig = CrudConfig(
  title: 'Warehouses',
  singular: 'Warehouse',
  subtitle: 'Stores and warehouses where stock is kept',
  table: 'warehouses',
  module: Modules.inventory,
  hasActiveFlag: true,
  icon: Icons.warehouse_outlined,
  searchKeys: const ['name', 'code'],
  fields: [
    const FieldDef('code', 'Code', required: true, inList: true, flex: 1, hint: 'For example MAIN'),
    const FieldDef('name', 'Name', required: true, inList: true, flex: 3),
    FieldDef('branch_id', 'Branch', type: FieldType.dropdown, optionsSource: branchOptions, inList: true, flex: 3),
    const FieldDef('is_default', 'Default warehouse', type: FieldType.toggle, inList: true, flex: 2, hint: 'Used when no warehouse is chosen'),
    const FieldDef('address_line', 'Address', type: FieldType.multiline),
  ],
);

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) => CrudPage(config: _productConfig);
}

class WarehousesPage extends StatelessWidget {
  const WarehousesPage({super.key});

  @override
  Widget build(BuildContext context) => CrudPage(config: _warehouseConfig);
}
