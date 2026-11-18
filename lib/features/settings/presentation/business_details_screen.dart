import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as pth;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rent_solution/core/brand/brand_config.dart';
import 'package:rent_solution/core/localization/friendly_error.dart';
import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/repository_providers.dart';
import 'package:rent_solution/features/tenants/application/tenant_providers.dart';

/// Business name, owner, address, phone, email and website. They are printed on every receipt.
class BusinessDetailsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BusinessDetailsScreen({super.key});

  @override
  ConsumerState<BusinessDetailsScreen> createState() => _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends ConsumerState<BusinessDetailsScreen> {
  final _controllers = {
    for (final k in ['name', 'owner', 'address', 'phone', 'email', 'website', 'footer'])
      k: TextEditingController(),
  };
  final _busy = ValueNotifier<bool>(false);
  final _error = ValueNotifier<String?>(null);
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _busy.dispose();
    _error.dispose();
    super.dispose();
  }

  void _fill(OrgProfile? p) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    _controllers['name']!.text = p?.displayName ?? BrandConfig.companyName;
    _controllers['owner']!.text = p?.ownerName ?? '';
    _controllers['address']!.text = p?.address ?? '';
    _controllers['phone']!.text = p?.phone ?? '';
    _controllers['email']!.text = p?.email ?? '';
    _controllers['website']!.text = p?.website ?? '';
    _controllers['footer']!.text = p?.receiptFooter ?? '';
  }

  Future<void> _chooseLogo() async {
    final t = AppLocalizations.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) {
        return;
      }
      final dir = Directory(pth.join((await getApplicationDocumentsDirectory()).path, 'brand'));
      await dir.create(recursive: true);
      final target = File(pth.join(dir.path, 'logo_custom${pth.extension(picked.path)}'));
      await File(picked.path).copy(target.path);
      final repo = await ref.read(orgProfileRepositoryProvider.future);
      await repo.setLogoPath(target.path);
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.logoSaved)));
      }
    } on Object catch (e) {
      if (mounted) {
        _error.value = friendlyError(AppLocalizations.of(context), e);
      }
    }
  }

  Future<void> _useBuiltInLogo() async {
    final t = AppLocalizations.of(context);
    try {
      final repo = await ref.read(orgProfileRepositoryProvider.future);
      await repo.setLogoPath(null);
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.logoSaved)));
      }
    } on Object catch (e) {
      if (mounted) {
        _error.value = friendlyError(AppLocalizations.of(context), e);
      }
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final email = _controllers['email']!.text.trim();
    if (_controllers['name']!.text.trim().isEmpty) {
      _error.value = t.errorRequired;
      return;
    }
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _error.value = t.errorEmail;
      return;
    }
    _busy.value = true;
    _error.value = null;
    try {
      final repo = await ref.read(orgProfileRepositoryProvider.future);
      await repo.save(
        displayName: _controllers['name']!.text,
        ownerName: _controllers['owner']!.text,
        address: _controllers['address']!.text,
        phone: _controllers['phone']!.text,
        email: email,
        website: _controllers['website']!.text,
        receiptFooter: _controllers['footer']!.text,
      );
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.businessSaved)));
        context.pop();
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final profile = ref.watch(orgProfileProvider);
    Widget field(String key, String label, {TextInputType? type, int lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _controllers[key],
            keyboardType: type,
            minLines: lines,
            maxLines: lines,
            decoration: InputDecoration(labelText: label),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t.businessDetails)),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(t, e))),
        data: (p) {
          _fill(p);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.businessHint),
              const SizedBox(height: 16),
              field('name', t.businessNameLabel),
              field('owner', t.ownerNameLabel),
              field('address', t.addressLabel, lines: 2),
              field('phone', t.phoneLabel, type: TextInputType.phone),
              field('email', t.emailLabel, type: TextInputType.emailAddress),
              field('website', t.websiteLabel, type: TextInputType.url),
              field('footer', t.receiptFooterLabel, lines: 2),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _chooseLogo,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(t.chooseLogo),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _useBuiltInLogo, child: Text(t.useBuiltInLogo)),
                ],
              ),
              const SizedBox(height: 12),
              Text(t.receiptFontHint, style: Theme.of(context).textTheme.bodySmall),
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
                      : Text(t.save),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
