import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/pill_tabs.dart';
import '../../shared/widgets/stat_card.dart';
import '../finance/finance_providers.dart';

class _SetupState {
  const _SetupState({required this.profileDone, required this.logoDone, required this.teamDone, required this.departmentsDone});
  final bool profileDone;
  final bool logoDone;
  final bool teamDone;
  final bool departmentsDone;
}

final _setupProvider = FutureProvider.autoDispose<_SetupState>((ref) async {
  final m = ref.watch(activeMembershipProvider);
  if (m == null) return const _SetupState(profileDone: true, logoDone: true, teamDone: true, departmentsDone: true);
  final client = ref.watch(supabaseProvider);
  final org = await client.from('organizations').select('phone, address_line, logo_url').eq('id', m.orgId).single();
  final members = await client.from('organization_members').select('id').eq('org_id', m.orgId);
  final invites = await client.from('invitations').select('id').eq('org_id', m.orgId).eq('status', 'pending');
  final departments = await client.from('departments').select('id').eq('org_id', m.orgId);
  bool filled(Object? v) => v != null && '$v'.trim().isNotEmpty;
  return _SetupState(
    profileDone: filled(org['phone']) && filled(org['address_line']),
    logoDone: filled(org['logo_url']),
    teamDone: members.length + invites.length > 1,
    departmentsDone: departments.isNotEmpty,
  );
});

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.route, this.module);
  final String label;
  final IconData icon;
  final String route;
  final String module;
}

const _quickActions = [
  _QuickAction('New invoice', Icons.receipt_long_outlined, '/sales/invoices', Modules.sales),
  _QuickAction('Record payment', Icons.payments_outlined, '/finance/receivables', Modules.finance),
  _QuickAction('New expense', Icons.swap_vert_outlined, '/finance/transactions', Modules.expenses),
  _QuickAction('Add customer', Icons.person_add_alt_outlined, '/sales/customers', Modules.sales),
  _QuickAction('Add supplier', Icons.domain_add_outlined, '/purchase/suppliers', Modules.purchase),
  _QuickAction('Purchase request', Icons.playlist_add_check_outlined, '/purchase/requisitions', Modules.requisitions),
  _QuickAction('Stock transfer', Icons.swap_horiz_outlined, '/inventory/transfers', Modules.inventory),
  _QuickAction('Create task', Icons.add_task_outlined, '/projects', Modules.projects),
];

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  static const _labels = ['Today', 'Last 7 days', 'This month', 'Last month', 'Custom'];
  int _period = 2;
  DateTimeRange? _custom;

  DateTimeRange get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 0:
        return DateTimeRange(start: today, end: today);
      case 1:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case 3:
        return DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0));
      case 4:
        return _custom ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      default:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
    }
  }

  Future<void> _onPeriod(int i) async {
    if (i == 4) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _custom,
      );
      if (picked == null) return;
      setState(() {
        _custom = picked;
        _period = 4;
      });
      return;
    }
    setState(() => _period = i);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(activeMembershipProvider);
    final perms = ref.watch(permsProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final branches = ref.watch(branchesProvider).valueOrNull ?? const [];
    final branchId = ref.watch(activeBranchIdProvider);
    if (m == null) return const LoadingView();

    final branchMatches = branches.where((b) => b.id == branchId).toList();
    final branchLabel = branchMatches.isEmpty ? 'all branches' : branchMatches.first.name;
    final range = _range;
    final showMoney = perms.canView(Modules.financialData);

    String? cashText;
    if (showMoney && perms.canView(Modules.finance)) {
      final fin = ref.watch(financialAccountsProvider).valueOrNull;
      final bal = ref.watch(balancesProvider).valueOrNull;
      if (fin != null && bal != null) {
        final total = fin.where((f) => f['is_active'] == true).fold<double>(0, (s, f) {
          final b = bal[f['account_id']];
          return s + (b == null ? 0 : b.debit - b.credit);
        });
        cashText = Fmt.money(total, currency: m.currency);
      }
    }

    final stats = <StatCard>[
      if (showMoney) const StatCard(label: 'Sales', value: null, icon: Icons.trending_up_rounded),
      if (showMoney) const StatCard(label: 'Income', value: null, icon: Icons.south_west_rounded, tone: BadgeTone.success),
      if (showMoney) const StatCard(label: 'Expenses', value: null, icon: Icons.north_east_rounded, tone: BadgeTone.warning),
      if (showMoney) const StatCard(label: 'Receivables', value: null, icon: Icons.request_page_outlined, tone: BadgeTone.info),
      if (showMoney) const StatCard(label: 'Payables', value: null, icon: Icons.receipt_outlined, tone: BadgeTone.danger),
      if (showMoney) StatCard(label: 'Cash and bank', value: cashText, icon: Icons.account_balance_wallet_outlined, tone: BadgeTone.success, onTap: () => context.go('/finance/cash-bank')),
      if (perms.canView(Modules.inventory)) const StatCard(label: 'Stock value', value: null, icon: Icons.inventory_2_outlined, tone: BadgeTone.neutral),
      if (perms.canView(Modules.approvals)) const StatCard(label: 'Pending approvals', value: null, icon: Icons.verified_outlined, tone: BadgeTone.warning),
    ];

    final actions = _quickActions.where((a) => perms.can(a.module, PermAction.create)).toList();
    final isAdmin = perms.can(Modules.settings, PermAction.edit);

    final quick = SectionCard(
      title: 'Quick actions',
      subtitle: 'Jump straight into common tasks',
      child: actions.isEmpty
          ? Text('No quick actions are available for your role.', style: AppText.body)
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in actions)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    onTap: () => context.go(a.route),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F9F8),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(a.icon, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(a.label, style: AppText.label),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );

    return AppPage(
      title: '${_greeting()}, ${profile?.firstName ?? 'there'}',
      subtitle: '${m.orgName}, $branchLabel. ${Fmt.date(range.start)} to ${Fmt.date(range.end)}.',
      actions: [PillTabs(labels: _labels, index: _period, onChanged: _onPeriod)],
      children: [
        if (stats.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, cons) {
              final cols = cons.maxWidth >= 1000 ? 4 : (cons.maxWidth >= 640 ? 3 : 2);
              const gap = 14.0;
              final w = (cons.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(spacing: gap, runSpacing: gap, children: [for (final s in stats) SizedBox(width: w, child: s)]);
            },
          ),
          const SizedBox(height: 10),
          Text('Figures appear here as you record sales, purchases and payments.', style: AppText.small),
          const SizedBox(height: 22),
        ],
        if (context.isWide && isAdmin)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: quick),
              const SizedBox(width: 16),
              const Expanded(flex: 2, child: _SetupCard()),
            ],
          )
        else ...[
          quick,
          if (isAdmin) ...[const SizedBox(height: 16), const _SetupCard()],
        ],
      ],
    );
  }
}

class _SetupCard extends ConsumerWidget {
  const _SetupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_setupProvider);
    return SectionCard(
      title: 'Finish setting up',
      subtitle: 'A few steps to get your workspace ready',
      child: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => Text('Setup progress is unavailable right now.', style: AppText.body),
        data: (s) {
          final items = [
            ('Complete your company profile', s.profileDone, '/settings/organization'),
            ('Upload your company logo', s.logoDone, '/settings/organization'),
            ('Invite your team', s.teamDone, '/settings/users'),
            ('Create your departments', s.departmentsDone, '/settings/departments'),
          ];
          final done = items.where((i) => i.$2).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: done / items.length,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text('$done of ${items.length} complete', style: AppText.small),
              const SizedBox(height: 10),
              for (final i in items)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () => context.go(i.$3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(i.$2 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 20, color: i.$2 ? AppColors.success : AppColors.borderStrong),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            i.$1,
                            style: AppText.bodyStrong.copyWith(
                              color: i.$2 ? AppColors.textMuted : AppColors.textPrimary,
                              decoration: i.$2 ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
