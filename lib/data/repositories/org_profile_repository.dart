import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// The business details shown on receipts. Staff and tenants can read them (to print or show a
/// receipt); only Owner/Admin can change them.
class OrgProfileRepository {
  /// Creates the repository.
  OrgProfileRepository(this._db, this._guard, this._ctx);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;

  /// The profile of this organization, or null if none was saved yet.
  Future<OrgProfile?> get() async {
    _guard.requireAny({Permission.paymentCreate, Permission.ownRecordsView});
    return (_db.select(_db.orgProfiles)
          ..where((p) => p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Saves the business details. Owner/Admin only. Empty optional fields are cleared.
  Future<void> save({
    required String displayName,
    String? ownerName,
    String? address,
    String? phone,
    String? email,
    String? website,
    String? receiptFooter,
  }) async {
    _guard.require(Permission.settingsManage);
    if (displayName.trim().isEmpty) {
      throw ArgumentError('The business name is required.');
    }
    final cleanEmail = _blank(email);
    if (cleanEmail != null && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('The email address is not valid.');
    }
    final now = _ctx.now;
    await _ctx.transaction(_db, () async {
      final existing = await (_db.select(_db.orgProfiles)
            ..where((p) => p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull()))
          .getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.orgProfiles).insert(
              OrgProfilesCompanion.insert(
                id: newId(),
                orgId: _ctx.orgId,
                createdAt: now,
                updatedAt: now,
                createdBy: _ctx.userId,
                deviceId: _ctx.deviceId,
                hlc: _ctx.hlc,
                displayName: displayName.trim(),
                ownerName: Value(_blank(ownerName)),
                address: Value(_blank(address)),
                phone: Value(_blank(phone)),
                email: Value(cleanEmail),
                website: Value(_blank(website)),
                receiptFooter: Value(_blank(receiptFooter)),
              ),
            );
      } else {
        await (_db.update(_db.orgProfiles)
              ..where((p) => p.id.equals(existing.id) & p.orgId.equals(_ctx.orgId)))
            .write(
          OrgProfilesCompanion(
            displayName: Value(displayName.trim()),
            ownerName: Value(_blank(ownerName)),
            address: Value(_blank(address)),
            phone: Value(_blank(phone)),
            email: Value(cleanEmail),
            website: Value(_blank(website)),
            receiptFooter: Value(_blank(receiptFooter)),
            updatedAt: Value(now),
            hlc: Value(_ctx.hlc),
            syncStatus: Value(SyncStatus.pending),
          ),
        );
      }
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'org_profile.save',
        entityType: 'org_profile',
        entityId: existing?.id ?? _ctx.orgId,
        newValue: jsonEncode({'displayName': displayName.trim()}),
        at: now,
      );
    });
  }

  /// Sets (or clears, with null) the custom logo file path. Owner/Admin only. The business
  /// details must have been saved once before.
  Future<void> setLogoPath(String? path) async {
    _guard.require(Permission.settingsManage);
    await _ctx.transaction(_db, () async {
      final existing = await (_db.select(_db.orgProfiles)
            ..where((p) => p.orgId.equals(_ctx.orgId) & p.deletedAt.isNull()))
          .getSingleOrNull();
      if (existing == null) {
        throw StateError('Save the business details first.');
      }
      final now = _ctx.now;
      await (_db.update(_db.orgProfiles)
            ..where((p) => p.id.equals(existing.id) & p.orgId.equals(_ctx.orgId)))
          .write(
        OrgProfilesCompanion(
          logoPath: Value(path),
          updatedAt: Value(now),
          hlc: Value(_ctx.hlc),
          syncStatus: Value(SyncStatus.pending),
        ),
      );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'org_profile.logo',
        entityType: 'org_profile',
        entityId: existing.id,
        newValue: jsonEncode({'custom': path != null}),
        at: now,
      );
    });
  }

  String? _blank(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
