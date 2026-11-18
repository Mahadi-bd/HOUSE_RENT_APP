# Offline authorization lease (PROPOSAL, needs the Owner's approval before any code)

## The honest limits
- A phone that is offline cannot receive a revoke or suspend command. Nothing can reach it.
- Data already downloaded to a phone stays on that phone. The app cannot remotely erase an offline
  or compromised device. Any "remote wipe" only runs when the phone next goes online AND the app
  is not tampered with.
- Key rotation protects the FUTURE: after a revoke, the organization key (and the vault key if
  needed) changes, and the new key is shared only with remaining members. The revoked device cannot
  decrypt anything created after the rotation.
- Key rotation does NOT erase anything the revoked device already decrypted or stored, and it cannot
  stop a person from photographing or copying what they could already see.

## What a lease is
Each member phone holds an "authorization lease": a time limit that renews every time the phone
successfully checks its membership status on the server. If the lease runs out while offline, the app
locks itself and asks the person to go online. Locked data stays encrypted in the local database
(the database key is in Keystore/Keychain); it is not deleted.

The lease is enforced by the app. A rooted phone or a changed system clock can weaken it. It is a
safety net for honest mistakes (lost phone, ex-employee who stays offline), not a guarantee.

## When a revoke takes effect
| Situation | Effect |
|---|---|
| Server (Firestore) | Immediately. Rules refuse every read and write from that member. |
| Member phone, online | On its next sync or app open (seconds to minutes): the app sees "revoked", locks, deletes the local organization data and keys. |
| Member phone, offline | Not until it goes online, or until its lease ends (then the app locks). The data on it stays until then. |
| Phone that never goes online again | Stays as it was, locked after the lease only if the app is untampered. |

## What stays in a member's local database
- Manager and Caretaker phones: basic data only (names, units, bills, payments they may see). They never receive
  vault data (NID, address, agreement, household IDs) unless an Admin approved vault access.
- Tenant phone: only their own records.
- Owner/Admin phones: everything, including the vault.
This is why vault access is approved per person and why staff phones should hold as little as possible.

## Proposed durations (Owner chooses)
| Role | Proposed lease | Why |
|---|---|---|
| Admin | 14 days | Holds vault data; renews on any online use. |
| Manager | 7 days | Daily work; short lease limits exposure. |
| Caretaker | 7 days | Same. |
| Tenant | 30 days | Only own records; low risk; may be offline for weeks. |
| Owner | none | The Owner's phone is the source of truth; backups protect it. |

Other extra protections to switch on: sync window for staff phones (for example only the last 3 months),
screen-capture block, PIN or biometric lock, and an Admin button "Revoke now" that also rotates keys.

## Decision needed from the Owner
Approve or change the durations above (or say "shorter" / "longer"). Nothing is implemented until you answer.
