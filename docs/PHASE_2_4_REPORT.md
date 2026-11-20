# Phase 2.4 report (archive, legal records, legal erasure, police form)

Source code only; not compiled here. Written in this step: 3 repositories, 1 PDF builder, 3 screens, about 35 tests.

## Deleted Items Archive (2 years)
- Dashboard (Owner/Admin): "Deleted items archive". Every deleted tenant, payment, extra charge, expense, household member and document is listed with the delete date and the date it will be removed.
- **Restore:** payments (balance recalculated; refused if the TrxID was used again), tenants (refused if the unit has a new tenant, or if the tenant's personal data was erased), charges, expenses, household members (with private data), documents.
- **Purge:** once per app start (Owner/Admin) everything older than 2 years is removed for good, files included. A tenant is not deleted but reduced to a stub (name "[erased]", no phone/email/photo; private details, household and documents removed). Payment amounts, lease dates, the unit, legal records and the police-share log stay.

## Legal records
- Owner/Admin store a legal notice or NOC (photo from camera or gallery, optional reference number). Stored encrypted, never purged. Works for tenants who already moved out (open the tenant from the archive, scales icon).

## Legal erasure (on a legal notice)
- Needs: tenant already moved out, at least one legal notice for that tenant, a warning screen, and an email-link confirmation for that exact tenant.
- Erases: private details, household, documents and photos (files too), archive copies, OCR scans of those documents. Keeps: legal notice and NOC (files and records), police-share log, payment amounts without a name, lease dates, unit. Writes an erasure record. Tests scan every table for leftover names, NID and phone numbers.
- It cannot be undone, and the tenant cannot be restored afterwards.

## Police form
- Tenant profile menu (Owner/Admin only): "Police form". The person must tick that the tenant agreed. The PDF (tenant, NID, address, emergency contact, lease dates, household with phones and ID numbers, owner details, signature lines) opens in the share menu. Every share is logged (who, when, consent). The log and audit never contain the tenant's data.
- **Limit:** the form is in English for now (Bengali labels need the font files and translated labels; ask me).

## Still open
1. Scoped Firestore keys and rules (blocks Phase 3).
2. Real compile results from GitHub (the first Gradle error was fixed; Dart errors may follow).
3. Bengali police form, Sign in with Apple, offline lease durations (waiting for you).
