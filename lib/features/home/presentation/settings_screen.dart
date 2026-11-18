import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/routing/route_names.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/localization/role_labels.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/language_dropdown.dart';

/// Settings: language, who you are, sign out. More sections arrive in later phases.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final access = ref.watch(memberAccessProvider).dataOrNull;
    final user = ref.watch(authStateProvider).dataOrNull;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(t.tabSettings, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (user != null) Text(user.email ?? user.displayName ?? ''),
        if (access != null) Text(t.signedInAs(roleLabel(t, access.role))),
        const SizedBox(height: 24),
        const LanguageDropdown(),
        const SizedBox(height: 24),
        if (access?.can(Permission.settingsManage) ?? false) ...[
          OutlinedButton.icon(
            onPressed: () => context.push(RouteNames.business),
            icon: const Icon(Icons.business_outlined),
            label: Text(t.businessDetails),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          onPressed: () => context.push(RouteNames.about),
          child: Text(t.openAbout),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          child: Text(t.signOut),
        ),
        const BrandFooter(),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => context.push(RouteNames.about),
          icon: const Icon(Icons.info_outline),
          label: Text(t.aboutTitle),
        ),
        const BrandFooter(),
      ],
    );
  }
}
