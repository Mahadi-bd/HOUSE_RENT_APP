// ignore_for_file: public_member_api_docs
import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/local/tables/property_tables.dart';
import 'package:rent_solution/data/local/tables/synced_columns.dart';

class Organizations extends Table with SyncedColumns {
  TextColumn get name => text()();
  TextColumn get ownerUid => text()();
  IntColumn get keyVersion => integer().withDefault(const Constant(1))();
}

@DataClassName('AppUser')
class AppUsers extends Table with SyncedColumns {
  @override
  String get tableName => 'users';
  TextColumn get name => text()();
  TextColumn get email => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get language => text().withDefault(const Constant('en'))();
}

@TableIndex(name: 'idx_memberships_org_status', columns: {#orgId, #status})
class Memberships extends Table with SyncedColumns {
  TextColumn get userId => text().references(AppUsers, #id)();
  // Set for tenant-role members: the tenant record they may see.
  TextColumn get linkedTenantId => text().nullable().references(Tenants, #id)();
  TextColumn get role => textEnum<Role>()();
  TextColumn get status => textEnum<MemberStatus>()();
  // JSON arrays stored as text.
  TextColumn get propertyScope => text().withDefault(const Constant('[]'))();
  TextColumn get grants => text().withDefault(const Constant('[]'))();
  TextColumn get revokes => text().withDefault(const Constant('[]'))();
  BoolColumn get vaultAccess => boolean().withDefault(const Constant(false))();
  TextColumn get invitedBy => text().nullable()();
  DateTimeColumn get suspendedAt => dateTime().nullable()();
  DateTimeColumn get revokedAt => dateTime().nullable()();
}

class Invitations extends Table with SyncedColumns {
  TextColumn get email => text()();
  TextColumn get role => textEnum<Role>()();
  TextColumn get tenantId => text().nullable()();
  TextColumn get codeHash => text()();
  DateTimeColumn get expiresAt => dateTime()();
  TextColumn get status =>
      textEnum<InvitationStatus>().withDefault(Constant(InvitationStatus.pending.name))();
}

@DataClassName('AppSetting')
class AppSettings extends Table with SyncedColumns {
  @override
  String get tableName => 'settings';
  TextColumn get userId => text()();
  TextColumn get language => text().withDefault(const Constant('en'))();
  TextColumn get currency => text().withDefault(const Constant('BDT'))();
  IntColumn get reminderDays => integer().withDefault(const Constant(3))();
  TextColumn get theme => text().withDefault(const Constant('system'))();
  BoolColumn get cctvEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get backupWifiOnly => boolean().withDefault(const Constant(true))();
}

/// Business details printed at the top of every receipt: name, address, phone, email, logo.
@DataClassName('OrgProfile')
class OrgProfiles extends Table with SyncedColumns {
  TextColumn get displayName => text()();
  TextColumn get ownerName => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();
  TextColumn get receiptFooter => text().nullable()();
  // A custom logo file on this device. Null means the built-in brand logo is used.
  TextColumn get logoPath => text().nullable()();
}
