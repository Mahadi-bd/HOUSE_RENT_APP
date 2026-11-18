import 'package:flutter/material.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';

/// Shown when the data on this phone cannot be opened because its key is missing or wrong.
/// Nothing is deleted and no new key is made, so the old data stays recoverable.
class RecoveryScreen extends StatelessWidget {
  /// Creates the screen.
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.lock_reset, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(t.recoveryTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(t.recoveryExplain),
            const SizedBox(height: 16),
            Text(t.recoveryStepsTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('1. ${t.recoveryStep1}'),
            const SizedBox(height: 4),
            Text('2. ${t.recoveryStep2}'),
            const SizedBox(height: 4),
            Text('3. ${t.recoveryStep3}'),
          ],
        ),
      ),
    );
  }
}
