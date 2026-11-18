/// Roles inside one organization.
enum Role {
  /// The first user; cannot be removed.
  owner,

  /// Co-admin appointed by the owner.
  admin,

  /// Runs day-to-day tenant and payment work.
  manager,

  /// Collects rent and handles tickets on site.
  caretaker,

  /// Sees only their own records.
  tenant;

  /// True for owner and admin.
  bool get isAdminLevel => this == Role.owner || this == Role.admin;

  /// Parses a stored role name; unknown values become the least-privileged role.
  static Role fromName(String name) =>
      Role.values.firstWhere((r) => r.name == name, orElse: () => Role.tenant);
}

/// Whether a member may use the app right now.
enum MemberStatus {
  /// Normal access.
  active,

  /// Temporarily blocked by an admin; can be resumed.
  suspended,

  /// Permanently removed; data key is rotated.
  revoked,
}
