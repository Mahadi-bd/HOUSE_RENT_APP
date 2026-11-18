# Firebase (project rent-solution-2dd62). Do NOT enable Blaze.

1. Firestore Database: create (Standard, production mode), nearest region (cannot change later).
2. Authentication: enable Google and Email link. (Apple later, see docs.)
3. Android app and iOS app: both `com.rentsolution.app` (`flutterfire configure` in tools/setup.sh does this). Add debug SHA-1 and SHA-256 for Android.
4. TTL policy: collection group `ops`, field `expireAt`.
5. Rules: run the tests first.

       cd firebase
       npm install
       npm test          # starts the Firestore emulator and runs test/rules.test.js

   Only if every test passes: paste `firestore.rules` in the console (Firestore, Rules, Publish).

Server rules cannot see encrypted operation contents. Business permissions on operations are checked by the
applying device (the Admin device is the authority); vault data is protected by the vault key.
