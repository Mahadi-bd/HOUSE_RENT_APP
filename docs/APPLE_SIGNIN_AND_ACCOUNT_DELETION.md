# iOS sign-in review (App Store Guideline 4.8) and account deletion

## Do we need Sign in with Apple?
The app offers Google Sign-In as a main way to create an account. Under Guideline 4.8 an app that uses a
third-party or social login must also offer an equivalent login that limits data to name and email, lets
the person hide their email, and does not track them. Email-link sign-in does not let people hide their
email. To avoid rejection, add Sign in with Apple on iOS. Apple's own review decides; this is the safe path.

## Options (no package has been added)
| Option | New package? | Notes |
|---|---|---|
| A. Firebase Auth built-in Apple provider (`signInWithProvider(AppleAuthProvider())`) | **No** (uses `firebase_auth`, already approved) | Works on iOS and Android through Firebase. Needs Apple Developer setup and enabling Apple in Firebase. Recommended. |
| B. `sign_in_with_apple` | Yes | Publisher aboutyou.com (verified), MIT license (from pub.dev/aggregator pages I could read). Supports iOS, macOS, Android, Web. A version shown by an aggregator is 7.0.1; pub.dev score pages I opened showed older snapshots. Last publish date and open GitHub issue count: NOT VERIFIED here; `dart run tools/dependency_audit.dart` prints them once the package is added. Needed only if option A has nonce or flow problems. |

Recommendation: option A, no new dependency. Please approve A, B, or neither. I will not add anything until you answer.
Cost note: the Apple Developer Program has a yearly fee (store fee, not an app charge).

## Account deletion (separate from rental-record deletion)
Apple (and Google Play) require an in-app way to delete the account if the app lets people create one.
- This deletes the PERSON'S login account and their membership. It is not the same as deleting tenants,
  payments or other rental records, which follow the 2-year archive and legal-record rules.
- Flow: Settings, "Delete my account", confirm by email link (or Apple re-authentication), then:
  remove the Firebase Auth user, mark the membership revoked, delete this person's local database and keys.
- The Owner cannot delete their account while they own an organization: they must transfer ownership
  (not built yet) or close the organization. Closing an organization means exporting a backup first.
- Sign in with Apple users: also revoke the Apple token when deleting (Apple requires this).
- Business records the person created stay in the organization (they belong to the business); the person's
  name on them stays as the audit trail needs it. State this in the privacy policy.
