import 'package:flutter/material.dart';

/// A small dialog with text fields. Returns the typed values, or null when cancelled.
class FieldsDialog extends StatefulWidget {
  /// Creates the dialog. [initial] pre-fills the fields.
  const FieldsDialog({
    required this.title,
    required this.labels,
    required this.confirmLabel,
    required this.cancelLabel,
    this.keyboards,
    this.initial,
    this.message,
    super.key,
  });

  /// Dialog title.
  final String title;

  /// One label per field.
  final List<String> labels;

  /// Keyboard per field (default text).
  final List<TextInputType>? keyboards;

  /// Starting text per field.
  final List<String>? initial;

  /// Optional explanation above the fields.
  final String? message;

  /// Text of the confirm button.
  final String confirmLabel;

  /// Text of the cancel button.
  final String cancelLabel;

  @override
  State<FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<FieldsDialog> {
  late final List<TextEditingController> _controllers = [
    for (var i = 0; i < widget.labels.length; i++)
      TextEditingController(text: widget.initial != null ? widget.initial![i] : ''),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < widget.labels.length; i++) ...[
              TextField(
                controller: _controllers[i],
                keyboardType: widget.keyboards?[i] ?? TextInputType.text,
                autofocus: i == 0,
                decoration: InputDecoration(labelText: widget.labels[i]),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.cancelLabel)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([for (final c in _controllers) c.text]),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
