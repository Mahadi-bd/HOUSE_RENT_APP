import 'package:rent_solution/core/utils/ids.dart';

/// Actions that need a fresh email confirmation from the signed-in person.
enum SensitiveAction {
  paymentEdit,
  paymentVoid,
  chargeVoid,
  expenseVoid,
  tenantDelete,
  householdRemove,
  documentRemove,
  legalErasure,
}

/// Why a confirmation failed. [reason] is one of: offline, not_signed_in, wrong_account,
/// invalid_link, expired, already_used, invalid, mismatch.
class ConfirmationException implements Exception {
  /// Creates the exception.
  const ConfirmationException(this.reason);

  /// Short machine-readable reason.
  final String reason;

  @override
  String toString() => 'ConfirmationException($reason)';
}

/// Proof that the signed-in person just confirmed ONE action on ONE record.
/// The only way to get one is [ConfirmationService.complete]; no other code can create it
/// (the constructor is private to this library), so a caller can never pass `true` to bypass it.
class ConfirmationToken {
  ConfirmationToken._(this.id, this.uid, this.action, this.entityId, this.expiresAt);

  /// Random id of this token.
  final String id;

  /// The Firebase user who confirmed.
  final String uid;

  /// The action that was confirmed.
  final SensitiveAction action;

  /// The record that was confirmed.
  final String entityId;

  /// After this moment the token no longer works.
  final DateTime expiresAt;
}

/// A confirmation link that was sent and is waiting for the person to paste it back.
class PendingConfirmation {
  PendingConfirmation._(this.id, this.uid, this.email, this.action, this.entityId, this.expiresAt);

  /// Random id of this challenge.
  final String id;

  /// The user the link was requested for.
  final String uid;

  /// The address the link was sent to.
  final String email;

  /// Action being confirmed.
  final SensitiveAction action;

  /// Record being confirmed.
  final String entityId;

  /// After this moment the challenge is dead.
  final DateTime expiresAt;
}

/// Talks to Firebase (or a fake in tests).
abstract interface class ReauthProvider {
  /// Uid of the signed-in user, or null.
  String? get currentUid;

  /// Email of the signed-in user, or null.
  String? get currentEmail;

  /// Sends the confirmation link. Throws [ConfirmationException]('offline') without internet.
  Future<void> sendLink(String email);

  /// Re-authenticates the CURRENT user with the pasted link and returns the uid it confirmed.
  Future<String> reauthenticate({required String email, required String link});
}

/// Issues and checks one-time confirmation tokens.
///
/// Flow: [begin] (sends the email link, remembers the challenge) then [complete] (the person
/// pastes the link; Firebase re-authenticates the current user; a token is minted for exactly
/// that action and record). A repository calls [consume], which checks identity, action, record,
/// expiry and single use. Everything is in memory: closing the app cancels pending confirmations.
class ConfirmationService {
  /// Creates the service. [clock] and [ttl] are for tests.
  ConfirmationService(
    this._provider, {
    DateTime Function()? clock,
    this.challengeTtl = const Duration(minutes: 10),
    this.tokenTtl = const Duration(minutes: 5),
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final ReauthProvider _provider;
  final DateTime Function() _clock;

  /// How long the person has to paste the link.
  final Duration challengeTtl;

  /// How long a minted token can wait before it is used.
  final Duration tokenTtl;

  final Map<String, PendingConfirmation> _pending = {};
  final Map<String, ConfirmationToken> _tokens = {};

  /// Email address the link goes to (shown to the person).
  String? get email => _provider.currentEmail;

  /// Sends a confirmation link for [action] on [entityId]. Blocked while offline.
  Future<PendingConfirmation> begin({
    required SensitiveAction action,
    required String entityId,
  }) async {
    final uid = _provider.currentUid;
    final email = _provider.currentEmail;
    if (uid == null || email == null || email.isEmpty) {
      throw const ConfirmationException('not_signed_in');
    }
    await _provider.sendLink(email);
    final pending = PendingConfirmation._(
      newId(),
      uid,
      email,
      action,
      entityId,
      _clock().add(challengeTtl),
    );
    _pending[pending.id] = pending;
    return pending;
  }

  /// Checks the pasted [link] and returns a single-use token for the pending action.
  Future<ConfirmationToken> complete(PendingConfirmation pending, String link) async {
    final known = _pending[pending.id];
    if (known == null || !identical(known, pending)) {
      throw const ConfirmationException('already_used');
    }
    if (_clock().isAfter(pending.expiresAt)) {
      _pending.remove(pending.id);
      throw const ConfirmationException('expired');
    }
    if (_provider.currentUid != pending.uid) {
      throw const ConfirmationException('wrong_account');
    }
    final confirmedUid = await _provider.reauthenticate(email: pending.email, link: link.trim());
    if (confirmedUid != pending.uid) {
      throw const ConfirmationException('wrong_account');
    }
    _pending.remove(pending.id);
    final token = ConfirmationToken._(
      newId(),
      pending.uid,
      pending.action,
      pending.entityId,
      _clock().add(tokenTtl),
    );
    _tokens[token.id] = token;
    return token;
  }

  /// Accepts [token] once, only for [action] on [entityId], only for the same signed-in user,
  /// only before it expires. Throws [ConfirmationException] otherwise.
  void consume(
    ConfirmationToken token, {
    required SensitiveAction action,
    required String entityId,
  }) {
    final issued = _tokens[token.id];
    if (issued == null || !identical(issued, token)) {
      throw const ConfirmationException('invalid');
    }
    if (token.action != action || token.entityId != entityId) {
      throw const ConfirmationException('mismatch');
    }
    if (token.uid != _provider.currentUid) {
      _tokens.remove(token.id);
      throw const ConfirmationException('wrong_account');
    }
    if (_clock().isAfter(token.expiresAt)) {
      _tokens.remove(token.id);
      throw const ConfirmationException('expired');
    }
    _tokens.remove(token.id);
  }

  /// Forgets everything (call on sign-out).
  void clear() {
    _pending.clear();
    _tokens.clear();
  }
}
