import 'package:flutter/material.dart';

/// Standard empty state: what this is, what to do next.
class EmptyState extends StatelessWidget {
  /// Creates an empty state. [actionLabel] and [onAction] show the primary button.
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Large icon.
  final IconData icon;

  /// Short title.
  final String title;

  /// One-sentence explanation.
  final String message;

  /// Primary button text (optional).
  final String? actionLabel;

  /// Primary button action.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
