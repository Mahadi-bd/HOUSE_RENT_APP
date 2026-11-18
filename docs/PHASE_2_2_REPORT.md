# Phase 2.2 and 2.3 report (household, private details, documents, OCR) + branding + GitHub APK

Same honesty line as before: source code only, NOT compiled or run here. Static checks that ran: imports, brackets,
language keys (304 in each of English, Bengali, Hindi), script syntax, and `patch_android.py` / `set_app_id.sh` /
`patch_pubspec.py` on mock project files. Tests written: about 265 Dart cases and 49 Firestore rules cases.

## Your answers, and what was done
| Your decision | Done |
|---|---|
| Phase 2.2 to 2.4 in order | **2.2 done now** (below). 2.3 (OCR) and 2.4 (police form, legal records, archive restore and purge) are next. |
| Scoped Firestore key hierarchy before Phase 3 | **Approved; not built yet.** Next after 2.4 (design in `PHASE_2_1_REPORT.md`). Phase 3 will not start before it. |
| New packages (my responsibility) | **Added:** url_launcher, image_picker, app_links, pdf, printing. Used: WhatsApp button, logo picker, tenant photo/NID camera, automatic email-link completion. |
| Tenant tickets | Stay in Phase 6 (placeholder tab until then). |
| Permanent LIFE EASY branding + GitHub APK | **Done.** See below. |

## Permanent branding
`BrandConfig` (LIFE EASY, developer MAHADI HASAN JEWEL, your logo) is the single source. The About screen (open to every role, from Settings and
the tenant Profile and the dashboard) shows the logo, brand, "Developed and designed by MAHADI HASAN JEWEL", version and licence. A small footer carries the
same line on the sign-in screen, dashboard and settings. These cannot be edited in the app (the business details on receipts can).

## Phase 2.2
- **People in the home:** family, domestic worker, driver, guard, other. Names, relations and ages are basic data visible to staff;
  the total ("N people in the home") includes the tenant. Phone and ID number are private (vault).
- **Private details:** NID number (10, 13 or 17 digits checked), permanent address, emergency contact. Locked for people without vault access;
  tenants see their own. The audit log records which fields changed, never the values.
- **Documents:** tenant photo (basic) and NID card or agreement (private), taken with the camera or chosen from the gallery, reduced to at most
  1600 px, then **encrypted on the phone with AES-256-GCM** before saving. Tamper and file-swap detection. A lost vault key never creates a replacement key.
- New permission `tenantSensitiveWrite`. Removing a person or document needs Owner/Admin and an email confirmation for that exact record; a snapshot goes to the 2-year archive.

## Phase 2.3: OCR with human review
- **Scan NID card** (private details section): camera or gallery, text is read on the phone (Tesseract, English + Bengali), then a **review screen** shows the photo and
  the suggestions. The person corrects the NID number and presses "Confirm and save". Nothing is saved before that.
  Saved: NID number (private details), the card photo (encrypted), and a scan record with who confirmed it. The audit log and scan record never contain the NID itself.
- Name, parents and date of birth are shown for comparison only (there is no field for them in the private details yet).
- **Payment screenshot reader** on Record Payment: fills provider, amount and TrxID from a bKash/Nagad/Rocket screenshot; the person still checks and presses Save.
- Parsers are plain Dart with tests (English and Bengali labels, Bengali digits, spaced numbers, bad dates). Missing values give warnings, never invented values.
- **Not verified:** how well Tesseract reads real Bangladeshi NID photos, and the `flutter_tesseract_ocr` package (maintenance, iOS). Language data is
  downloaded by `tools/fetch_tessdata.sh` (also run by the GitHub workflow). Lease-paper OCR is not built (only NID and payment screenshots).

## Receipts and WhatsApp
Receipt menu on every payment: share PDF, print, **Send on WhatsApp** (opens `wa.me` with the receipt text; you tap Send). Business details and logo can be changed in Settings.

## GitHub
`.github/workflows/ci.yml` (rules tests, analyze, tests, debug APK) and `release.yml` (signed release APK, attached to a GitHub Release on a `v*` tag), `tools/ci_prepare.sh`,
`tools/patch_android.py` (INTERNET permission, Firebase Gradle plugin, minSdk 23, release signing, link filter), and `docs/GITHUB_APK_GUIDE.md`.

## Still open
1. A real NID photo test of OCR (send a sample with the name covered, or test on your phone and tell me the result).
2. Phase 2.4 police form and consent record, legal notices and NOC, Legal Erasure, archive restore screen and purge job.
3. Scoped Firestore keys and rules (blocks Phase 3).
4. Offline lease durations and Sign in with Apple (waiting for you).
5. Real verification: nobody has compiled this code. First GitHub run will probably show errors; send me the log.
