import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/permissions/role.dart';
import 'package:rent_solution/core/security/local_secrets.dart';
import 'package:rent_solution/core/storage/key_value_store.dart';
import 'package:rent_solution/data/local/database.dart';
import 'package:rent_solution/features/organization/data/organization_repository.dart';

void main() {
  late AppDatabase db;
  late OrganizationRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = OrganizationRepository(db, LocalSecrets(store: MemoryKeyValueStore()));
  });
  tearDown(() => db.close());

  test('first sign-in creates the organization, the owner, membership and settings', () async {
    await repo.createOrganization(
      uid: 'firebase-uid-1',
      name: 'Rahim Villa',
      displayName: 'Rahim',
      email: 'rahim@example.com',
      ownerName: 'MAHADI HASAN JEWEL',
    );
    final org = await db.select(db.organizations).getSingle();
    expect(org.name, 'Rahim Villa');
    expect(org.ownerUid, 'firebase-uid-1');
    expect(org.id, org.orgId);

    final member = await db.select(db.memberships).getSingle();
    expect(member.userId, 'firebase-uid-1');
    expect(member.role, Role.owner);
    expect(member.status, MemberStatus.active);
    expect(member.vaultAccess, isTrue);

    expect(await db.select(db.appUsers).get(), hasLength(1));
    expect(await db.select(db.appSettings).get(), hasLength(1));
    final profile = await db.select(db.orgProfiles).getSingle();
    expect(profile.displayName, 'Rahim Villa');
    expect(profile.ownerName, 'MAHADI HASAN JEWEL');
  });

  test('a second owner membership for the same user in the same org is refused', () async {
    await repo.createOrganization(uid: 'u1', name: 'A');
    final org = await db.select(db.organizations).getSingle();
    final existing = await db.select(db.memberships).getSingle();
    await expectLater(
      db.into(db.memberships).insert(
            MembershipsCompanion.insert(
              id: 'dup',
              orgId: org.id,
              createdAt: existing.createdAt,
              updatedAt: existing.updatedAt,
              createdBy: 'u1',
              deviceId: 'd',
              hlc: '1',
              userId: 'u1',
              role: Role.admin,
              status: MemberStatus.active,
            ),
          ),
      throwsA(anything),
    );
  });
}
