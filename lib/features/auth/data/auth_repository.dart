import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rent_solution/core/constants/app_constants.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';

/// A sign-in problem with a short machine-readable reason.
class AuthFailure implements Exception {
  /// Creates a failure with [reason].
  const AuthFailure(this.reason);

  /// Short reason such as `missing_id_token` or `invalid_link`.
  final String reason;

  @override
  String toString() => 'AuthFailure($reason)';
}

/// Wraps Firebase Auth and Google Sign-In. Firebase is used for sign-in only.
class AuthRepository {
  /// Creates the repository. Pass fakes in tests.
  AuthRepository({FirebaseAuth? auth, GoogleSignIn? google, KeyValueStore? store})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn.instance,
        _store = store ?? const SecureKeyValueStore();

  final KeyValueStore _store;
  static const _pendingEmailKey = 'pending_signin_email_v1';

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  bool _googleReady = false;

  static const _appId = AppConstants.applicationId;
  static const _linkUrl = 'https://${AppConstants.firebaseProjectId}.firebaseapp.com';

  /// Emits the signed-in user, or null when signed out.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// The signed-in user right now, if any.
  User? get currentUser => _auth.currentUser;

  /// Signs in with a Google account.
  Future<void> signInWithGoogle() async {
    if (!_googleReady) {
      await _google.initialize();
      _googleReady = true;
    }
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('missing_id_token');
    }
    await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  /// Emails a sign-in link. This replaces numeric email codes (they need a paid backend).
  Future<void> sendEmailLink(String email) async {
    await _store.write(_pendingEmailKey, email.trim());
    await _auth.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: ActionCodeSettings(
        url: _linkUrl,
        handleCodeInApp: true,
        androidPackageName: _appId,
        androidInstallApp: true,
        androidMinimumVersion: '23',
        iOSBundleId: _appId,
      ),
    );
  }

  /// Finishes email-link sign-in with the full link the user pasted.
  Future<void> signInWithEmailLink({required String email, required String link}) async {
    if (!_auth.isSignInWithEmailLink(link)) {
      throw const AuthFailure('invalid_link');
    }
    await _auth.signInWithEmailLink(email: email, emailLink: link);
  }

  /// Finishes email-link sign-in with a link that opened the app, using the email it was sent to.
  Future<void> completeSignInFromLink(String link) async {
    final email = await _store.read(_pendingEmailKey);
    if (email == null || email.isEmpty) {
      throw const AuthFailure('no_pending_email');
    }
    await signInWithEmailLink(email: email, link: link);
  }

  /// Signs out of Firebase and Google.
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _google.signOut();
    } on Object {
      // Google may not be initialised if the user signed in by email link.
    }
  }
}

/// The auth repository.
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

/// The signed-in Firebase user (null when signed out).
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// What the sign-in screen should tell the person.
enum SignInNotice { none, linkSent }

/// Runs sign-in actions and exposes loading, success and error states.
class SignInController extends Notifier<AsyncValue<SignInNotice>> {
  @override
  AsyncValue<SignInNotice> build() => const AsyncData(SignInNotice.none);

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Google sign-in.
  Future<void> google() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.signInWithGoogle();
      return SignInNotice.none;
    });
  }

  /// Sends the email link.
  Future<void> sendLink(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.sendEmailLink(email);
      return SignInNotice.linkSent;
    });
  }

  /// Completes sign-in with a link that opened the app.
  Future<void> completeFromInbox(String link) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.completeSignInFromLink(link);
      return SignInNotice.none;
    });
  }

  /// Completes email-link sign-in.
  Future<void> completeLink(String email, String link) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.signInWithEmailLink(email: email, link: link);
      return SignInNotice.none;
    });
  }
}

/// Sign-in controller provider.
final signInControllerProvider =
    NotifierProvider<SignInController, AsyncValue<SignInNotice>>(SignInController.new);
