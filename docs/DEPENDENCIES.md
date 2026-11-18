# Direct dependencies (plan, not evidence)

Exact versions, license tags, publish dates and open-issue counts come from `dart run tools/dependency_audit.dart`
after `flutter pub get` (needs Flutter and internet; BLOCKED where this was written).

| Package | Why it is required | Approved |
|---|---|---|
| flutter_riverpod | State management | Master Prompt stack |
| go_router | Routing and role guards | Master Prompt stack |
| drift, drift_dev, build_runner | Local database and code generation | Master Prompt stack |
| sqlite3 (3.x, sqlite3mc build hook) | Encrypted SQLite (SQLite3MultipleCiphers) | Replaces sqlcipher_flutter_libs |
| path, path_provider | Database file location | Needed by drift |
| flutter_secure_storage | Database key, device id, language, clock, audit checkpoint | Master Prompt stack |
| cryptography | AES-GCM, key derivation (Phase 3 and 5) | Master Prompt stack |
| crypto | SHA-256 for the audit chain and device codes | Approved (v3 update) |
| firebase_core, firebase_auth, cloud_firestore | Sign-in, email-link confirmation, encrypted relay | Owner-approved Firebase exception |
| google_sign_in | Google login, later Drive backup | Master Prompt stack |
| local_auth | Biometric unlock (Phase 5) | Master Prompt stack |
| intl, flutter_localizations | Localization, number and date formats | Master Prompt stack |
| logger | Logging instead of print | Master Prompt stack |
| pdf, printing | Receipt PDF, print, share sheet | Master Prompt stack; please confirm (see report) |
| url_launcher | Opens WhatsApp (wa.me) with the receipt text | Approved by the Owner (Owner delegated; Flutter-team package, BSD-3) |
| image_picker | Camera or gallery for the logo and tenant documents | Approved by the Owner (Flutter-team package, BSD-3) |
| app_links | Receives the email-confirmation link inside the app | Approved by the Owner. From pub.dev: version 7.0.0, Apache-2.0, 160/160 points, 1.2M downloads; open-issue count not checked |
| flutter_tesseract_ocr | On-phone OCR for NID cards and payment screenshots (Tesseract, Apache-2.0 engine) | Chosen by the developer (Owner delegated). pub.dev snapshot seen: 0.4.30, BSD-3, unverified publisher; maintenance, iOS support and Bengali accuracy NOT verified. It is behind the `OcrEngine` interface so it can be replaced. |
| very_good_analysis (dev) | Lint rules | Master Prompt coding standards |
| integration_test (dev, Flutter SDK) | Real-device tests | Flutter SDK package |

Not added, waiting for a decision: a Tesseract wrapper (Phase 2.3), flutter_launcher_icons, Sign in with Apple package.
Removed: sqlcipher_flutter_libs, riverpod_annotation, riverpod_generator.
