// Firestore security rules tests (rules v3: scoped operations). Run with `npm test` in this folder.
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

const SCOPE = {
  org: { scopeType: 'org', scopeId: ORG },
  vault: { scopeType: 'vault', scopeId: ORG },
  p1: { scopeType: 'property', scopeId: 'p1' },
  p2: { scopeType: 'property', scopeId: 'p2' },
  t1: { scopeType: 'tenant', scopeId: 't1', propertyId: 'p1' },
  t2: { scopeType: 'tenant', scopeId: 't2', propertyId: 'p2' },
};

const opData = (sender, scope = 'org', over = {}) => ({
  senderUid: sender,
  deviceId: 'dev1',
  entityType: 'payment',
  entityId: 'e1',
  hlc: '001700000000000-0000-dev1',
  ...SCOPE[scope],
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
const opRef = (db, id) => doc(db, `orgs/${ORG}/ops/${id}`);
const memberRef = (db, uid) => doc(db, `orgs/${ORG}/members/${uid}`);
const orgRef = (db) => doc(db, `orgs/${ORG}`);
const grantRef = (db, uid) => doc(db, `orgs/${ORG}/grants/${uid}`);
const grant = (uid, epoch) => ({ recipientUid: uid, epoch, bundle: 'YnVuZGxl', updatedAt: serverTimestamp() });

/** A revoke/suspend batch WITH key rotation (org epoch +1 and the admin's new bundle). */
function rotatingBatch(db, adminUid, epoch, build) {
  const batch = writeBatch(db);
  build(batch);
  batch.update(orgRef(db), { keyVersion: epoch });
  batch.set(grantRef(db, adminUid), grant(adminUid, epoch));
  return batch;
}

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
    await setDoc(orgRef(db), { ownerUid: 'owner', name: 'Org', keyVersion: 1, createdAt: Timestamp.now() });
    const member = (uid, role, extra = {}) =>
      setDoc(memberRef(db, uid), { role, status: 'active', vaultAccess: false, createdAt: Timestamp.now(), ...extra });
    await member('owner', 'owner', { vaultAccess: true });
    await member('admin', 'admin', { vaultAccess: true });
    await member('manager', 'manager'); // empty scope = every property
    await member('caretaker', 'caretaker');
    await member('tenant', 'tenant', { linkedTenantId: 't1' });
    await member('mgrP1', 'manager', { propertyScope: ['p1'] });
    await member('careP1', 'caretaker', { propertyScope: ['p1'] });
    await member('suspended', 'manager', { status: 'suspended' });
    await member('revoked', 'manager', { status: 'revoked' });
    await member('vaultmgr', 'manager', { vaultAccess: true });
    for (const [id, scope] of [['org1', 'org'], ['vault1', 'vault'], ['prop1', 'p1'], ['prop2', 'p2'], ['ten1', 't1'], ['ten2', 't2']]) {
      await setDoc(opRef(db, id), opData('owner', scope));
    }
    await setDoc(doc(db, `orgs/${ORG}/invites/inv1`), inviteData());
  });
});

describe('Owner', () => {
  it('reads org, members and every scope', async () => {
    const db = as('owner');
    await assertSucceeds(getDoc(orgRef(db)));
    await assertSucceeds(getDoc(memberRef(db, 'admin')));
    for (const id of ['org1', 'vault1', 'prop1', 'prop2', 'ten1', 'ten2']) {
      await assertSucceeds(getDoc(opRef(db, id)));
    }
  });
  it('can rename, and rotate the key only with its own new bundle', async () => {
    const db = as('owner');
    await assertSucceeds(updateDoc(orgRef(db), { name: 'New name' }));
    await assertFails(updateDoc(orgRef(db), { keyVersion: 2 }));
    const batch = writeBatch(db);
    batch.update(orgRef(db), { keyVersion: 2 });
    batch.set(grantRef(db, 'owner'), grant('owner', 2));
    await assertSucceeds(batch.commit());
  });
  it('cannot change ownerUid, jump key versions, or delete the org', async () => {
    const db = as('owner');
    await assertFails(updateDoc(orgRef(db), { ownerUid: 'admin' }));
    await assertFails(updateDoc(orgRef(db), { keyVersion: 5 }));
    await assertFails(deleteDoc(orgRef(db)));
  });
  it('can invite an admin and a manager', async () => {
    const db = as('owner');
    await assertSucceeds(setDoc(doc(db, `orgs/${ORG}/invites/i2`), inviteData({ role: 'admin', createdBy: 'owner', createdAt: serverTimestamp() })));
    await assertSucceeds(setDoc(doc(db, `orgs/${ORG}/invites/i3`), inviteData({ createdBy: 'owner', createdAt: serverTimestamp() })));
  });
  it('can promote a manager to admin; the owner membership can never change', async () => {
    const db = as('owner');
    await assertSucceeds(updateDoc(memberRef(db, 'manager'), { role: 'admin' }));
    await assertFails(updateDoc(memberRef(db, 'owner'), { role: 'admin' }));
    await assertFails(updateDoc(memberRef(db, 'owner'), { status: 'suspended' }));
    await assertFails(deleteDoc(memberRef(db, 'owner')));
  });
});

describe('Admin', () => {
  it('reads org, members and vault records', async () => {
    const db = as('admin');
    await assertSucceeds(getDoc(orgRef(db)));
    await assertSucceeds(getDocs(collection(db, `orgs/${ORG}/members`)));
    await assertSucceeds(getDoc(opRef(db, 'vault1')));
    await assertSucceeds(getDoc(opRef(db, 'ten2')));
  });
  it('can grant vault access (no rotation needed for GIVING access)', async () => {
    await assertSucceeds(updateDoc(memberRef(as('admin'), 'caretaker'), { vaultAccess: true }));
  });
  it('CANNOT promote anyone to Owner', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'manager'), { role: 'owner' }));
    await assertFails(updateDoc(memberRef(db, 'admin'), { role: 'owner' }));
  });
  it('cannot promote someone to admin, nor touch another admin or the owner', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'manager'), { role: 'admin' }));
    await assertFails(updateDoc(memberRef(db, 'owner'), { status: 'suspended' }));
  });
  it('cannot change its own membership', async () => {
    await assertFails(updateDoc(memberRef(as('admin'), 'admin'), { vaultAccess: false }));
  });
  it('cannot add members directly (membership only through an invitation)', async () => {
    const db = as('admin');
    await assertFails(setDoc(memberRef(db, 'ghost'), { role: 'owner', status: 'active', vaultAccess: true, createdAt: serverTimestamp() }));
    await assertFails(setDoc(memberRef(db, 'ghost'), { role: 'manager', status: 'active', vaultAccess: false, createdAt: serverTimestamp() }));
  });
  it('cannot invite an owner or an admin, but can invite a manager', async () => {
    const db = as('admin');
    const base = { createdBy: 'admin', createdAt: serverTimestamp() };
    await assertFails(setDoc(doc(db, `orgs/${ORG}/invites/x1`), inviteData({ ...base, role: 'owner' })));
    await assertFails(setDoc(doc(db, `orgs/${ORG}/invites/x2`), inviteData({ ...base, role: 'admin' })));
    await assertSucceeds(setDoc(doc(db, `orgs/${ORG}/invites/x3`), inviteData({ ...base, propertyScope: ['p1'] })));
  });
  it('a tenant invitation must name the tenant record', async () => {
    const db = as('admin');
    const base = { createdBy: 'admin', createdAt: serverTimestamp(), role: 'tenant' };
    await assertFails(setDoc(doc(db, `orgs/${ORG}/invites/x4`), inviteData(base)));
    await assertSucceeds(setDoc(doc(db, `orgs/${ORG}/invites/x5`), inviteData({ ...base, linkedTenantId: 't9' })));
  });
  it('cannot rename the org or change its owner', async () => {
    const db = as('admin');
    await assertFails(updateDoc(orgRef(db), { name: 'Hacked' }));
    await assertFails(updateDoc(orgRef(db), { ownerUid: 'admin' }));
  });
  it('cannot revive a revoked member, or add unknown fields', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'revoked'), { status: 'active' }));
    await assertFails(updateDoc(memberRef(db, 'manager'), { isSuperUser: true }));
  });
  it('resuming a suspended member does not need a key rotation', async () => {
    await assertSucceeds(updateDoc(memberRef(as('admin'), 'suspended'), { status: 'active' }));
  });
});

describe('Revocation needs key rotation (atomic)', () => {
  it('revoke or suspend WITHOUT rotation is rejected', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'manager'), { status: 'revoked' }));
    await assertFails(updateDoc(memberRef(db, 'manager'), { status: 'suspended' }));
    const batch = writeBatch(db);
    batch.update(memberRef(db, 'manager'), { status: 'revoked' });
    await assertFails(batch.commit());
  });
  it('revoke + epoch +1 + the admin bundle in ONE commit succeeds', async () => {
    const db = as('admin');
    await assertSucceeds(rotatingBatch(db, 'admin', 2, (b) => b.update(memberRef(db, 'manager'), { status: 'revoked' })).commit());
  });
  it('suspend with rotation succeeds', async () => {
    const db = as('admin');
    await assertSucceeds(rotatingBatch(db, 'admin', 2, (b) => b.update(memberRef(db, 'caretaker'), { status: 'suspended' })).commit());
  });
  it('rotation without the bundle, with a wrong epoch, or jumping two epochs is rejected', async () => {
    const db = as('admin');
    const noBundle = writeBatch(db);
    noBundle.update(memberRef(db, 'manager'), { status: 'revoked' });
    noBundle.update(orgRef(db), { keyVersion: 2 });
    await assertFails(noBundle.commit());

    const wrongEpoch = writeBatch(db);
    wrongEpoch.update(memberRef(db, 'manager'), { status: 'revoked' });
    wrongEpoch.update(orgRef(db), { keyVersion: 2 });
    wrongEpoch.set(grantRef(db, 'admin'), grant('admin', 3));
    await assertFails(wrongEpoch.commit());

    await assertFails(rotatingBatch(db, 'admin', 3, (b) => b.update(memberRef(db, 'manager'), { status: 'revoked' })).commit());
  });
  it('removing vault access or narrowing a property scope also needs rotation', async () => {
    const db = as('admin');
    await assertFails(updateDoc(memberRef(db, 'vaultmgr'), { vaultAccess: false }));
    await assertFails(updateDoc(memberRef(db, 'mgrP1'), { propertyScope: ['p2'] }));
    await assertSucceeds(rotatingBatch(db, 'admin', 2, (b) => b.update(memberRef(db, 'vaultmgr'), { vaultAccess: false })).commit());
  });
  it('after the rotation only the NEW key version can write operations', async () => {
    const db = as('admin');
    await assertSucceeds(rotatingBatch(db, 'admin', 2, (b) => b.update(memberRef(db, 'manager'), { status: 'revoked' })).commit());
    await assertFails(setDoc(opRef(as('caretaker'), 'old'), opData('caretaker', 'org')));
    await assertSucceeds(setDoc(opRef(as('caretaker'), 'new'), opData('caretaker', 'org', { keyVersion: 2 })));
  });
  it('the revoked member is locked out at once', async () => {
    const adminDb = as('admin');
    await assertSucceeds(rotatingBatch(adminDb, 'admin', 2, (b) => b.update(memberRef(adminDb, 'manager'), { status: 'revoked' })).commit());
    const db = as('manager');
    await assertFails(getDoc(orgRef(db)));
    await assertFails(getDoc(opRef(db, 'org1')));
    await assertSucceeds(getDoc(memberRef(db, 'manager')));
  });
});

describe('Key grants (wrapped keys)', () => {
  it('a member reads only their own bundle', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(grantRef(ctx.firestore(), 'manager'), { recipientUid: 'manager', epoch: 1, bundle: 'eA==', updatedAt: Timestamp.now() });
    });
    await assertSucceeds(getDoc(grantRef(as('manager'), 'manager')));
    await assertFails(getDoc(grantRef(as('caretaker'), 'manager')));
    await assertFails(getDoc(grantRef(as('stranger'), 'manager')));
  });
  it('only an admin writes bundles, only for an active member, only at the current epoch', async () => {
    await assertSucceeds(setDoc(grantRef(as('admin'), 'manager'), grant('manager', 1)));
    await assertFails(setDoc(grantRef(as('admin'), 'revoked'), grant('revoked', 1)));
    await assertFails(setDoc(grantRef(as('admin'), 'manager'), grant('manager', 7)));
    await assertFails(setDoc(grantRef(as('manager'), 'manager'), grant('manager', 1)));
    await assertFails(setDoc(grantRef(as('tenant'), 'tenant'), grant('tenant', 1)));
  });
});

describe('Scopes: who may read and write which operations', () => {
  it('unscoped manager and caretaker read org, every property and every tenant record', async () => {
    for (const uid of ['manager', 'caretaker']) {
      const db = as(uid);
      for (const id of ['org1', 'prop1', 'prop2', 'ten1', 'ten2']) {
        await assertSucceeds(getDoc(opRef(db, id)));
      }
      await assertFails(getDoc(opRef(db, 'vault1')));
    }
  });
  it('a manager scoped to property p1 cannot access p2 or its tenants', async () => {
    const db = as('mgrP1');
    await assertSucceeds(getDoc(opRef(db, 'prop1')));
    await assertSucceeds(getDoc(opRef(db, 'ten1')));
    await assertFails(getDoc(opRef(db, 'prop2')));
    await assertFails(getDoc(opRef(db, 'ten2')));
    await assertFails(getDoc(opRef(db, 'vault1')));
  });
  it('a caretaker scoped to property p1 cannot access p2 or its tenants', async () => {
    const db = as('careP1');
    await assertSucceeds(getDoc(opRef(db, 'prop1')));
    await assertFails(getDoc(opRef(db, 'prop2')));
    await assertFails(getDoc(opRef(db, 'ten2')));
  });
  it('queries must stay inside the member scope', async () => {
    const db = as('mgrP1');
    await assertSucceeds(getDocs(query(opsOf(db), where('scopeType', '==', 'property'), where('scopeId', '==', 'p1'))));
    await assertFails(getDocs(query(opsOf(db), where('scopeType', '==', 'property'), where('scopeId', '==', 'p2'))));
    await assertFails(getDocs(opsOf(db)));
  });
  it('a tenant reads only its OWN tenant record and the organization data, not other tenants or properties', async () => {
    const db = as('tenant');
    await assertSucceeds(getDoc(opRef(db, 'ten1')));
    await assertSucceeds(getDoc(opRef(db, 'org1')));
    await assertFails(getDoc(opRef(db, 'ten2')));
    await assertFails(getDoc(opRef(db, 'prop1')));
    await assertFails(getDoc(opRef(db, 'vault1')));
    await assertSucceeds(getDocs(query(opsOf(db), where('scopeType', '==', 'tenant'), where('scopeId', '==', 't1'))));
    await assertFails(getDocs(query(opsOf(db), where('scopeType', '==', 'tenant'), where('scopeId', '==', 't2'))));
  });
  it('a tenant can write only its own tenant record, never organization data', async () => {
    const db = as('tenant');
    await assertSucceeds(setDoc(opRef(db, 'tw1'), opData('tenant', 't1')));
    await assertFails(setDoc(opRef(db, 'tw2'), opData('tenant', 't2')));
    await assertFails(setDoc(opRef(db, 'tw3'), opData('tenant', 'org')));
    await assertFails(setDoc(opRef(db, 'tw4'), opData('tenant', 'p1')));
  });
  it('a scoped manager cannot write into another property or tenant', async () => {
    const db = as('mgrP1');
    await assertSucceeds(setDoc(opRef(db, 'w1'), opData('mgrP1', 'p1')));
    await assertSucceeds(setDoc(opRef(db, 'w2'), opData('mgrP1', 't1')));
    await assertFails(setDoc(opRef(db, 'w3'), opData('mgrP1', 'p2')));
    await assertFails(setDoc(opRef(db, 'w4'), opData('mgrP1', 't2')));
    await assertFails(setDoc(opRef(db, 'w5'), opData('mgrP1', 'vault')));
  });
  it('a tenant-scoped record must name its property', async () => {
    const db = as('manager');
    await assertSucceeds(setDoc(opRef(db, 'ok1'), opData('manager', 't1')));
    const missingProperty = opData('manager', 't1');
    delete missingProperty.propertyId;
    await assertFails(setDoc(opRef(db, 'bad1'), missingProperty));
  });
  it('org and vault records must use the organization id as scope id', async () => {
    const db = as('admin');
    await assertSucceeds(setDoc(opRef(db, 'v1'), opData('admin', 'vault')));
    await assertFails(setDoc(opRef(db, 'v2'), opData('admin', 'vault', { scopeId: 'something-else' })));
    await assertFails(setDoc(opRef(db, 'o2'), opData('admin', 'org', { scopeId: 'something-else' })));
  });
});

describe('Vault isolation', () => {
  it('without vault access: no read, no write', async () => {
    const db = as('manager');
    await assertFails(getDoc(opRef(db, 'vault1')));
    await assertFails(setDoc(opRef(db, 'v1'), opData('manager', 'vault')));
    await assertFails(getDocs(query(opsOf(db), where('scopeType', '==', 'vault'))));
  });
  it('with approved vault access: read and write', async () => {
    const db = as('vaultmgr');
    await assertSucceeds(getDoc(opRef(db, 'vault1')));
    await assertSucceeds(getDocs(query(opsOf(db), where('scopeType', '==', 'vault'))));
    await assertSucceeds(setDoc(opRef(db, 'v2'), opData('vaultmgr', 'vault')));
  });
});

describe('Operations are immutable and validated', () => {
  const put = (id, over, scope = 'org') => setDoc(opRef(as('manager'), id), opData('manager', scope, over));
  it('accepts a valid record', async () => assertSucceeds(put('ok1', {})));
  it('nobody edits or deletes operations', async () => {
    for (const uid of ['manager', 'admin', 'owner']) {
      await assertFails(updateDoc(opRef(as(uid), 'org1'), { ciphertext: 'eA==' }));
      await assertFails(deleteDoc(opRef(as(uid), 'org1')));
    }
  });
  it('rejects forged sender, oversized ciphertext, wrong key version', async () => {
    await assertFails(put('f1', { senderUid: 'owner' }));
    await assertFails(put('big', { ciphertext: 'a'.repeat(200001) }));
    await assertFails(put('kv', { keyVersion: 7 }));
  });
  it('rejects expiry beyond 30 days or in the past', async () => {
    await assertFails(put('e1', { expireAt: Timestamp.fromMillis(Date.now() + 40 * DAY) }));
    await assertFails(put('e2', { expireAt: Timestamp.fromMillis(Date.now() - 1000) }));
  });
  it('rejects an unknown scope type, extra fields, a client-made timestamp, short nonce, empty data', async () => {
    await assertFails(put('c1', { scopeType: 'secret' }));
    await assertFails(put('x1', { extra: 'field' }));
    await assertFails(put('t1', { createdAt: Timestamp.fromMillis(Date.now() - 5 * DAY) }));
    await assertFails(put('n1', { nonce: 'abc' }));
    await assertFails(put('n2', { ciphertext: '' }));
  });
});

describe('Other roles and states', () => {
  it('members read only their own member document and cannot escalate', async () => {
    const db = as('manager');
    await assertSucceeds(getDoc(memberRef(db, 'manager')));
    await assertFails(getDoc(memberRef(db, 'admin')));
    await assertFails(getDocs(collection(db, `orgs/${ORG}/members`)));
    for (const patch of [{ role: 'admin' }, { role: 'owner' }, { vaultAccess: true }, { propertyScope: ['p9'] }]) {
      await assertFails(updateDoc(memberRef(db, 'manager'), patch));
    }
  });
  it('a tenant cannot read members or invites, nor change itself', async () => {
    const db = as('tenant');
    await assertFails(getDocs(collection(db, `orgs/${ORG}/members`)));
    await assertFails(getDoc(doc(db, `orgs/${ORG}/invites/inv1`)));
    await assertFails(updateDoc(memberRef(db, 'tenant'), { linkedTenantId: 't2' }));
  });
  it('suspended and revoked members lose access but can read their own status', async () => {
    for (const uid of ['suspended', 'revoked']) {
      const db = as(uid);
      await assertFails(getDoc(orgRef(db)));
      await assertFails(getDoc(opRef(db, 'org1')));
      await assertFails(setDoc(opRef(db, 'x1'), opData(uid, 'org')));
      await assertSucceeds(getDoc(memberRef(db, uid)));
      await assertFails(updateDoc(memberRef(db, uid), { status: 'active' }));
    }
  });
  it('signed-out visitors and strangers can do nothing', async () => {
    await assertFails(getDoc(opRef(anon(), 'org1')));
    const db = as('stranger');
    await assertFails(getDoc(orgRef(db)));
    await assertFails(getDocs(opsOf(db)));
    await assertFails(setDoc(opRef(db, 'z2'), opData('stranger', 'org')));
    for (const role of ['owner', 'admin', 'manager']) {
      await assertFails(setDoc(memberRef(db, 'stranger'), { role, status: 'active', vaultAccess: true, createdAt: serverTimestamp() }));
    }
  });
});

describe('Invitations carry the scope', () => {
  it('the invited person joins with exactly the invited role, vault flag, scope and tenant link', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/scoped`), inviteData({ propertyScope: ['p1'] }));
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/tenantInv`), inviteData({ role: 'tenant', linkedTenantId: 't1', email: 'tenant2@example.com' }));
    });
    await assertSucceeds(acceptInvite('newbie', 'scoped', { propertyScope: ['p1'] }));
    await assertSucceeds(acceptInvite('tenant2', 'tenantInv', { role: 'tenant', linkedTenantId: 't1' }));
  });
  it('a wider scope, a different tenant link, or no scope is refused', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/scoped`), inviteData({ propertyScope: ['p1'] }));
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/tenantInv`), inviteData({ role: 'tenant', linkedTenantId: 't1' }));
    });
    await assertFails(acceptInvite('newbie', 'scoped', { propertyScope: ['p1', 'p2'] }));
    await assertFails(acceptInvite('newbie', 'scoped', { propertyScope: [] }));
    await assertFails(acceptInvite('newbie', 'scoped', {}));
    await assertFails(acceptInvite('newbie', 'tenantInv', { role: 'tenant', linkedTenantId: 't2' }));
    await assertFails(acceptInvite('newbie', 'inv1', { linkedTenantId: 't1' }));
  });
  it('the invited verified email can join once; others and unverified cannot', async () => {
    await assertFails(acceptInvite('other', 'inv1'));
    const db = as('newbie', { email_verified: false });
    const batch = writeBatch(db);
    batch.update(doc(db, `orgs/${ORG}/invites/inv1`), { status: 'accepted', acceptedBy: 'newbie' });
    batch.set(memberRef(db, 'newbie'), { role: 'manager', status: 'active', vaultAccess: false, inviteId: 'inv1', codeHash: HASH, createdAt: serverTimestamp() });
    await assertFails(batch.commit());
    await assertSucceeds(acceptInvite('newbie', 'inv1'));
  });
  it('wrong code, other role, owner role, vault flag, expired, reused, or no acceptance is refused', async () => {
    await assertFails(acceptInvite('newbie', 'inv1', { codeHash: 'b'.repeat(64) }));
    await assertFails(acceptInvite('newbie', 'inv1', { role: 'admin' }));
    await assertFails(acceptInvite('newbie', 'inv1', { role: 'owner' }));
    await assertFails(acceptInvite('newbie', 'inv1', { vaultAccess: true }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/old`), inviteData({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) }));
    });
    await assertFails(acceptInvite('newbie', 'old'));
    const db = as('newbie');
    await assertFails(setDoc(memberRef(db, 'newbie'), { role: 'manager', status: 'active', vaultAccess: false, inviteId: 'inv1', codeHash: HASH, createdAt: serverTimestamp() }));
    await assertSucceeds(acceptInvite('newbie', 'inv1'));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `orgs/${ORG}/invites/inv1`), inviteData({ status: 'accepted', acceptedBy: 'newbie' }));
    });
    await assertFails(acceptInvite('newbie2', 'inv1'));
  });
});

describe('Organization creation', () => {
  const newOrg = (over = {}) => ({ ownerUid: 'founder', name: 'My Houses', keyVersion: 1, createdAt: serverTimestamp(), ...over });
  const ownerMember = { role: 'owner', status: 'active', vaultAccess: true, createdAt: serverTimestamp() };
  it('a user can create their own organization with an owner membership', async () => {
    const db = as('founder');
    const batch = writeBatch(db);
    batch.set(doc(db, 'orgs/new1'), newOrg());
    batch.set(doc(db, 'orgs/new1/members/founder'), ownerMember);
    await assertSucceeds(batch.commit());
  });
  it('cannot create an organization owned by someone else, without membership, or at another key version', async () => {
    const db = as('founder');
    let batch = writeBatch(db);
    batch.set(doc(db, 'orgs/new2'), newOrg({ ownerUid: 'owner' }));
    batch.set(doc(db, 'orgs/new2/members/founder'), ownerMember);
    await assertFails(batch.commit());
    await assertFails(setDoc(doc(db, 'orgs/new3'), newOrg()));
    batch = writeBatch(db);
    batch.set(doc(db, 'orgs/new4'), newOrg({ keyVersion: 5 }));
    batch.set(doc(db, 'orgs/new4/members/founder'), ownerMember);
    await assertFails(batch.commit());
  });
  it('cannot add an owner membership to an organization that already exists', async () => {
    await assertFails(setDoc(memberRef(as('stranger'), 'stranger'), ownerMember));
  });
});
