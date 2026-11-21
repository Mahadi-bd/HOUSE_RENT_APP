# Scoped keys and Firestore rules v3 (must exist before Phase 3 sync)

Status: rules, emulator tests, key crypto and its tests are written. The Firestore rules tests already ran once on your GitHub
(the earlier version); this version has NOT been run yet. The Dart crypto has NOT been compiled yet.

## The idea in one paragraph
The relay (Firestore) only stores encrypted operations. Every operation belongs to a **scope**: `org` (business profile and settings),
`property:<id>`, `tenant:<id>`, or `vault` (private data). Each scope has its own random 256-bit key. A member receives only the keys of the
scopes they may see, wrapped for their own device (X25519 + HKDF + AES-256-GCM). The server rules ALSO refuse to hand out or accept records
outside a member's scope. So a modified app can neither download out-of-scope records (rules) nor read them if it somehow got them (no key).

## Who holds which keys
| Member | Keys |
|---|---|
| Owner, Admin | everything (org, vault, every property, every tenant) |
| Manager, Caretaker, no property list | org, every property, every tenant record; vault only with approved vault access |
| Manager, Caretaker with property list | org, those properties, the tenants living in them; vault only if approved |
| Tenant | org key and its own tenant key only |

## Rules (firebase/firestore.rules)
- Reading or writing an operation needs an active membership AND access to its scope (property list, own tenant, vault access, admin).
- Operations are immutable, size and expiry limited, carry the current key version and the sender's uid.
- A member joins only through a single-use invitation bound to a verified email; role, vault flag, property list and tenant link are copied
  from the invitation, never chosen by the invited person.
- **Anything that takes access away** (suspend, revoke, remove vault access, narrow a property list) must be ONE commit that also raises the
  organization key version by exactly one and writes the acting admin's new key bundle for that epoch. A revoke without rotation is rejected.
- Key bundles (`grants/{uid}`): a member reads only their own; only an admin writes them, only for an active member, only for the current epoch.

## Rotation on revoke (client, `KeyHierarchy.rotate`)
New random keys for every scope at epoch + 1. Each remaining member receives a ring with the new keys of their scopes plus the old keys of the same
scopes (so old data stays readable). The removed member receives nothing.

## What this protects, and what it cannot
- Protects: out-of-scope reading and writing through a modified client; reading anything created AFTER a revocation; a revoke that forgets to rotate keys.
- Cannot: erase what a device already downloaded and decrypted (a revoked or offline phone keeps what it had); stop someone photographing the screen;
  check what an operation says (devices must check the sender's role when applying it; the Admin device is the authority).
- Visible to the server: scope, property id, record kind, sizes and times. Contents are not.
- Grants for an offline member wait in Firestore; the member gets new keys when they next go online. A member who stays offline cannot read new data,
  which is the intended behaviour. The lease durations in `OFFLINE_AUTHORIZATION_POLICY.md` still need your decision.

## Still to build in Phase 3
Storing each member's private key in the Keystore/Keychain, publishing their public key on the member record, creating and applying grants,
the sync applier (must call `observeRemoteHlc`, check sender roles, and run inside a transaction with deferred foreign keys).
