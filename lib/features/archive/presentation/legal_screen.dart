import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/data/local/enums.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/security/confirm_action_dialog.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';
import 'package:rent_solution/shared/widgets/fields_dialog.dart';

/// Legal notices and NOCs of a tenant who moved out, and the legal erasure of their personal data.
class LegalScreen extends ConsumerWidget {
  /// Creates the screen.
  const LegalScreen({required this.tenantId, super.key});

  /// The tenant.
  final String tenantId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final kind = await showDialog<LegalRecordKind>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(t.addLegal),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(d, LegalRecordKind.legalNotice), child: Text(t.legalNotice)),
          SimpleDialogOption(onPressed: () => Navigator.pop(d, LegalRecordKind.noc), child: Text(t.legalNoc)),
        ],
      ),
    );
    if (kind == null || !context.mounted) {
      return;
    }
    final fields = await showDialog<List<String>>(
      context: context,
      builder: (_) => FieldsDialog(
        title: t.addLegal,
        labels: [t.legalRef],
        confirmLabel: t.save,
        cancelLabel: t.cancel,
      ),
    );
    if (fields == null || !context.mounted) {
      return;
    }
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(t.pickFile),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(d, ImageSource.camera), child: Text(t.takePhoto)),
          SimpleDialogOption(onPressed: () => Navigator.pop(d, ImageSource.gallery), child: Text(t.pickFromGallery)),
        ],
      ),
    );
    if (source == null || !context.mounted) {
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 85);
      if (picked == null) {
        return;
      }
      final dot = picked.path.lastIndexOf('.');
      final repo = await ref.read(legalRecordsRepositoryProvider.future);
      await repo.add(
        tenantId: tenantId,
        kind: kind,
        issuedOn: DateTime.now().toUtc(),
        bytes: await picked.readAsBytes(),
        extension: dot < 0 ? 'jpg' : picked.path.substring(dot + 1),
        referenceNo: fields.first,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.documentAdded)));
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(t, e))));
      }
    }
  }

  Future<void> _erase(BuildContext context, WidgetRef ref, String legalRecordId) async {
    final t = AppLocalizations.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(t.legalErase),
        content: Text(t.legalEraseWarn),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(t.legalErase)),
        ],
      ),
    );
    if (sure != true || !context.mounted) {
      return;
    }
    final token = await confirmSensitiveAction(
      context,
      ref,
      action: SensitiveAction.legalErasure,
      entityId: tenantId,
    );
    if (token == null || !context.mounted) {
      return;
    }
    try {
      final repo = await ref.read(legalErasureRepositoryProvider.future);
      await repo.eraseTenant(tenantId, legalRecordId: legalRecordId, confirmation: token);
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.legalErased)));
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(t, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final records = ref.watch(legalRecordsProvider(tenantId));
    return Scaffold(
      appBar: AppBar(title: Text(t.legalTitle)),
      body: records.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (list) {
          final notice = list.where((r) => r.kind == LegalRecordKind.legalNotice).firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (list.isEmpty) Text(t.legalNone),
              for (final r in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(r.kind == LegalRecordKind.noc ? t.legalNoc : t.legalNotice),
                  subtitle: Text(
                    '${context.fmt.date(r.issuedOn.toLocal())}${r.referenceNo == null ? '' : ' · ${r.referenceNo}'}',
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add),
                label: Text(t.addLegal),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: notice == null ? null : () => _erase(context, ref, notice.id),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(t.legalErase),
              ),
              if (notice == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t.legalNeedNotice, style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          );
        },
      ),
    );
  }
}
