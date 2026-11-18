import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/id_numbers.dart';
import 'package:rent_solution/core/utils/ids.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/documents_repository.dart';
import 'package:rent_solution/data/repositories/tenant_vault_repository.dart';
import 'package:rent_solution/data/repositories/write_context.dart';

/// Saves the outcome of an NID scan AFTER a person reviewed and corrected it. The OCR text itself is
/// never saved without that review; the card photo goes to the encrypted document store.
class OcrRepository {
  /// Creates the repository.
  OcrRepository(this._db, this._guard, this._ctx, this._documents, this._vault);

  final AppDatabase _db;
  final AccessGuard _guard;
  final WriteContext _ctx;
  final DocumentsRepository _documents;
  final TenantVaultRepository _vault;

  /// Stores the card photo (encrypted), saves the reviewed NID number to the tenant's private
  /// details, and records the scan with who confirmed it. [suggestedNid] is what the reader
  /// found; [reviewedNid] is what the person confirmed (they may differ).
  Future<String> confirmNidScan({
    required String tenantId,
    required Uint8List image,
    required String extension,
    required String reviewedNid,
    String? suggestedNid,
  }) async {
    _guard.require(Permission.tenantSensitiveWrite);
    final nid = normalizeNid(reviewedNid);
    if (nid == null) {
      throw ArgumentError('The NID number must have 10, 13 or 17 digits.');
    }
    final documentId = await _documents.store(
      tenantId: tenantId,
      type: DocumentType.nid,
      bytes: image,
      extension: extension,
    );
    await _vault.save(tenantId, nidNo: nid);
    final id = newId();
    final now = _ctx.now;
    await _ctx.transaction(_db, () async {
      await _db.into(_db.ocrScans).insert(
            OcrScansCompanion.insert(
              id: id,
              orgId: _ctx.orgId,
              createdAt: now,
              updatedAt: now,
              createdBy: _ctx.userId,
              deviceId: _ctx.deviceId,
              hlc: _ctx.hlc,
              sourceType: OcrSourceType.nid,
              imageDocId: documentId,
              // Only whether the reader and the person agreed: never the NID itself.
              extractedJson: jsonEncode({'matchedSuggestion': suggestedNid != null && suggestedNid == nid}),
              confirmedBy: Value(_ctx.userId),
              confirmedAt: Value(now),
            ),
          );
      await _db.auditDao.append(
        orgId: _ctx.orgId,
        userId: _ctx.userId,
        action: 'ocr.confirm',
        entityType: 'ocr_scan',
        entityId: id,
        newValue: jsonEncode({'tenantId': tenantId, 'source': 'nid'}),
        at: now,
      );
    });
    return id;
  }
}
