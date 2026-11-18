import 'package:rent_solution/core/permissions/role.dart';

/// Every action the UI or repositories can be gated on.
enum Permission {
  /// Create or edit properties and units.
  propertyWrite,

  /// See basic tenant info (name, photo, unit, phone, dues, member count).
  tenantBasicRead,

  /// Create or edit tenants.
  tenantWrite,

  /// See NID, address, agreement, household IDs and other vault data.
  tenantSensitiveRead,

  /// Change vault data: NID number, address, agreement, household IDs, sensitive documents.
  tenantSensitiveWrite,

  /// See household names, relations and roles.
  householdBasicRead,

  /// Record a payment.
  paymentCreate,

  /// Edit a payment (always needs email confirmation).
  paymentEdit,

  /// Record an expense.
  expenseCreate,

  /// Open a maintenance ticket.
  ticketCreate,

  /// Change a ticket's status.
  ticketUpdate,

  /// Enter meter readings.
  meterReadingWrite,

  /// Add optional extra charges (electricity, gas, water, fines, other) to a tenant.
  chargeWrite,

  /// Adjust a bill before it is sent.
  billAdjust,

  /// Send a bill or receipt through WhatsApp and save its PDF.
  billSend,

  /// View reports.
  reportsView,

  /// View own receipts, statement and lease.
  ownRecordsView,

  /// Invite, suspend, resume or revoke members.
  membersManage,

  /// Change settings.
  settingsManage,

  /// Run backup and restore.
  backupManage,

  /// Read the audit log.
  auditView,

  /// Delete anything (always needs email confirmation).
  deleteAny,

  /// Ask an admin to delete something.
  deletionRequest,

  /// Share tenant details with the police.
  policeShare,

  /// Keep legal notices and NOCs, and erase a tenant's personal data on a legal notice.
  legalRecords,

  /// Restore from the Deleted Items Archive.
  archiveRestore,

  /// View CCTV (Phase 6).
  cctvView,
}

/// Permissions that can never be granted to a non-admin through overrides.
const adminOnlyPermissions = <Permission>{
  Permission.paymentEdit,
  Permission.deleteAny,
  Permission.membersManage,
  Permission.settingsManage,
  Permission.backupManage,
  Permission.auditView,
  Permission.policeShare,
  Permission.archiveRestore,
  Permission.legalRecords,
};

/// Permissions that can never be taken away from an Admin (they always keep their own records).
const protectedFromRevoke = <Permission>{Permission.ownRecordsView};

/// Default permissions per role. All UI gating reads from here.
final Map<Role, Set<Permission>> permissionMatrix = {
  Role.owner: Set.unmodifiable(Permission.values),
  Role.admin: Set.unmodifiable(Permission.values),
  Role.manager: Set.unmodifiable({
    Permission.tenantBasicRead,
    Permission.tenantWrite,
    Permission.householdBasicRead,
    Permission.paymentCreate,
    Permission.expenseCreate,
    Permission.ticketCreate,
    Permission.ticketUpdate,
    Permission.meterReadingWrite,
    Permission.chargeWrite,
    Permission.billAdjust,
    Permission.billSend,
    Permission.reportsView,
    Permission.ownRecordsView,
    Permission.deletionRequest,
    Permission.cctvView,
  }),
  Role.caretaker: Set.unmodifiable({
    Permission.tenantBasicRead,
    Permission.householdBasicRead,
    Permission.paymentCreate,
    Permission.ticketCreate,
    Permission.ticketUpdate,
    Permission.meterReadingWrite,
    Permission.billSend,
    Permission.ownRecordsView,
    Permission.deletionRequest,
    Permission.cctvView,
  }),
  Role.tenant: Set.unmodifiable({
    Permission.ticketCreate,
    Permission.ownRecordsView,
  }),
};

/// One member's access: role, status, property scope, and per-user overrides set by an admin.
class MemberAccess {
  /// Creates a member's access description.
  const MemberAccess({
    required this.role,
    this.status = MemberStatus.active,
    this.grants = const {},
    this.revokes = const {},
    this.propertyScope = const {},
    this.vaultAccess = false,
    this.linkedTenantId,
  });

  /// The member's role.
  final Role role;

  /// Active, suspended or revoked.
  final MemberStatus status;

  /// Extra permissions granted to this member (admin-only ones are ignored).
  final Set<Permission> grants;

  /// Permissions taken away from this member.
  final Set<Permission> revokes;

  /// Property ids this member may work with. Empty means all properties.
  final Set<String> propertyScope;

  /// True when an admin approved vault access (the member holds the vault key).
  final bool vaultAccess;

  /// For a tenant member: the one tenant record they may see.
  final String? linkedTenantId;

  /// Final permission set. Empty unless the member is active.
  Set<Permission> get effective {
    if (status != MemberStatus.active) {
      return const {};
    }
    final result = {...?permissionMatrix[role]};
    if (role == Role.admin) {
      // The Owner may take individual permissions away from an Admin, except the protected ones.
      result.removeAll(revokes.difference(protectedFromRevoke));
    } else if (!role.isAdminLevel) {
      result
        ..addAll(grants.difference(adminOnlyPermissions))
        ..removeAll(revokes);
      // Sensitive data also needs the vault key, which only a vault-approved member holds.
      if (!vaultAccess) {
        result
          ..remove(Permission.tenantSensitiveRead)
          ..remove(Permission.tenantSensitiveWrite);
      }
    }
    return result;
  }

  /// Whether this member may do [permission].
  bool can(Permission permission) => effective.contains(permission);

  /// Whether this member may work with [propertyId].
  bool canAccessProperty(String propertyId) =>
      status == MemberStatus.active &&
      (role.isAdminLevel || propertyScope.isEmpty || propertyScope.contains(propertyId));

  /// Whether [tenantId] is this tenant member's own record.
  bool isOwnTenant(String tenantId) =>
      status == MemberStatus.active && role == Role.tenant && linkedTenantId == tenantId;
}
