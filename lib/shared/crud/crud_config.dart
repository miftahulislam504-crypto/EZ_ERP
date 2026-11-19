import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Option {
  const Option(this.value, this.label);
  final String value;
  final String label;
}

enum FieldType { text, multiline, number, money, email, phone, dropdown, toggle, date, image }

class FieldDef {
  const FieldDef(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.hint,
    this.options,
    this.optionsSource,
    this.defaultValue,
    this.inList = false,
    this.flex = 2,
    this.fullWidth = false,
    this.lockOnEdit = false,
    this.section,
    this.sensitive = false,
    this.imageBucket = 'product-images',
  });

  /// Database column.
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? hint;

  /// Fixed options for dropdowns.
  final List<Option>? options;

  /// Options loaded from the backend for dropdowns (any provider of AsyncValue<List<Option>>).
  final ProviderListenable<AsyncValue<List<Option>>>? optionsSource;

  /// Initial value on create. For number and money fields it is also used when the box is left empty.
  final Object? defaultValue;

  /// Show as a column in the list view.
  final bool inList;
  final int flex;
  final bool fullWidth;

  /// Value can be set on create but not changed afterwards.
  final bool lockOnEdit;

  /// Heading the field is grouped under in the form. Fields without one come first.
  final String? section;

  /// Financial figure (cost, balance). Hidden from roles without the financial figures permission.
  final bool sensitive;

  /// Storage bucket for image fields.
  final String imageBucket;
}

/// Describes a master-data screen. One config drives the list, search,
/// create and edit form, archive and permission checks.
class CrudConfig {
  CrudConfig({
    required this.title,
    required this.singular,
    required this.table,
    required this.module,
    required this.fields,
    this.subtitle,
    this.select = '*',
    this.orderBy = 'name',
    this.titleKey = 'name',
    this.searchKeys = const ['name'],
    this.hasActiveFlag = false,
    this.icon = Icons.list_alt_rounded,
    this.extraInsert = const {},
    this.filters = const {},
    this.collapsedSections = const [],
  });

  final String title;
  final String singular;
  final String? subtitle;
  final String table;

  /// Permission module key (see Modules).
  final String module;
  final List<FieldDef> fields;
  final String select;
  final String orderBy;

  /// Column shown as the primary text on mobile cards.
  final String titleKey;
  final List<String> searchKeys;

  /// When true the table has is_active and rows are archived instead of deleted.
  final bool hasActiveFlag;
  final IconData icon;

  /// Constant values added to every inserted row (for example a lookup kind).
  final Map<String, dynamic> extraInsert;

  /// Equality filters applied when listing (for example is_customer = true).
  final Map<String, Object> filters;

  /// Form sections that start collapsed (advanced details).
  final List<String> collapsedSections;
}
