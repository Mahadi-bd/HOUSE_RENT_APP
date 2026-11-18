# Phase 2.1 report: fixes, brand and receipts

**Honest status line:** all of this is source code. It has NOT been compiled, analyzed or run (no Flutter, Dart,
Firebase emulator or internet in the build environment). Static checks that did run: every project import resolves,
brackets balance, all 222 language keys exist in English, Bengali and Hindi, the shell scripts parse, and
`set_app_id.sh` and `patch_pubspec.py` were run against mock project files (idempotent, no leftover .bak files).
Test cases written: 216 Dart + 49 Firestore rules. Run `bash tools/verify_phase1_1.sh` to get the real PASS/FAIL.

## The 13 review points

| # | Item | Status |
|---|---|---|
| 1 | Real email re-authentication | **Done in code.** `ConfirmationService` issues single-use tokens bound to user, action and record, with expiry (10 min to paste, 5 min to use). Repositories take a `ConfirmationToken`, no `bool`. Firebase provider re-authenticates the CURRENT user with the email link and checks the same UID. Offline: nothing is sent and the dialog says "Connect to the internet to confirm this change." **Partial:** the link is pasted by the person; automatic deep-link handling needs the `app_links` package (waiting for your approval). Needs a real-phone test: re-authenticating a Google-signed-in account with an email link depends on Firebase's "one account per email" setting. The binding to action and record is local to the app (Firebase cannot carry it). |
| 2 | Tenant move-out and unit status | **Done.** One transaction: org-scoped fetch, archive snapshot, tenant marked moved out (clock and sync state updated), unit freed only if no other active tenant, audit. Tests: normal, unit vacant, unit stays occupied, other organization, rollback. |
| 3 | TrxID integrity | **Done.** Unique per organization AND provider among non-cancelled payments, enforced by a partial unique index and by checks on record and edit; case-insensitive (stored upper case). `existingTrxIds` lists conflicts for restore/import. Tests: duplicate create, duplicate edit, direct insert, simultaneous insert, cancelled frees the ID. |
| 4 | Payment edit consistency | **Done.** Correction model: balances are always calculated; type, status and month are labels recalculated in order after every edit or cancellation with the same function used when recording. Receipts keep their number and print "Amended"; old values stay in the audit log. |
| 5 | Organization isolation | **Done for repositories.** Every business query now filters by organization (plus entity, deleted, property scope, own tenant). Negative cross-organization tests for payments, charges, expenses, tenants, units. Firestore side: see item 8. |
| 6 | Expense UI | **Done.** List, add, property and month filter, monthly total, empty/loading/error states, removal with email confirmation and archive snapshot. |
| 7 | Tenant UI | **Done:** Edit Tenant (rent locked once payments exist, because rent history arrives with Phase 4 bills), real Tenant Home (own due, advance, this month), real Tenant Profile. **Tickets stay in Phase 6: needs your explicit OK.** |
| 8 | Firestore property and tenant scoping | **Not done on purpose, blocks Phase 3.** Proposal below. |
| 9 | HLC and audit hardening | **Done.** HLC saved per device and restored (never goes back), `observeRemoteHlc` for the sync applier, audit checkpoint saved outside the database after each committed change, restore verification detects modified, removed, truncated and reordered records and a replaced file. |
| 10 | Database key recovery | **Done.** A new key is created only for a new database. Existing database with missing or damaged key: no new key, file untouched, Recovery screen. A key that does not open the file: same. Tests use real files. |
| 11 | Setup and delivery | **Partly.** Scripts portable (Linux and macOS: no GNU-only sed, python3 for the pubspec). `pubspec.lock`, Drift generated files, localization generated files and the Android/iOS folders are created by Flutter and cannot be produced here: BLOCKED. Dependency inventory: `docs/DEPENDENCIES.md`. |
| 12 | Master Prompt v3 Phase 2 features | **Scope-change proposal below. Waiting for your approval.** Archive is partly built (snapshots are written for tenants, payments, charges, expenses). |
| 13 | Real verification | **BLOCKED / NOT RUN here.** `tools/verify_phase1_1.sh` produces the real report. |

## New from you: business details and logo on receipts
- Settings, "Business details" (Owner/Admin): business name, owner name, address, phone, email, website, footer note.
  Starting values come from `BrandConfig` (LIFE EASY, MAHADI HASAN JEWEL, your logo); change one file for another business.
- Your hummingbird logo is bundled (`assets/brand/life_easy_logo.png`) and shown on the sign-in screen, dashboard, tenant home and on receipts.
- Receipt PDF (A5): logo, name, proprietor, address, phone, email, website, receipt number, date, tenant, unit, month,
  method, TrxID, amount, balance or advance, "Amended" marker, signature line, footer. Share (WhatsApp, email, Drive) or print.
- **Bengali needs the font:** without `NotoSansBengali-Regular.ttf` and `-Bold.ttf` in `assets/fonts/` the receipt prints in English with "BDT".
- Waiting for approval: `url_launcher` (direct WhatsApp chat button), `image_picker` (choose a different logo).

## Packages
`pdf` and `printing` are in the Master Prompt's locked stack. From pub.dev pages I could read: pdf 3.12.0 (Apache-2.0, publisher nfet.net),
printing 5.14.2 (Apache-2.0, same publisher). Last publish dates and open issue counts were not visible to me; run
`dart run tools/dependency_audit.dart` after `flutter pub get`. Please confirm you accept them.
`app_links`, `url_launcher`, `image_picker`: NOT added; license, version, date and issues not verified yet.

## Proposal for item 8: scoped Firestore operations (must be approved before Phase 3)
Server rules cannot read encrypted operations, so scoping must be in the record and in the keys:
1. Every operation carries `scopeType` (org, property, tenant) and `scopeId`.
2. Keys form a hierarchy: org key (basic organization data), one key per property, one key per tenant record, and the vault key.
   A Manager or Caretaker receives only the keys of their properties; a tenant receives only their tenant key.
3. Rules: reading or writing a property-scoped record needs membership in that property scope; a tenant-scoped record needs
   `linkedTenantId == scopeId` or admin. A client that edits its own code can download ciphertext it may not read, but cannot decrypt it.
4. Revoke and key rotation are ONE batch: rules require, with `getAfter`, that the member document becomes revoked AND the
   key version of every affected scope increases in the same commit. A revoke without rotation is rejected.
5. Emulator tests: tenant cannot read another tenant's records, Manager and Caretaker cannot read unassigned properties,
   revoke without rotation rejected, revoke with rotation accepted, old key cannot decrypt new operations.
Cost: more keys and a more complex invitation step. Decision needed from you.

## Proposal for item 12: Phase 2 features of Master Prompt v3 (not built yet)
- **2.2 Household and vault:** household members, tenant vault (NID, address, agreement), document storage with encryption, member-count rules.
- **2.3 OCR with human review:** needs a Tesseract Flutter package approved first and the Bengali font; plus your sample NID for the accuracy test.
- **2.4 Police form and Legal Records:** police form PDF with consent record, legal notice and NOC store, Legal Erasure, archive restore screen and the 2-year purge job.
I recommend 2.2, then 2.3, then 2.4, each after the gate passes. Approve, reorder, or tell me to drop something.

## Database changes
Nothing is released yet, so schema version 1 was edited in place (new: extra charges, business profile, archive snapshot column,
unique TrxID index). **A phone that already ran an earlier test build must clear the app data (or reinstall) once.**
Real migrations start with the first release; use `dart run drift_dev schema dump` then.
