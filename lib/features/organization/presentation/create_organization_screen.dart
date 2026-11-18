import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';
import 'package:rent_solution/shared/widgets/language_dropdown.dart';

/// First-time setup: name the business. The signed-in person becomes the Owner.
class CreateOrganizationScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreateOrganizationScreen({super.key});

  @override
  ConsumerState<CreateOrganizationScreen> createState() => _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends ConsumerState<CreateOrganizationScreen> {
  final _name = TextEditingController(text: BrandConfig.companyName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final state = ref.watch(createOrganizationControllerProvider);
    final busy = state.isLoading;
    return Scaffold(
      appBar: AppBar(title: Text(t.createOrgTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(t.createOrgHint),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: t.orgNameLabel),
            ),
            const SizedBox(height: 16),
            const LanguageDropdown(),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      final name = _name.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(t.errorRequired)));
                        return;
                      }
                      ref.read(createOrganizationControllerProvider.notifier).create(name);
                    },
              child: Text(t.createOrgButton),
            ),
            if (busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (state.hasError) ...[
              const SizedBox(height: 24),
              Text(
                t.errorGeneric,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
