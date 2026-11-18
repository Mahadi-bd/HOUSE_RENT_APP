import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/security/confirmation_service.dart';

import 'helpers.dart';

void main() {
  late FakeReauthProvider provider;
  late DateTime now;
  late ConfirmationService service;

  setUp(() {
    provider = FakeReauthProvider();
    now = DateTime.utc(2026, 11, 10, 6);
    service = ConfirmationService(provider, clock: () => now);
  });

  Future<ConfirmationToken> mint(SensitiveAction a, String id) async {
    final pending = await service.begin(action: a, entityId: id);
    return service.complete(pending, 'https://link/ok');
  }

  test('begin sends one email link; complete mints a token for that action and record', () async {
    final pending = await service.begin(action: SensitiveAction.paymentVoid, entityId: 'p1');
    expect(provider.linksSent, 1);
    final token = await service.complete(pending, 'https://link/ok');
    expect(token.action, SensitiveAction.paymentVoid);
    expect(token.entityId, 'p1');
    expect(token.uid, 'owner-uid');
    service.consume(token, action: SensitiveAction.paymentVoid, entityId: 'p1');
  });

  test('a token works once only', () async {
    final token = await mint(SensitiveAction.paymentEdit, 'p1');
    service.consume(token, action: SensitiveAction.paymentEdit, entityId: 'p1');
    expect(
      () => service.consume(token, action: SensitiveAction.paymentEdit, entityId: 'p1'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'invalid')),
    );
  });

  test('a token is bound to its action and its record', () async {
    final token = await mint(SensitiveAction.paymentEdit, 'p1');
    expect(
      () => service.consume(token, action: SensitiveAction.paymentVoid, entityId: 'p1'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'mismatch')),
    );
    expect(
      () => service.consume(token, action: SensitiveAction.paymentEdit, entityId: 'p2'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'mismatch')),
    );
    // A wrong attempt does not use the token up.
    service.consume(token, action: SensitiveAction.paymentEdit, entityId: 'p1');
  });

  test('tokens from another service instance are refused', () async {
    final other = ConfirmationService(FakeReauthProvider(), clock: () => now);
    final pending = await other.begin(action: SensitiveAction.tenantDelete, entityId: 't1');
    final foreign = await other.complete(pending, 'https://link/ok');
    expect(
      () => service.consume(foreign, action: SensitiveAction.tenantDelete, entityId: 't1'),
      throwsA(isA<ConfirmationException>()),
    );
  });

  test('offline: no link is sent and no token can exist', () async {
    provider.failWith = 'offline';
    await expectLater(
      service.begin(action: SensitiveAction.chargeVoid, entityId: 'c1'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'offline')),
    );
    expect(provider.linksSent, 0);
  });

  test('not signed in is refused', () async {
    provider.uid = null;
    await expectLater(
      service.begin(action: SensitiveAction.chargeVoid, entityId: 'c1'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'not_signed_in')),
    );
  });

  test('a bad link fails but the person can try again with the right one', () async {
    final pending = await service.begin(action: SensitiveAction.expenseVoid, entityId: 'e1');
    provider.failWith = 'invalid_link';
    await expectLater(
      service.complete(pending, 'garbage'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'invalid_link')),
    );
    provider.failWith = null;
    final token = await service.complete(pending, 'https://link/ok');
    expect(token.entityId, 'e1');
  });

  test('the link must confirm the SAME account', () async {
    final pending = await service.begin(action: SensitiveAction.paymentVoid, entityId: 'p1');
    provider.returnUid = 'someone-else';
    await expectLater(
      service.complete(pending, 'https://link/ok'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'wrong_account')),
    );
  });

  test('signing in as someone else invalidates pending and issued confirmations', () async {
    final token = await mint(SensitiveAction.paymentVoid, 'p1');
    provider.uid = 'another-user';
    expect(
      () => service.consume(token, action: SensitiveAction.paymentVoid, entityId: 'p1'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'wrong_account')),
    );
  });

  test('the challenge expires after 10 minutes and the token after 5', () async {
    final pending = await service.begin(action: SensitiveAction.paymentVoid, entityId: 'p1');
    now = now.add(const Duration(minutes: 11));
    await expectLater(
      service.complete(pending, 'https://link/ok'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'expired')),
    );

    now = DateTime.utc(2026, 11, 10, 7);
    final token = await mint(SensitiveAction.paymentVoid, 'p2');
    now = now.add(const Duration(minutes: 6));
    expect(
      () => service.consume(token, action: SensitiveAction.paymentVoid, entityId: 'p2'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'expired')),
    );
  });

  test('a challenge can be completed only once', () async {
    final pending = await service.begin(action: SensitiveAction.paymentVoid, entityId: 'p1');
    await service.complete(pending, 'https://link/ok');
    await expectLater(
      service.complete(pending, 'https://link/ok'),
      throwsA(isA<ConfirmationException>().having((e) => e.reason, 'reason', 'already_used')),
    );
  });

  test('clear() forgets everything', () async {
    final token = await mint(SensitiveAction.paymentVoid, 'p1');
    service.clear();
    expect(
      () => service.consume(token, action: SensitiveAction.paymentVoid, entityId: 'p1'),
      throwsA(isA<ConfirmationException>()),
    );
  });
}
