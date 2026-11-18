// ignore_for_file: public_member_api_docs
import 'package:drift/drift.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/local/tables/property_tables.dart';
import 'package:rent_solution/data/local/tables/synced_columns.dart';

@TableIndex(name: 'idx_tickets_unit_status', columns: {#unitId, #status})
class MaintenanceTickets extends Table with SyncedColumns {
  TextColumn get tenantId => text().nullable().references(Tenants, #id)();
  TextColumn get unitId => text().references(Units, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get status =>
      textEnum<TicketStatus>().withDefault(Constant(TicketStatus.open.name))();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
}

@TableIndex(name: 'idx_documents_entity', columns: {#entityType, #entityId})
class Documents extends Table with SyncedColumns {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get localPath => text()();
  TextColumn get type => textEnum<DocumentType>()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get uploadedAt => dateTime()();
}

class DeletionRequests extends Table with SyncedColumns {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get requestedBy => text()();
  TextColumn get reason => text().nullable()();
  TextColumn get status => textEnum<DeletionRequestStatus>()
      .withDefault(Constant(DeletionRequestStatus.pending.name))();
  TextColumn get decidedBy => text().nullable()();
}

@TableIndex(name: 'idx_notifications_user_read', columns: {#userId, #readAt})
@DataClassName('AppNotification')
class Notifications extends Table with SyncedColumns {
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get channel => text().withDefault(const Constant('in_app'))();
  DateTimeColumn get sentAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
}

/// Legal notices and NOCs. Never auto-purged; Owner/Admin only.
class LegalRecords extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get kind => textEnum<LegalRecordKind>()();
  TextColumn get referenceNo => text().nullable()();
  DateTimeColumn get issuedOn => dateTime()();
  TextColumn get documentId => text().references(Documents, #id)();
}

class ErasureRequests extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get legalRecordId => text().references(LegalRecords, #id)();
  TextColumn get requestedBy => text()();
  TextColumn get approvedBy => text().nullable()();
  DateTimeColumn get erasedAt => dateTime().nullable()();
}

class PoliceShares extends Table with SyncedColumns {
  TextColumn get tenantId => text().references(Tenants, #id)();
  TextColumn get sharedBy => text()();
  DateTimeColumn get sharedAt => dateTime()();
  TextColumn get channel => text()();
  BoolColumn get consentConfirmed => boolean()();
}

/// Deleted items kept for 2 years (encrypted snapshot), Owner/Admin only.
@TableIndex(name: 'idx_archive_purge', columns: {#purgeAfter})
class DeletedArchives extends Table with SyncedColumns {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  // JSON of the deleted record (protected by whole-database encryption today).
  TextColumn get snapshot => text()();
  TextColumn get deletedBy => text()();
  DateTimeColumn get deletedAt => dateTime()();
  DateTimeColumn get purgeAfter => dateTime()();
  // Set when the item was brought back; such entries are no longer waiting in the archive.
  DateTimeColumn get restoredAt => dateTime().nullable()();
}

class MessageTemplates extends Table with SyncedColumns {
  TextColumn get kind => text()();
  TextColumn get language => text()();
  TextColumn get body => text()();
}

class OcrScans extends Table with SyncedColumns {
  TextColumn get sourceType => textEnum<OcrSourceType>()();
  TextColumn get imageDocId => text()();
  TextColumn get extractedJson => text()();
  TextColumn get confirmedBy => text().nullable()();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
}

class CctvCameras extends Table with SyncedColumns {
  TextColumn get propertyId => text().references(Properties, #id)();
  TextColumn get name => text()();
  TextColumn get onvifXaddr => text()();
  TextColumn get username => text()();
  TextColumn get passwordEncrypted => text()();
  TextColumn get rtspUri => text().nullable()();
  BoolColumn get ptzSupported => boolean().withDefault(const Constant(false))();
}
