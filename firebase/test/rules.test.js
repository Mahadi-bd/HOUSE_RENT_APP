// Firestore security rules tests. Run with `npm test` in this folder (needs the Firebase emulator).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const ORG = 'org1';
const DAY = 86400000;
const HASH = 'a'.repeat(64);
let env;

const opData = (sender, channel, over = {}) => ({
  senderUid: sender,
  deviceId: 'dev1',
  entityType: 'payment',
  entityId: 'p1',
  hlc: '001700000000000-0000-dev1',
  channel,
  keyVersion: 1,
  nonce: 'bm9uY2Vub25jZTEy',
  ciphertext: 'Y2lwaGVydGV4dA==',
  createdAt: serverTimestamp(),
  expireAt: Timestamp.fromMillis(Date.now() + 7 * DAY),
  ...over,
});

const inviteData = (over = {}) => ({
  email: 'newbie@example.com',
  role: 'manager',
  codeHash: HASH,
  vaultAccess: false,
  status: 'pending',
  createdBy: 'admin',
  createdAt: Timestamp.now(),
  expiresAt: Timestamp.fromMillis(Date.now() + DAY),
  ...over,
});

const as = (uid, claims = {}) =>
  env
    .authenticatedContext(uid, { email: `${uid}@example.com`, email_verified: true, ...claims })
    .firestore();
const anon = () => env.unauthenticatedContext().firestore();
const opsOf = (db) => collection(db, `orgs/${ORG}/ops`);
const memberRef = (db, uid) => doc(db, `orgs/${ORG}/members/${uid}`);

async function acceptInvite(uid, inviteId, member) {
  const db = as(uid);
  const batch = writeBatch(db);
  batch.update(doc(db, `orgs/${ORG}/invites/${inviteId}`), { status: 'accepted', acceptedBy: uid });
  batch.set(memberRef(db, uid), {
    role: 'manager',
    status: 'active',
    vaultAccess: false,
    inviteId,
    codeHash: HASH,
    createdAt: serverTimestamp(),
    ...member,
  });
  return batch.commit();
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'rent-solution-2dd62',
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `orgs/${ORG}`), {
      ownerUid: 'owner',
      name: 'Org',
      keyVersion: 1,
      createdAt: Timestamp.now(),
    });
    const member = (uid, role, status = 'active', vaultAccess = false) =>
      setDoc(memberRef(db, uid), { role, status, vaultAccess, createdAt: Timestamp.now() });
    await member('owner', 'owner', 'active', true);
    await member('admin', 'admin', 'active', true);
    await member('manager', 'manager');
    await member('caretaker', 'caretaker');
    await member('tenant', 'tenant');
    await member('suspended', 'manager', 'suspended');
    await member('revoked', 'manager', 'revoked');
    await member('vaultmgr', 'manager', 'active', true);
    await setDoc(doc(db, `orgs/${ORG}/ops/basic1`), opData('owner', 'basic'));
    await setDoc(doc(db, `orgs/${ORG}/ops/vault1`), opData('owner', 'vault'));
    await setDoc(doc(db, `orgs/${ORG}/invites/inv1`), inviteData());
  });
});

describe('Owner', () => {
  it('reads org, members and both channels', async () => {
    const db = as('owner');
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}`)));
    await assertSucceeds(getDocs(collection(db, `orgs/${ORG}/members`)));
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}/ops/vault1`)));
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
  });
  it('can rename the org and rotate the key by exactly one', async () => {
    const db = as('owner');
    await assertSucceeds(updateDoc(doc(db, `orgs/${ORG}`), { name: 'New name' }));
    await assertSucceeds(updateDoc(doc(db, `orgs/${ORG}`), { keyVersion: 2 }));
  });
  it('cannot change ownerUid, jump key versions, or delete the org', async () => {
    const db = as('owner');
    await assertFails(updateDoc(doc(db, `orgs/${ORG}`), { ownerUid: 'admin' }));
    await assertFails(updateDoc(doc(db, `orgs/${ORG}`), { keyVersion: 5 }));
    await assertFails(deleteDoc(doc(db, `orgs/${ORG}`)));
  });
  it('can invite an admin and a manager', async () => {
    const db = as('owner');
    await assertSucceeds(
      setDoc(doc(db, `orgs/${ORG}/invites/i2`), inviteData({ role: 'admin', createdBy: 'owner', createdAt: serverTimestamp() })),
    );
    await assertSucceeds(
      setDoc(doc(db, `orgs/${ORG}/invites/i3`), inviteData({ createdBy: 'owner', createdAt: serverTimestamp() })),
    );
  });
  it('can suspend and promote an admin (owner-only actions)', async () => {
    const db = as('owner');
    await assertSucceeds(updateDoc(memberRef(db, 'admin'), { status: 'suspended' }));
    await assertSucceeds(updateDoc(memberRef(db, 'manager'), { role: 'admin' }));
  });
  it('cannot edit or remove the owner membership, even as owner', async () => {
    const db = as('owner');
    await assertFails(updateDoc(memberRef(db, 'owner'), { role: 'admin' }));
    await assertFails(updateDoc(memberRef(db, 'owner'), { status: 'suspended' }));
    await assertFails(deleteDoc(memberRef(db, 'owner')));
  });
});

describe('Admin', () => {
  it('reads org, members and vault records', async () => {
    const db = as('admin');
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}`)));
    await assertSucceeds(getDocs(collection(db, `orgs/${ORG}/members`)));
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}/ops/vault1`)));
  });
  it('can suspend a manager, grant vault access, and raise keyVersion by one', async () => {
    const db = as('admin');
    await assertSucceeds(updateDoc(memberRef(db, 'manager'), { status: 'suspended' }));
    await assertSucceeds(updateDoc(memberRef(db, 'caretaker'), { vaultAccess: true }));
    await assertSucceeds(updateDoc(doc(db, `orgs/${ORG}`), { keyVersion: 2 }));
  });
  it('CANNOT promote anyone to Owner', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'manager'), { role: 'owner' }));
    await assertFails(updateDoc(memberRef(db, 'admin'), { role: 'owner' }));
  });
  it('cannot promote someone to admin, and cannot touch another admin or the owner', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'manager'), { role: 'admin' }));
    await assertFails(updateDoc(memberRef(db, 'owner'), { status: 'suspended' }));
    await assertFails(updateDoc(memberRef(db, 'owner'), { role: 'admin' }));
  });
  it('cannot change its own membership', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'admin'), { vaultAccess: false }));
  });
  it('cannot add members directly (membership only through an invitation)', async () => {
    const db = as('admin');
    await assertFails(
      setDoc(memberRef(db, 'ghost'), { role: 'owner', status: 'active', vaultAccess: true, createdAt: serverTimestamp() }),
    );
    await assertFails(
      setDoc(memberRef(db, 'ghost'), { role: 'manager', status: 'active', vaultAccess: false, createdAt: serverTimestamp() }),
    );
  });
  it('cannot invite an owner or an admin, but can invite a manager', async () => {
    const db = as('admin');
    const base = { createdBy: 'admin', createdAt: serverTimestamp() };
    await assertFails(setDoc(doc(db, `orgs/${ORG}/invites/x1`), inviteData({ ...base, role: 'owner' })));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/invites/x2`), inviteData({ ...base, role: 'admin' })));
    await assertSucceeds(setDoc(doc(db, `orgs/${ORG}/invites/x3`), inviteData(base)));
  });
  it('cannot rename the org or change its owner', async () => {
    const db = as('admin');
    await assertFails(updateDoc(doc(db, `orgs/${ORG}`), { name: 'Hacked' }));
    await assertFails(updateDoc(doc(db, `orgs/${ORG}`), { ownerUid: 'admin' }));
  });
  it('cannot revive a revoked member', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'revoked'), { status: 'active' }));
  });
  it('cannot add unknown fields to a member', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'manager'), { isSuperUser: true }));
  });
});

describe('Manager', () => {
  it('reads basic records only; vault read and query are refused', async () => {
    const db = as('manager');
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/ops/vault1`)));
    await assertSucceeds(getDocs(query(opsOf(db), where('channel', '==', 'basic'))));
    await assertFails(getDocs(query(opsOf(db), where('channel', '==', 'vault'))));
    await assertFails(getDocs(opsOf(db)));
  });
  it('can write basic operations as itself, not vault, not as someone else', async () => {
    const db = as('manager');
    await assertSucceeds(setDoc(doc(db, `orgs/${ORG}/ops/m1`), opData('manager', 'basic')));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/m2`), opData('manager', 'vault')));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/m3`), opData('owner', 'basic')));
  });
  it('cannot edit or delete operations', async () => {
    const db = as('manager');
    await assertFails(updateDoc(doc(db, `orgs/${ORG}/ops/basic1`), { ciphertext: 'eA==' }));
    await assertFails(deleteDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
  });
  it('reads only its own member document and cannot escalate', async () => {
    const db = as('manager');
    await assertSucceeds(getDoc(memberRef(db, 'manager')));
    await assertFails(getDoc(memberRef(db, 'admin')));
    await assertFails(getDocs(collection(db, `orgs/${ORG}/members`)));
    await assertFails(updateDoc(memberRef(db, 'manager'), { role: 'admin' }));
    await assertFails(updateDoc(memberRef(db, 'manager'), { role: 'owner' }));
    await assertFails(updateDoc(memberRef(db, 'manager'), { vaultAccess: true }));
  });
  it('cannot invite, read invites, or change the org', async () => {
    const db = as('manager');
    await assertFails(setDoc(doc(db, `orgs/${ORG}/invites/y1`), inviteData({ createdBy: 'manager', createdAt: serverTimestamp() })));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/invites/inv1`)));
    await assertFails(updateDoc(doc(db, `orgs/${ORG}`), { keyVersion: 2 }));
  });
});

describe('Caretaker', () => {
  it('basic only, no member management, no invites', async () => {
    const db = as('caretaker');
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/ops/vault1`)));
    await assertFails(updateDoc(memberRef(db, 'manager'), { status: 'suspended' }));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/invites/y2`), inviteData({ createdBy: 'caretaker', createdAt: serverTimestamp() })));
  });
});

describe('Tenant', () => {
  it('basic only; cannot read vault, members or invites; cannot escalate', async () => {
    const db = as('tenant');
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/ops/vault1`)));
    await assertFails(getDocs(collection(db, `orgs/${ORG}/members`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/invites/inv1`)));
    await assertFails(updateDoc(memberRef(db, 'tenant'), { role: 'owner' }));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/t1`), opData('tenant', 'vault')));
  });
});

describe('Suspended member', () => {
  it('loses access to the org and records but can still read its own status', async () => {
    const db = as('suspended');
    await assertFails(getDoc(doc(db, `orgs/${ORG}`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/s1`), opData('suspended', 'basic')));
    await assertSucceeds(getDoc(memberRef(db, 'suspended')));
  });
  it('cannot re-activate itself', async () => {
    const db = as('suspended');
    await assertFails(updateDoc(memberRef(db, 'suspended'), { status: 'active' }));
  });
});

describe('Revoked member', () => {
  it('loses all access but can read its own status', async () => {
    const db = as('revoked');
    await assertFails(getDoc(doc(db, `orgs/${ORG}`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/r1`), opData('revoked', 'basic')));
    await assertSucceeds(getDoc(memberRef(db, 'revoked')));
  });
  it('cannot re-activate itself', async () => {
    const db = as('revoked');
    await assertFails(updateDoc(memberRef(db, 'revoked'), { status: 'active' }));
  });
});

describe('Unauthorized users', () => {
  it('a signed-out visitor can do nothing', async () => {
    const db = anon();
    await assertFails(getDoc(doc(db, `orgs/${ORG}`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/ops/basic1`)));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/z1`), opData('x', 'basic')));
  });
  it('a signed-in stranger cannot read, write, or make themselves a member', async () => {
    const db = as('stranger');
    await assertFails(getDoc(doc(db, `orgs/${ORG}`)));
    await assertFails(getDocs(opsOf(db)));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/z2`), opData('stranger', 'basic')));
    for (const role of ['owner', 'admin', 'manager']) {
      await assertFails(
        setDoc(memberRef(db, 'stranger'), { role, status: 'active', vaultAccess: true, createdAt: serverTimestamp() }),
      );
    }
  });
});

describe('Vault access', () => {
  it('member WITHOUT vault access cannot read or create vault records', async () => {
    const db = as('manager');
    await assertFails(getDoc(doc(db, `orgs/${ORG}/ops/vault1`)));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/ops/v1`), opData('manager', 'vault')));
  });
  it('member WITH approved vault access can read and create vault records', async () => {
    const db = as('vaultmgr');
    await assertSucceeds(getDoc(doc(db, `orgs/${ORG}/ops/vault1`)));
    await assertSucceeds(getDocs(query(opsOf(db), where('channel', '==', 'vault'))));
    await assertSucceeds(setDoc(doc(db, `orgs/${ORG}/ops/v2`), opData('vaultmgr', 'vault')));
  });
});

describe('Invitations', () => {
  it('the invited verified email can join once, as the invited role', async () => {
    await assertSucceeds(acceptInvite('newbie', 'inv1'));
  });
  it('a different person cannot use the invitation', async () => {
    await assertFails(acceptInvite('other', 'inv1'));
  });
  it('an unverified email cannot use the invitation', async () => {
    const db = as('newbie', { email_verified: false });
    const batch = writeBatch(db);
    batch.update(doc(db, `orgs/${ORG}/invites/inv1`), { status: 'accepted', acceptedBy: 'newbie' });
    batch.set(memberRef(db, 'newbie'), { role: 'manager', status: 'active', vaultAccess: false, inviteId: 'inv1', codeHash: HASH, createdAt: serverTimestamp() });
    await assertFails(batch.commit());
  });
  it('a wrong code, a different role, or owner role is refused', async () => {
    await assertFails(acceptInvite('newbie', 'inv1', { codeHash: 'b'.repeat(64) }));
    await assertFails(acceptInvite('newbie', 'inv1', { role: 'admin' }));
    await assertFails(acceptInvite('newbie', 'inv1', { role: 'owner' }));
    await assertFails(acceptInvite('newbie', 'inv1', { vaultAccess: true }));
  });
  it('an expired invitation is refused', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/old`), inviteData({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }));
    });
    await assertFails(acceptInvite('newbie', 'old'));
  });
  it('an invitation cannot be used twice', async () => {
    await assertSucceeds(acceptInvite('newbie', 'inv1'));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/inv1`), inviteData({ status: 'accepted', acceptedBy: 'newbie' }));
    });
    await assertFails(acceptInvite('newbie2', 'inv1'));
  });
  it('joining without marking the invitation accepted is refused', async () => {
    const db = as('newbie');
    await assertFails(
      setDoc(memberRef(db, 'newbie'), { role: 'manager', status: 'active', vaultAccess: false, inviteId: 'inv1', codeHash: HASH, createdAt: serverTimestamp() }),
    );
  });
});

describe('Organization creation', () => {
  const newOrg = (db, over = {}) => ({
    ownerUid: 'founder',
    name: 'My Houses',
    keyVersion: 1,
    createdAt: serverTimestamp(),
    ...over,
  });
  const ownerMember = { role: 'owner', status: 'active', vaultAccess: true, createdAt: serverTimestamp() };

  it('a user can create their own organization with an owner membership', async () => {
    const db = as('founder');
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs/new1'), newOrg(db));
    batch.set(doc(db, 'orgs/new1/members/founder'), ownerMember);
    await assertSucceeds(batch.commit());
  });
  it('cannot create an organization owned by someone else', async () => {
    const db = as('founder');
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs/new2'), newOrg(db, { ownerUid: 'owner' }));
    batch.set(doc(db, 'orgs/new2/members/founder'), ownerMember);
    await assertFails(batch.commit());
  });
  it('cannot create an organization without the matching owner membership', async () => {
    await assertFails(setDoc(doc(as('founder'), 'orgs/new3'), newOrg(null)));
  });
  it('cannot start at a key version other than 1', async () => {
    const db = as('founder');
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs/new4'), newOrg(db, { keyVersion: 5 }));
    batch.set(doc(db, 'orgs/new4/members/founder'), ownerMember);
    await assertFails(batch.commit());
  });
  it('cannot add an owner membership to an organization that already exists', async () => {
    await assertFails(setDoc(memberRef(as('stranger'), 'stranger'), ownerMember));
  });
});

describe('Operation validation', () => {
  const db = () => as('manager');
  const put = (id, over) => setDoc(doc(db(), `orgs/${ORG}/ops/${id}`), opData('manager', 'basic', over));

  it('accepts a valid record', async () => {
    await assertSucceeds(put('ok1', {}));
  });
  it('rejects oversized ciphertext', async () => {
    await assertFails(put('big', { ciphertext: 'a'.repeat(200001) }));
  });
  it('rejects a wrong key version', async () => {
    await assertFails(put('kv', { keyVersion: 7 }));
  });
  it('rejects expiry beyond 30 days or in the past', async () => {
    await assertFails(put('e1', { expireAt: Timestamp.fromMillis(Date.now() + 40 * DAY) }));
    await assertFails(put('e2', { expireAt: Timestamp.fromMillis(Date.now() - 1000) }));
  });
  it('rejects an unknown channel, extra fields, and a client-made timestamp', async () => {
    await assertFails(put('c1', { channel: 'secret' }));
    await assertFails(put('x1', { extra: 'field' }));
    await assertFails(put('t1', { createdAt: Timestamp.fromMillis(Date.now() - 5 * DAY) }));
  });
  it('rejects a too-short nonce and empty ciphertext', async () => {
    await assertFails(put('n1', { nonce: 'abc' }));
    await assertFails(put('n2', { ciphertext: '' }));
  });
});
