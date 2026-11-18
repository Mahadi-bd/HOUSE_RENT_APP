// ignore_for_file: public_member_api_docs
import 'package:drift/drift.dart';
import 'package:rent_solution/data/local/enums.dart';

/// Columns every synced table shares. Money is stored as integer poisha (1 BDT = 100).
mixin SyncedColumns on Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get deviceId => text()();
  TextColumn get hlc => text()();
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(Constant(SyncStatus.pending.name))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
