import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/access_guard.dart';
import 'package:rent_solution/core/permissions/permission_matrix.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/data/repositories/org_profile_repository.dart';

import 'helpers.dart';

OrgProfileRepository profileFor(AppDatabase db, MemberAccess? a, [String org = 'org']) =>
    OrgProfileRepository(db, guardFor(a), contextAt(testNow, orgId: org));

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('owner saves the business details printed on receipts; they can be changed again', () async {
    final repo = profileFor(db, ownerAccess);
    expect(await repo.get(), isNull);
    await repo.save(
      displayName: 'LIFE EASY',
      ownerName: 'MAHADI HASAN JEWEL',
      address: 'Khulna',
      phone: '+8801700000000',
      email: 'hello@example.com',
      website: ' ',
      receiptFooter: 'Thank you',
    );
    var p = (await repo.get())!;
    expect(p.displayName, 'LIFE EASY');
    expect(p.ownerName, 'MAHADI HASAN JEWEL');
    expect(p.website, isNull);
    await repo.save(displayName: 'LIFE EASY Ltd', phone: '01800000000');
    p = (await repo.get())!;
    expect(p.displayName, 'LIFE EASY Ltd');
    expect(p.ownerName, isNull);
    expect(await db.select(db.orgProfiles).get(), hasLength(1));
    expect((await db.auditDao.verifyChain('org')).ok, isTrue);
  });

  test('admin can save; manager, caretaker and tenant cannot', () async {
    await profileFor(db, const MemberAccess(role: Role.admin)).save(displayName: 'A');
    for (final role in [Role.manager, Role.caretaker, Role.tenant]) {
      await expectLater(
        profileFor(db, MemberAccess(role: role)).save(displayName: 'Hacked'),
        throwsA(isA<PermissionDenied>()),
      );
    }
    expect((await db.select(db.orgProfiles).getSingle()).displayName, 'A');
  });

  test('staff and tenants can read it for receipts; nobody else', () async {
    await profileFor(db, ownerAccess).save(displayName: 'A');
    for (final role in [Role.caretaker, Role.manager, Role.tenant]) {
      expect((await profileFor(db, MemberAccess(role: role)).get())!.displayName, 'A');
    }
    await expectLater(profileFor(db, null).get(), throwsA(isA<PermissionDenied>()));
  });

  test('a blank name or a bad email is refused', () async {
    final repo = profileFor(db, ownerAccess);
    await expectLater(repo.save(displayName: '  '), throwsArgumentError);
    await expectLater(repo.save(displayName: 'A', email: 'not-an-email'), throwsArgumentError);
    expect(await db.select(db.orgProfiles).get(), isEmpty);
  });

  test('another organization has its own, separate details', () async {
    await profileFor(db, ownerAccess).save(displayName: 'Mine');
    expect(await profileFor(db, ownerAccess, 'other').get(), isNull);
    await profileFor(db, ownerAccess, 'other').save(displayName: 'Theirs');
    expect((await profileFor(db, ownerAccess).get())!.displayName, 'Mine');
    expect(await db.select(db.orgProfiles).get(), hasLength(2));
  });

  test('a custom logo path can be set and cleared; the details must exist first', () async {
    final repo = profileFor(db, ownerAccess);
    await expectLater(repo.setLogoPath('/x/logo.png'), throwsStateError);
    await repo.save(displayName: 'A');
    await repo.setLogoPath('/x/logo.png');
    expect((await repo.get())!.logoPath, '/x/logo.png');
    await repo.setLogoPath(null);
    expect((await repo.get())!.logoPath, isNull);
    await expectLater(
      profileFor(db, const MemberAccess(role: Role.manager)).setLogoPath('/y.png'),
      throwsA(isA<PermissionDenied>()),
    );
  });

  test('the custom logo path can be set and cleared; needs saved details and settings permission', () async {
    final repo = profileFor(db, ownerAccess);
    await expectLater(repo.setLogoPath('/x/logo.png'), throwsStateError);
    await repo.save(displayName: 'A');
    await repo.setLogoPath('/x/logo.png');
    expect((await repo.get())!.logoPath, '/x/logo.png');
    await repo.setLogoPath(null);
    expect((await repo.get())!.logoPath, isNull);
    await expectLater(
      profileFor(db, const MemberAccess(role: Role.manager)).setLogoPath('/y.png'),
      throwsA(isA<PermissionDenied>()),
    );
  });
}
