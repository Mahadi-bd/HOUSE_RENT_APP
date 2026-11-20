import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/formatters.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/payments/application/receipt_service.dart';
import 'package:rent_solution/features/police/domain/police_form_pdf.dart';

/// Asks for the tenant's consent, builds the police form, logs the share, and opens the share menu.
/// The form is in English for now (Bengali labels will follow); names are printed as saved.
Future<void> shareTenantWithPolice(BuildContext context, WidgetRef ref, String tenantId) async {
  final t = AppLocalizations.of(context);
  final consent = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _ConsentDialog(title: t.policeForm, text: t.policeConsent, confirm: t.policeCreate, cancel: t.cancel, error: t.errorConsent),
  );
  if (consent != true || !context.mounted) {
    return;
  }
  try {
    final repo = await ref.read(policeFormRepositoryProvider.future);
    final data = await repo.prepare(tenantId);
    final fonts = await ReceiptService.loadFonts();
    final fmt = AppFormatters('en');
    final bytes = await buildPoliceFormPdf(
      data,
      PoliceFormLabels.english,
      formatDate: fmt.date,
      typeLabel: (name) => name,
      preparedOn: DateTime.now(),
      regular: fonts.$1,
      bold: fonts.$2,
    );
    await repo.recordShare(tenantId: tenantId, channel: 'share', consentConfirmed: true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.policeLogged)));
    }
    await Printing.sharePdf(bytes: bytes, filename: 'tenant-information-form.pdf');
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(t, e))));
    }
  }
}

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog({required this.title, required this.text, required this.confirm, required this.cancel, required this.error});

  final String title;
  final String text;
  final String confirm;
  final String cancel;
  final String error;

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  final _checked = ValueNotifier<bool>(false);
  final _error = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _checked.dispose();
    _error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _checked,
            builder: (context, checked, _) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checked,
              onChanged: (v) {
                _checked.value = v ?? false;
                _error.value = false;
              },
              title: Text(widget.text),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _error,
            builder: (context, show, _) =>
                show ? Text(widget.error, style: TextStyle(color: Theme.of(context).colorScheme.error)) : const SizedBox.shrink(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(widget.cancel)),
        FilledButton(
          onPressed: () {
            if (_checked.value) {
              Navigator.pop(context, true);
            } else {
              _error.value = true;
            }
          },
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
