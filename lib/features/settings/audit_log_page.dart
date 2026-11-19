import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';

const _entityNames = {
  'organizations': 'Company',
  'branches': 'Branch',
  'departments': 'Department',
  'roles': 'Role',
  'role_permissions': 'Permission',
  'organization_members': 'Member',
  'invitations': 'Invitation',
  'lookups': 'Lookup value',
  'doc_sequences': 'Numbering rule',
};

String _entity(String table) => _entityNames[table] ?? Fmt.humanize(table);

final _auditProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, table) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return <Map<String, dynamic>>[];
  var q = ref
      .watch(supabaseProvider)
      .from('audit_logs')
      .select('id, created_at, table_name, record_id, action, old_data, new_data, profiles(full_name, email)')
      .eq('org_id', m.orgId);
  if (table.isNotEmpty) q = q.eq('table_name', table);
  final rows = await q.order('created_at', ascending: false).limit(200);
  return List<Map<String, dynamic>>.from(rows);
});

class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  String _table = '';

  (String, BadgeTone) _action(String a) => switch (a) {
        'INSERT' => ('Created', BadgeTone.success),
        'DELETE' => ('Deleted', BadgeTone.danger),
        _ => ('Updated', BadgeTone.info),
      };

  Future<void> _details(Map<String, dynamic> r) {
    return showAdaptiveForm<void>(context, maxWidth: 640, builder: (_) => _AuditDetails(row: r));
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    if (!perms.canView(Modules.audit)) return const NoAccessView();
    final async = ref.watch(_auditProvider(_table));
    return AppPage(
      title: 'Audit log',
      subtitle: 'The latest 200 changes. Entries cannot be edited or removed.',
      children: [
        SizedBox(
          width: 320,
          child: AppDropdown<String>(
            label: 'Show',
            value: _table,
            items: [
              const DropdownMenuItem(value: '', child: Text('All changes')),
              for (final e in _entityNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _table = v ?? ''),
          ),
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_auditProvider)),
          data: (rows) {
            if (rows.isEmpty) {
              return const AppCard(
                child: EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No changes recorded yet',
                  message: 'Every create, update and delete in your workspace is recorded here.',
                ),
              );
            }
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(),
                    _row(rows[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final (label, tone) = _action('${r['action']}');
    final p = (r['profiles'] as Map?) ?? const {};
    final who = (p['full_name'] as String?) ?? (p['email'] as String?) ?? 'System';
    return InkWell(
      onTap: () => _details(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_entity('${r['table_name']}')} ${label.toLowerCase()}', style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text('$who, ${Fmt.dateTime(Fmt.parse(r['created_at'] as String?))}', style: AppText.small),
                ],
              ),
            ),
            StatusBadge(label, tone: tone),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _AuditDetails extends StatelessWidget {
  const _AuditDetails({required this.row});
  final Map<String, dynamic> row;

  String _fmt(Object? v) => v is Map || v is List ? jsonEncode(v) : '${v ?? '--'}';

  @override
  Widget build(BuildContext context) {
    final action = '${row['action']}';
    final oldData = (row['old_data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final newData = (row['new_data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    const hidden = {'updated_at', 'created_at'};
    final lines = <Widget>[];

    if (action == 'UPDATE') {
      for (final k in newData.keys) {
        if (hidden.contains(k) || oldData[k] == newData[k]) continue;
        lines.add(_line(k, from: _fmt(oldData[k]), to: _fmt(newData[k])));
      }
    } else {
      final data = action == 'DELETE' ? oldData : newData;
      for (final k in data.keys) {
        if (hidden.contains(k) || data[k] == null) continue;
        lines.add(_line(k, to: _fmt(data[k])));
      }
    }

    return FormShell(
      title: '${_entity('${row['table_name']}')} ${action == 'INSERT' ? 'created' : action == 'DELETE' ? 'deleted' : 'updated'}',
      subtitle: Fmt.dateTime(Fmt.parse(row['created_at'] as String?)),
      footer: Align(
        alignment: Alignment.centerRight,
        child: AppButton(label: 'Close', kind: AppButtonKind.secondary, onPressed: () => Navigator.of(context).pop()),
      ),
      child: lines.isEmpty ? Text('No field level changes were recorded.', style: AppText.body) : Column(children: lines),
    );
  }

  Widget _line(String key, {String? from, required String to}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(Fmt.humanize(key), style: AppText.small.copyWith(fontWeight: FontWeight.w600))),
          Expanded(
            child: from == null
                ? Text(to, style: AppText.body)
                : Text.rich(
                    TextSpan(
                      style: AppText.body,
                      children: [
                        TextSpan(text: from, style: const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.textMuted)),
                        const TextSpan(text: '  to  '),
                        TextSpan(text: to, style: AppText.bodyStrong),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
