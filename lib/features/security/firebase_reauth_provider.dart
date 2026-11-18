import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rent_solution/core/constants/app_constants.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';

/// Real re-authentication with a Firebase email link for the CURRENT user.
class FirebaseReauthProvider implements ReauthProvider {
  /// Creates the provider.
  FirebaseReauthProvider({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  Future<void> sendLink(String email) async {
    try {
      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://${AppConstants.firebaseProjectId}.firebaseapp.com',
          handleCodeInApp: true,
          androidPackageName: AppConstants.applicationId,
          androidInstallApp: true,
          androidMinimumVersion: '23',
          iOSBundleId: AppConstants.applicationId,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        throw const ConfirmationException('offline');
      }
      rethrow;
    }
  }

  @override
  Future<String> reauthenticate({required String email, required String link}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const ConfirmationException('not_signed_in');
    }
    if (!_auth.isSignInWithEmailLink(link)) {
      throw const ConfirmationException('invalid_link');
    }
    try {
      final credential = EmailAuthProvider.credentialWithLink(email: email, emailLink: link);
      final result = await user.reauthenticateWithCredential(credential);
      final uid = result.user?.uid;
      if (uid == null) {
        throw const ConfirmationException('wrong_account');
      }
      return uid;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'network-request-failed':
          throw const ConfirmationException('offline');
        case 'invalid-action-code':
        case 'expired-action-code':
        case 'invalid-email':
          throw const ConfirmationException('invalid_link');
        case 'user-mismatch':
          throw const ConfirmationException('wrong_account');
        default:
          rethrow;
      }
    }
  }
}

/// The confirmation service shared by the whole app (one set of pending challenges).
final confirmationServiceProvider = Provider<ConfirmationService>(
  (ref) => ConfirmationService(FirebaseReauthProvider()),
);
