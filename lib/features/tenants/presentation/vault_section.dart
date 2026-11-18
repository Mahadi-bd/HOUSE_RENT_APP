import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/features/ocr/data/tesseract_ocr_engine.dart';
import 'package:rent_solution/features/ocr/domain/ocr_parsers.dart';
import 'package:rent_solution/features/ocr/presentation/nid_review_screen.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/features/security/sensitive_actions.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/fields_dialog.dart';

/// NID number, permanent address and emergency contact. Hidden behind a lock for people
/// without vault access.
class VaultSection extends ConsumerWidget {
  /// Creates the section.
  const VaultSection({required this.tenantId, super.key});

  /// The tenant.
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final canRead = (access?.can(Permission.tenantSensitiveRead) ?? false) || (access?.isOwnTenant(tenantId) ?? false);
    final canWrite = access?.can(Permission.tenantSensitiveWrite) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.vaultTitle, style: Theme.of(context).textTheme.titleMedium),
        if (!canRead)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(t.vaultLocked),
          )
        else
          ref.watch(tenantVaultProvider(tenantId)).when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(friendlyError(t, e)),
                data: (v) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(v?.nidNo ?? t.notSet),
                      subtitle: Text(t.nidNumberLabel),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(v?.permanentAddress ?? t.notSet),
                      subtitle: Text(t.permanentAddressLabel),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(v?.emergencyContact ?? t.notSet),
                      subtitle: Text(t.emergencyContactLabel),
                    ),
                    if (canWrite)
                      OutlinedButton.icon(
                        onPressed: () => _scan(context, ref),
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: Text(t.scanNid),
                      ),
                    if (canWrite)
                      OutlinedButton.icon(
                        onPressed: () => _edit(context, ref, v?.nidNo, v?.permanentAddress, v?.emergencyContact),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(t.editVault),
                      ),
                  ],
                ),
              ),
      ],
    );
  }

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t.pickFile),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, ImageSource.camera), child: Text(t.takePhoto)),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, ImageSource.gallery), child: Text(t.pickFromGallery)),
        ],
      ),
    );
    if (source == null || !context.mounted) {
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 90);
      if (picked == null || !context.mounted) {
        return;
      }
      final bytes = await picked.readAsBytes();
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(t.ocrReading)]),
        ),
      ));
      NidScan scan;
      try {
        scan = parseNidText(await ref.read(ocrEngineProvider).recognize(bytes));
      } finally {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
      if (!context.mounted) {
        return;
      }
      final dot = picked.path.lastIndexOf('.');
      await context.push(
        '${RouteNames.tenants}/$tenantId/scan-nid',
        extra: NidReviewArgs(image: bytes, extension: dot < 0 ? 'jpg' : picked.path.substring(dot + 1), scan: scan),
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(t, e))));
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, String? nid, String? address, String? contact) async {
    final t = AppLocalizations.of(context);
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => FieldsDialog(
        title: t.editVault,
        labels: [t.nidNumberLabel, t.permanentAddressLabel, t.emergencyContactLabel],
        initial: [nid ?? '', address ?? '', contact ?? ''],
        keyboards: const [TextInputType.number, TextInputType.streetAddress, TextInputType.phone],
        confirmLabel: t.save,
        cancelLabel: t.cancel,
      ),
    );
    if (values == null || !context.mounted) {
      return;
    }
    try {
      final repo = await ref.read(tenantVaultRepositoryProvider.future);
      await repo.save(tenantId, nidNo: values[0], permanentAddress: values[1], emergencyContact: values[2]);
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.vaultSaved)));
      }
    } on Object catch (e) {
      if (context.mounted) {
        final message = e is ArgumentError ? t.errorNid : friendlyError(t, e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

/// Encrypted documents of a tenant: tenant photo (basic) and NID card, agreement (private).
class DocumentsSection extends ConsumerWidget {
  /// Creates the section.
  const DocumentsSection({required this.tenantId, super.key});

  /// The tenant.
  final String tenantId;

  String _label(AppLocalizations t, DocumentType type) {
    switch (type) {
      case DocumentType.nid:
        return t.docNid;
      case DocumentType.photo:
        return t.docPhoto;
      case DocumentType.lease:
        return t.docLease;
      default:
        return type.name;
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref, {required bool sensitive}) async {
    final t = AppLocalizations.of(context);
    final type = await showDialog<DocumentType>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t.addDocument),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, DocumentType.photo), child: Text(t.docPhoto)),
          if (sensitive) ...[
            SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, DocumentType.nid), child: Text(t.docNid)),
            SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, DocumentType.lease), child: Text(t.docLease)),
          ],
        ],
      ),
    );
    if (type == null || !context.mounted) {
      return;
    }
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(t.pickFile),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, ImageSource.camera), child: Text(t.takePhoto)),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, ImageSource.gallery), child: Text(t.pickFromGallery)),
        ],
      ),
    );
    if (source == null || !context.mounted) {
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final dot = picked.path.lastIndexOf('.');
      final extension = dot < 0 ? 'jpg' : picked.path.substring(dot + 1);
      final repo = await ref.read(documentsRepositoryProvider.future);
      await repo.store(tenantId: tenantId, type: type, bytes: bytes, extension: extension);
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.documentAdded)));
      }
    } on Object catch (e) {
      if (context.mounted) {
        final message = e is ArgumentError ? t.errorFileTooBig : friendlyError(t, e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _view(BuildContext context, WidgetRef ref, String documentId) async {
    final t = AppLocalizations.of(context);
    try {
      final repo = await ref.read(documentsRepositoryProvider.future);
      final bytes = await repo.read(documentId);
      final isPdf = bytes.length > 4 && String.fromCharCodes(bytes.take(4)) == '%PDF';
      if (isPdf) {
        await Printing.sharePdf(bytes: bytes, filename: 'document.pdf');
        return;
      }
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: InteractiveViewer(child: Image.memory(bytes, errorBuilder: (_, __, ___) => Text(t.errorTampered))),
        ),
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(t, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final sensitiveWrite = access?.can(Permission.tenantSensitiveWrite) ?? false;
    final canAdd = sensitiveWrite || (access?.can(Permission.tenantWrite) ?? false);
    final canRemove = access?.can(Permission.deleteAny) ?? false;
    final docs = ref.watch(tenantDocumentsProvider(tenantId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.documentsTitle, style: Theme.of(context).textTheme.titleMedium),
        docs.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(friendlyError(t, e)),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (list.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.noDocuments)),
              for (final d in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline),
                  title: Text(_label(t, d.type)),
                  subtitle: Text(context.fmt.date(d.uploadedAt.toLocal())),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: t.viewDocument,
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () => _view(context, ref, d.id),
                      ),
                      if (canRemove)
                        IconButton(
                          tooltip: t.removeDocument,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => removeDocumentFlow(context, ref, d.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (canAdd)
          OutlinedButton.icon(
            onPressed: () => _add(context, ref, sensitive: sensitiveWrite),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(t.addDocument),
          ),
      ],
    );
  }
}
