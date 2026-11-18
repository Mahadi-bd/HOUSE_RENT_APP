import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/utils/async_value_x.dart';
import 'package:rent_solution/features/auth/data/auth_repository.dart';
import 'package:rent_solution/features/security/email_link_inbox.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/brand_footer.dart';
import 'package:rent_solution/shared/widgets/brand_header.dart';
import 'package:rent_solution/shared/widgets/language_dropdown.dart';

/// Sign in with Google or an emailed link.
class SignInScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _link = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _link.dispose();
    super.dispose();
  }

  void _needValue(AppLocalizations t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.errorRequired)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final state = ref.watch(signInControllerProvider);
    final controller = ref.read(signInControllerProvider.notifier);
    ref.listen<String?>(emailLinkInboxProvider, (previous, link) {
      if (link != null) {
        ref.read(emailLinkInboxProvider.notifier).clear();
        controller.completeFromInbox(link);
      }
    });
    final busy = state.isLoading;
    final linkSent = state.dataOrNull == SignInNotice.linkSent;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const BrandHeader(),
            const SizedBox(height: 16),
            Text(t.welcomeTitle, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(t.chooseLanguageHint),
            const SizedBox(height: 16),
            const LanguageDropdown(),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: busy ? null : controller.google,
              child: Text(t.signInWithGoogle),
            ),
            const SizedBox(height: 24),
            Text(t.signInWithEmail, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: t.emailLabel),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () {
                      final email = _email.text.trim();
                      if (email.isEmpty) {
                        _needValue(t);
                        return;
                      }
                      controller.sendLink(email);
                    },
              child: Text(t.sendEmailLink),
            ),
            if (linkSent) ...[
              const SizedBox(height: 16),
              Text(t.emailLinkSent),
              const SizedBox(height: 12),
              TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: t.pasteLinkLabel),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy
                    ? null
                    : () {
                        final email = _email.text.trim();
                        final link = _link.text.trim();
                        if (email.isEmpty || link.isEmpty) {
                          _needValue(t);
                          return;
                        }
                        controller.completeLink(email, link);
                      },
                child: Text(t.completeEmailSignIn),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            const BrandFooter(),
            const BrandFooter(),
            if (state.hasError) ...[
              const SizedBox(height: 24),
              Text(
                t.errorSignIn,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
