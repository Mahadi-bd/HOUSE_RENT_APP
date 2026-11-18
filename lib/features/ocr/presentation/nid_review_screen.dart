import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/formatters_context.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/ocr/domain/ocr_parsers.dart';

/// What the review screen needs: the photo and what the reader suggested.
class NidReviewArgs {
  /// Creates the arguments.
  const NidReviewArgs({required this.image, required this.extension, required this.scan});

  /// The card photo.
  final Uint8List image;

  /// File extension (jpg, png).
  final String extension;

  /// The reader's suggestions.
  final NidScan scan;
}

/// A person compares the reader's suggestions with the card and corrects them. Nothing is saved
/// until they press "Confirm and save".
class NidReviewScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const NidReviewScreen({required this.tenantId, required this.args, super.key});

  /// The tenant the card belongs to.
  final String tenantId;

  /// The photo and suggestions.
  final NidReviewArgs args;

  @override
  ConsumerState<NidReviewScreen> createState() => _NidReviewScreenState();
}

class _NidReviewScreenState extends ConsumerState<NidReviewScreen> {
  late final TextEditingController _nid = TextEditingController(text: widget.args.scan.nidNo ?? '');
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _nid.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    _busy.value = true;
    _error.value = null;
    try {
      final repo = await ref.read(ocrRepositoryProvider.future);
      await repo.confirmNidScan(
        tenantId: widget.tenantId,
        image: widget.args.image,
        extension: widget.args.extension,
        reviewedNid: _nid.text,
        suggestedNid: widget.args.scan.nidNo,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.ocrSaved)));
        context.pop();
      }
    } on Object catch (e) {
      if (mounted) {
        _error.value = e is ArgumentError ? t.errorNid : friendlyError(t, e);
      }
    } finally {
      if (mounted) {
        _busy.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scan = widget.args.scan;
    Widget info(String label, String? value) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(value ?? t.notSet),
          subtitle: Text(label),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t.ocrReviewTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Image.memory(widget.args.image, height: 220, fit: BoxFit.contain),
          const SizedBox(height: 12),
          Text(t.ocrCompare),
          if (scan.warnings.contains(NidWarning.noNidNumber)) ...[
            const SizedBox(height: 8),
            Text(t.ocrNidMissing, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _nid,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t.nidNumberLabel),
          ),
          const SizedBox(height: 8),
          info(t.ocrNameLabel, scan.name),
          info(t.ocrFatherLabel, scan.fatherName),
          info(t.ocrMotherLabel, scan.motherName),
          info(t.ocrDobLabel, scan.dateOfBirth == null ? null : context.fmt.date(scan.dateOfBirth!)),
          const SizedBox(height: 16),
          ValueListenableBuilder<String?>(
            valueListenable: _error,
            builder: (context, message, _) => message == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (context, busy, _) => FilledButton(
              onPressed: busy ? null : _save,
              child: busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.ocrConfirm),
            ),
          ),
        ],
      ),
    );
  }
}
