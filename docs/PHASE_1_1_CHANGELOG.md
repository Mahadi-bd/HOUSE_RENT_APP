# Phase 1.1 changelog

## Fixed
- Application id: `flutter create --org com.rentsolution --project-name rent_solution` makes `com.rentsolution.rent_solution`. New `tools/set_app_id.sh` sets Android namespace/applicationId, moves MainActivity, sets iOS bundle ids, prints real values. `test/app_identity_test.dart` checks the real files. (Script tested only on a mock layout here.)
- One canonical `tools/setup.sh` (no sqlcipher_flutter_libs, sqlite3mc build hook, FlutterFire with explicit ids).
- Encryption: setup runs before any query, refuses to start without the encrypted build, sets the `sqlcipher` cipher, forces a read so a wrong key fails immediately. Key is 32 bytes of OS secure random in Keystore/Keychain.
- Firestore rules rewritten (see firebase/): no owner promotion, owner document protected, membership only through a single-use email-bound invitation, field-level update checks, vault gating, immutable ops, size/key-version/expiry checks. NOT DEPLOYED, NOT RUN.
- Navigation per Master Prompt v3 (Caretaker: Tickets; Tenant: Home, My Payments, My Tickets, Profile). Unknown routes are denied. Property scope, vault flag, linked tenant record, and `AccessGuard` + `TenantsRepository` for repository-level checks.
- Schema: 27 foreign keys, indexes, unique rules (partial unique for soft-deletable units and memberships), full SyncOps metadata, real Hybrid Logical Clock.
- Audit log: real SHA-256 chain per organization, verification, tamper detection, head hash for truncation detection.
- Language preference persists (Keystore/Keychain store, no new package). BDT/Bengali number and date formatters.

## Not done on purpose
- Phase 2 features, Apple sign-in package, offline lease code, launcher icons package: waiting for approvals.
- Migration tests: schema v1 is the first schema and nothing is released, so there is nothing to migrate from. Add drift schema dumps when v2 appears.

## Not verified (no Flutter, Dart, Firebase CLI or internet here)
Everything that needs them: see the "Status" table in the chat reply and run `tools/verify_phase1_1.sh`.
