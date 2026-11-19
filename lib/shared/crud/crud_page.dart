import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../widgets/adaptive_dialog.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_inputs.dart';
import '../widgets/app_page.dart';
import '../widgets/feedback.dart';
import 'crud_config.dart';
import 'crud_form.dart';

class CrudQuery {
  CrudQuery({
    required this.table,
    required this.select,
    required this.orderBy,
    required this.orgId,
    this.filters = const {},
  }) : _sig = (filters.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join('&');

  final String table;
  final String select;
  final String orderBy;
  final String orgId;
  final Map<String, Object> filters;
  final String _sig;

  @override
  bool operator ==(Object other) =>
      other is CrudQuery &&
      other.table == table &&
      other.select == select &&
      other.orderBy == orderBy &&
      other.orgId == orgId &&
      other._sig == _sig;

  @override
  int get hashCode => Object.hash(table, select, orderBy, orgId, _sig);
}

/// Loads every row for the query, one page at a time (the API caps a request at 1000 rows).
final crudListProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, CrudQuery>((ref, q) async {
  final client = ref.watch(supabaseProvider);
  const pageSize = 1000;
  final all = <Map<String, dynamic>>[];
  for (var from = 0; from < 20 * pageSize; from += pageSize) {
    var query = client.from(q.table).select(q.select).eq('org_id', q.orgId);
    for (final e in q.filters.entries) {
      query = query.eq(e.key, e.value);
    }
    final rows = await query.order(q.orderBy).order('id').range(from, from + pageSize - 1);
    all.addAll(List<Map<String, dynamic>>.from(rows));
    if (rows.length < pageSize) break;
  }
  return all;
});

class CrudPage extends ConsumerStatefulWidget {
  const CrudPage({super.key, required this.config, this.embedded = false});

  final CrudConfig config;

  /// Embedded pages render inside another page (for example a tab) without their own header.
  final bool embedded;

  @override
  ConsumerState<CrudPage> createState() => _CrudPageState();
}

class _CrudPageState extends ConsumerState<CrudPage> {
  String _search = '';
  bool _showArchived = false;

  CrudConfig get c => widget.config;

  Future<void> _openForm(String orgId, [Map<String, dynamic>? row]) async {
    final saved = await showAdaptiveForm<bool>(
      context,
      maxWidth: 680,
      builder: (_) => CrudForm(config: c, orgId: orgId, row: row),
    );
    if (saved == true) ref.invalidate(crudListProvider);
  }

  Future<void> _toggleActive(Map<String, dynamic> row) async {
    final active = row['is_active'] != false;
    final name = '${row[c.titleKey] ?? c.singular}';
    final ok = await confirmDialog(
      context,
      title: active ? 'Archive ${c.singular.toLowerCase()}?' : 'Restore ${c.singular.toLowerCase()}?',
      message: active
          ? '$name will be hidden from new transactions. Existing records keep their history.'
          : '$name will be available again.',
      confirmLabel: active ? 'Archive' : 'Restore',
      danger: active,
    );
    if (!ok) return;
    try {
      await ref.read(supabaseProvider).from(c.table).update({'is_active': !active}).eq('id', row['id'] as Object);
      ref.invalidate(crudListProvider);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${c.singular.toLowerCase()}?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(supabaseProvider).from(c.table).delete().eq('id', row['id'] as Object);
      ref.invalidate(crudListProvider);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  String _display(FieldDef f, Map<String, dynamic> row, Map<String, List<Option>> optionMap, String currency) {
    final v = row[f.key];
    if (v == null || '$v'.isEmpty) return '--';
    switch (f.type) {
      case FieldType.dropdown:
        final opts = optionMap[f.key] ?? const <Option>[];
        for (final o in opts) {
          if (o.value == '$v') return o.label;
        }
        return Fmt.humanize('$v');
      case FieldType.toggle:
        return v == true ? 'Yes' : 'No';
      case FieldType.date:
        return Fmt.date(DateTime.tryParse('$v'));
      case FieldType.money:
        return Fmt.money(num.tryParse('$v'), currency: currency);
      default:
        return '$v';
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(activeMembershipProvider);
    final perms = ref.watch(permsProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(c.module)) return const NoAccessView();

    final canCreate = perms.can(c.module, PermAction.create);
    final canEdit = perms.can(c.module, PermAction.edit);
    final canDelete = perms.can(c.module, PermAction.delete);
    final showFinancial = perms.canView(Modules.financialData);
    final fields = c.fields.where((f) => !f.sensitive || showFinancial).toList();

    final optionMap = <String, List<Option>>{};
    for (final f in fields) {
      if (f.type != FieldType.dropdown) continue;
      optionMap[f.key] = f.options ?? (f.optionsSource != null ? ref.watch(f.optionsSource!).valueOrNull : null) ?? const [];
    }

    final query = CrudQuery(table: c.table, select: c.select, orderBy: c.orderBy, orgId: m.orgId, filters: c.filters);
    final async = ref.watch(crudListProvider(query));
    final addLabel = 'Add ${c.singular.toLowerCase()}';

    final body = <Widget>[
      _toolbar(
        widget.embedded && canCreate ? AppButton(label: addLabel, icon: Icons.add_rounded, onPressed: () => _openForm(m.orgId)) : null,
      ),
      const SizedBox(height: 16),
      async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(crudListProvider)),
        data: (all) {
          final q = _search.trim().toLowerCase();
          final rows = all.where((r) {
            if (c.hasActiveFlag && !_showArchived && r['is_active'] == false) return false;
            if (q.isEmpty) return true;
            return c.searchKeys.any((k) => '${r[k] ?? ''}'.toLowerCase().contains(q));
          }).toList();

          if (rows.isEmpty) {
            return AppCard(
              child: EmptyState(
                icon: c.icon,
                title: all.isEmpty ? 'No ${c.title.toLowerCase()} yet' : 'No matching results',
                message: all.isEmpty
                    ? 'Add your first ${c.singular.toLowerCase()} to get started.'
                    : 'Try a different search or show archived records.',
                actionLabel: all.isEmpty && canCreate ? addLabel : null,
                onAction: all.isEmpty && canCreate ? () => _openForm(m.orgId) : null,
              ),
            );
          }
          return context.isMobile
              ? Column(children: [for (final r in rows) _mobileCard(m.orgId, r, fields, optionMap, m.currency, canEdit, canDelete)])
              : _table(m.orgId, rows, fields, optionMap, m.currency, canEdit, canDelete);
        },
      ),
    ];

    if (widget.embedded) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body);

    return AppPage(
      title: c.title,
      subtitle: c.subtitle,
      actions: [
        if (canCreate) AppButton(label: addLabel, icon: Icons.add_rounded, onPressed: () => _openForm(m.orgId)),
      ],
      children: body,
    );
  }

  Widget _toolbar(Widget? trailing) {
    return Row(
      children: [
        Expanded(
          child: AppTextField(
            hint: 'Search ${c.title.toLowerCase()}',
            prefixIcon: Icons.search_rounded,
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        if (c.hasActiveFlag) ...[
          const SizedBox(width: 12),
          FilterChip(
            label: const Text('Show archived'),
            selected: _showArchived,
            onSelected: (v) => setState(() => _showArchived = v),
            showCheckmark: false,
            selectedColor: AppColors.primarySoft,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _showArchived ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ],
    );
  }

  Widget _rowMenu(String orgId, Map<String, dynamic> row, bool canEdit, bool canDelete) {
    final active = row['is_active'] != false;
    final isHeadOffice = row['is_head_office'] == true;
    final items = <PopupMenuEntry<String>>[
      if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
      if (canEdit && c.hasActiveFlag && !isHeadOffice) PopupMenuItem(value: 'toggle', child: Text(active ? 'Archive' : 'Restore')),
      if (canDelete && !c.hasActiveFlag) const PopupMenuItem(value: 'delete', child: Text('Delete')),
    ];
    if (items.isEmpty) return const SizedBox(width: 40);
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      itemBuilder: (_) => items,
      onSelected: (v) {
        if (v == 'edit') _openForm(orgId, row);
        if (v == 'toggle') _toggleActive(row);
        if (v == 'delete') _delete(row);
      },
    );
  }

  Widget _table(
    String orgId,
    List<Map<String, dynamic>> rows,
    List<FieldDef> fields,
    Map<String, List<Option>> optionMap,
    String currency,
    bool canEdit,
    bool canDelete,
  ) {
    final cols = fields.where((f) => f.inList).toList();
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: const Color(0xFFF7F9F8),
            child: Row(
              children: [
                for (final f in cols)
                  Expanded(
                    flex: f.flex,
                    child: Text(f.label, style: AppText.small.copyWith(fontWeight: FontWeight.w600)),
                  ),
                if (c.hasActiveFlag) SizedBox(width: 110, child: Text('Status', style: AppText.small.copyWith(fontWeight: FontWeight.w600))),
                const SizedBox(width: 40),
              ],
            ),
          ),
          for (final r in rows) ...[
            const Divider(),
            InkWell(
              onTap: canEdit ? () => _openForm(orgId, r) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    for (var i = 0; i < cols.length; i++)
                      Expanded(
                        flex: cols[i].flex,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            _display(cols[i], r, optionMap, currency),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: i == 0 ? AppText.bodyStrong : AppText.body,
                          ),
                        ),
                      ),
                    if (c.hasActiveFlag)
                      SizedBox(
                        width: 110,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusBadge.status(r['is_active'] == false ? 'archived' : 'active'),
                        ),
                      ),
                    _rowMenu(orgId, r, canEdit, canDelete),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mobileCard(
    String orgId,
    Map<String, dynamic> r,
    List<FieldDef> fields,
    Map<String, List<Option>> optionMap,
    String currency,
    bool canEdit,
    bool canDelete,
  ) {
    final others = fields.where((f) => f.inList && f.key != c.titleKey).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        onTap: canEdit ? () => _openForm(orgId, r) : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r[c.titleKey] ?? '--'}', style: AppText.bodyStrong),
                  for (final f in others)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${f.label}: ${_display(f, r, optionMap, currency)}', style: AppText.small),
                    ),
                  if (c.hasActiveFlag) ...[
                    const SizedBox(height: 8),
                    StatusBadge.status(r['is_active'] == false ? 'archived' : 'active'),
                  ],
                ],
              ),
            ),
            _rowMenu(orgId, r, canEdit, canDelete),
          ],
        ),
      ),
    );
  }
}
