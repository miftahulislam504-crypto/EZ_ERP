class Membership {
  const Membership({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.roleId,
    required this.roleName,
    required this.isOwner,
    required this.currency,
    required this.branchIds,
    this.logoUrl,
    this.fiscalStartMonth = 7,
  });

  final String id;
  final String orgId;
  final String orgName;
  final String? logoUrl;
  final String currency;

  /// Month number (1 to 12) the financial year starts in.
  final int fiscalStartMonth;
  final String roleId;
  final String roleName;
  final bool isOwner;

  /// Empty means the member can work in every branch.
  final List<String> branchIds;

  factory Membership.fromJson(Map<String, dynamic> j) {
    final org = Map<String, dynamic>.from(j['organizations'] as Map);
    final role = Map<String, dynamic>.from(j['roles'] as Map);
    return Membership(
      id: j['id'] as String,
      orgId: j['org_id'] as String,
      orgName: org['name'] as String,
      logoUrl: org['logo_url'] as String?,
      currency: (org['currency_code'] as String?) ?? 'BDT',
      fiscalStartMonth: (org['fiscal_year_start_month'] as int?) ?? 7,
      roleId: j['role_id'] as String,
      roleName: role['name'] as String,
      isOwner: (role['is_owner'] as bool?) ?? false,
      branchIds: ((j['branch_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }
}

class BranchRef {
  const BranchRef({required this.id, required this.code, required this.name, required this.isHeadOffice});

  final String id;
  final String code;
  final String name;
  final bool isHeadOffice;

  factory BranchRef.fromJson(Map<String, dynamic> j) => BranchRef(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        isHeadOffice: (j['is_head_office'] as bool?) ?? false,
      );
}

class Profile {
  const Profile({required this.id, this.fullName, this.email, this.phone});

  final String id;
  final String? fullName;
  final String? email;
  final String? phone;

  String get firstName {
    final n = (fullName ?? '').trim();
    return n.isEmpty ? 'there' : n.split(RegExp(r'\s+')).first;
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        fullName: j['full_name'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
      );
}
