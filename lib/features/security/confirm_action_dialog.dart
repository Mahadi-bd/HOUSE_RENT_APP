import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/features/security/email_link_inbox.dart';
import 'package:rent_solution/features/security/firebase_reauth_provider.dart';

/// Asks the person to confirm ONE action on ONE record with a link sent to their email.
/// Returns a single-use token, or null when cancelled. Offline, nothing is sent and the dialog
/// says "Connect to the internet to confirm this change."
Future<ConfirmationToken?> confirmSensitiveAction(
  BuildContext context,
  WidgetRef ref, {
  required SensitiveAction action,
  required String entityId,
}) {
  return showDialog<ConfirmationToken>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConfirmDialog(
      service: ref.read(confirmationServiceProvider),
      action: action,
      entityId: entityId,
    ),
  );
}

class _ConfirmDialog extends ConsumerStatefulWidget {
  const _ConfirmDialog({required this.service, required this.action, required this.entityId});

  final ConfirmationService service;
  final SensitiveAction action;
  final String entityId;

  @override
  ConsumerState<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends ConsumerState<_ConfirmDialog> {
  final _link = TextEditingController();
  final _pending = ValueNotifier<PendingConfirmation?>(null);
  final _busy = ValueNotifier<bool>(true);
  final _error = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  @override
  void dispose() {
    _link.dispose();
    _pending.dispose();
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    try {
      final pending = await widget.service.begin(
        action: widget.action,
        entityId: widget.entityId,
      );
      if (mounted) {
        _pending.value = pending;
      }
    } on Object catch (e) {
      if (mounted) {
        _error.value = friendlyError(AppLocalizations.of(context), e);
      }
    } finally {
      if (mounted) {
        _busy.value = false;
      }
    }
  }

  Future<void> _confirm() async {
    final pending = _pending.value;
    if (pending == null) {
      return;
    }
    _busy.value = true;
    _error.value = null;
    try {
      final token = await widget.service.complete(pending, _link.text);
      if (mounted) {
        Navigator.of(context).pop(token);
      }
    } on Object catch (e) {
      if (mounted) {
        _error.value = friendlyError(AppLocalizations.of(context), e);
        _busy.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // A link that opens the app finishes the confirmation by itself.
    ref.listen<String?>(emailLinkInboxProvider, (previous, link) {
      if (link != null && _pending.value != null && !_busy.value) {
        _link.text = link;
        ref.read(emailLinkInboxProvider.notifier).clear();
        _confirm();
      }
    });
    return AlertDialog(
      title: Text(t.confirmTitle),
      content: SingleChildScrollView(
        child: ValueListenableBuilder<PendingConfirmation?>(
          valueListenable: _pending,
          builder: (context, pending, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pending != null) ...[
                Text(t.confirmSent(pending.email)),
                const SizedBox(height: 12),
                TextField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(labelText: t.confirmLinkLabel),
                ),
              ],
              ValueListenableBuilder<bool>(
                valueListenable: _busy,
                builder: (context, busy, _) => busy
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            if (pending == null) Text(t.confirmSending),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _error,
                builder: (context, message, _) => message == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          message,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        ValueListenableBuilder<PendingConfirmation?>(
          valueListenable: _pending,
          builder: (context, pending, _) => ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (context, busy, _) => FilledButton(
              onPressed: pending == null || busy ? null : _confirm,
              child: Text(t.confirmButton),
            ),
          ),
        ),
      ],
    );
  }
}
