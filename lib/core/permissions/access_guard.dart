import 'package:rent_solution/core/permissions/permission_matrix.dart';

/// Thrown when someone tries an action they are not allowed to do.
class PermissionDenied implements Exception {
  /// Creates the exception.
  const PermissionDenied(this.message);

  /// What was refused.
  final String message;

  @override
  String toString() => 'PermissionDenied($message)';
}

/// Checks permissions inside repositories, so hiding a button is never the only protection.
class AccessGuard {
  /// Creates a guard for [access] (null means nobody is signed in: everything is refused).
  const AccessGuard(this.access);

  /// The current member's access.
  final MemberAccess? access;

  /// Requires [permission].
  void require(Permission permission) {
    if (!(access?.can(permission) ?? false)) {
      throw PermissionDenied('Missing permission: ${permission.name}');
    }
  }

  /// Requires at least one of [permissions].
  void requireAny(Set<Permission> permissions) {
    final a = access;
    if (a == null || !permissions.any(a.can)) {
      throw PermissionDenied('Missing one of: ${permissions.map((p) => p.name).join(', ')}');
    }
  }

  /// Requires [permission] and access to [propertyId].
  void requireInProperty(Permission permission, String propertyId) {
    require(permission);
    if (!access!.canAccessProperty(propertyId)) {
      throw PermissionDenied('No access to property $propertyId');
    }
  }

  /// A tenant member may see only their own record; everyone else needs [permission]
  /// and access to the record's property.
  void requireOwnOrInProperty({
    required String tenantId,
    required String propertyId,
    required Permission permission,
  }) {
    if (access?.isOwnTenant(tenantId) ?? false) {
      return;
    }
    requireInProperty(permission, propertyId);
  }

  /// Vault data (NID, address, agreement): vault-approved staff, or the tenant's own record.
  void requireVaultRead(String tenantId) {
    if (access?.isOwnTenant(tenantId) ?? false) {
      return;
    }
    require(Permission.tenantSensitiveRead);
  }
}
