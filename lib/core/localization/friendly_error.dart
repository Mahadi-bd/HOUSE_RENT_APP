import 'package:rent_solution/core/localization/generated/app_localizations.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';
import 'package:rent_solution/core/security/vault_crypto.dart';
import 'package:rent_solution/features/ocr/domain/ocr_engine.dart';

/// A plain-language message for an error, in the app language. Details go to the log, not the screen.
String friendlyError(AppLocalizations t, Object error) {
  if (error is PermissionDenied) {
    return t.errorNoPermission;
  }
  final text = error.toString();
  if (text.contains('already recorded') ||
      (text.contains('UNIQUE constraint failed') && text.contains('trx_id'))) {
    return t.errorDuplicateTrx;
  }
  if (text.contains('already has an active tenant')) {
    return t.errorUnitTaken;
  }
  if (text.contains('UNIQUE constraint failed') && text.contains('unit_no')) {
    return t.errorDuplicateUnit;
  }
  if (error is OcrUnavailableException) {
    return t.ocrFailed;
  }
  if (error is DocumentTamperedException) {
    return t.errorTampered;
  }
  if (error is VaultKeyMissingException) {
    return t.errorVaultKey;
  }
  if (error is ConfirmationException) {
    switch (error.reason) {
      case 'offline':
        return t.errorConfirmOffline;
      case 'invalid_link':
        return t.errorConfirmLink;
      case 'expired':
        return t.errorConfirmExpired;
      case 'wrong_account':
        return t.errorConfirmAccount;
      default:
        return t.errorConfirmGeneric;
    }
  }
  return t.errorGeneric;
}

/// Labels for payment methods and charge kinds.
extension EnumLabels on AppLocalizations {
  /// Label for a payment method name (`cash`, `bkash`, `nagad`, `rocket`, `bank`, `qr`).
  String methodName(String name) {
    switch (name) {
      case 'bkash':
        return methodBkash;
      case 'nagad':
        return methodNagad;
      case 'rocket':
        return methodRocket;
      case 'bank':
        return methodBank;
      case 'qr':
        return methodQr;
      default:
        return methodCash;
    }
  }

  /// Label for a charge kind name.
  String chargeName(String name) {
    switch (name) {
      case 'electricity':
        return chargeElectricity;
      case 'gas':
        return chargeGas;
      case 'water':
        return chargeWater;
      case 'internet':
        return chargeInternet;
      case 'fine':
        return chargeFine;
      case 'damage':
        return chargeDamage;
      default:
        return chargeOther;
    }
  }
}
