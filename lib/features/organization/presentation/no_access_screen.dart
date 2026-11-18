import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';
import 'package:rent_solution/shared/widgets/empty_state.dart';

/// Shown when an admin paused or removed this person's access.
class NoAccessScreen extends ConsumerWidget {
  /// Creates the screen.
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: EmptyState(
          icon: Icons.lock_outline,
          title: t.noAccessTitle,
          message: t.noAccessMessage,
          actionLabel: t.signOut,
          onAction: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ),
    );
  }
}
