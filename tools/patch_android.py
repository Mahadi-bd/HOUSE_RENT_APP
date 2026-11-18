#!/usr/bin/env python3
"""Idempotent Android project patches for a freshly generated Flutter project (Kotlin Gradle files):
- INTERNET permission in the main manifest (release builds need it for Firebase)
- App Link intent filter for the Firebase email-confirmation link
- Google services Gradle plugin, minSdk 23 (Firebase), app label
- Release signing from android/key.properties (falls back to debug signing when it is missing)
Works on Linux and macOS. Run from the project folder."""
import os
import re
import sys

APP_LABEL = "Rent Solution"
LINK_HOST = "rent-solution-2dd62.firebaseapp.com"
GMS_VERSION = "4.4.2"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def patch_manifest(path):
    s = read(path)
    changed = False
    if "android.permission.INTERNET" not in s:
        s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
        changed = True
    if LINK_HOST not in s:
        filt = (
            '\n            <intent-filter android:autoVerify="true">\n'
            '                <action android:name="android.intent.action.VIEW"/>\n'
            '                <category android:name="android.intent.category.DEFAULT"/>\n'
            '                <category android:name="android.intent.category.BROWSABLE"/>\n'
            f'                <data android:scheme="https" android:host="{LINK_HOST}"/>\n'
            "            </intent-filter>\n        "
        )
        s = s.replace("</activity>", filt + "</activity>", 1)
        changed = True
    s2 = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', s, count=1)
    if s2 != s:
        s, changed = s2, True
    if changed:
        write(path, s)
    return changed


def patch_settings(path):
    s = read(path)
    if "com.google.gms.google-services" in s:
        return False
    marker = 'id("com.android.application")'
    i = s.find(marker)
    if i < 0:
        print("WARNING: settings.gradle.kts has no application plugin line; add google-services by hand", file=sys.stderr)
        return False
    j = s.find("\n", i)
    s = s[: j + 1] + f'    id("com.google.gms.google-services") version "{GMS_VERSION}" apply false\n' + s[j + 1:]
    write(path, s)
    return True


SIGNING_HEAD = """val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = java.util.Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}

"""

SIGNING_BLOCK = """    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

"""


def patch_app_gradle(path):
    s = read(path)
    changed = False
    if "com.google.gms.google-services" not in s:
        s = s.replace('id("dev.flutter.flutter-gradle-plugin")', 'id("dev.flutter.flutter-gradle-plugin")\n    id("com.google.gms.google-services")', 1)
        changed = True
    if "minSdk = flutter.minSdkVersion" in s:
        s = s.replace("minSdk = flutter.minSdkVersion", "minSdk = 23", 1)
        changed = True
    if "keystoreProperties" not in s:
        s = s.replace("android {", SIGNING_HEAD + "android {", 1)
        s = s.replace("    buildTypes {", SIGNING_BLOCK + "    buildTypes {", 1)
        s = s.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
            1,
        )
        changed = True
    if changed:
        write(path, s)
    return changed


def main():
    kts = "android/app/build.gradle.kts"
    if not os.path.exists(kts):
        print("android/app/build.gradle.kts not found (older Groovy template?). Patch it by hand or use a newer Flutter.", file=sys.stderr)
        return 1
    manifest = "android/app/src/main/AndroidManifest.xml"
    results = {
        "manifest": patch_manifest(manifest),
        "settings": patch_settings("android/settings.gradle.kts") if os.path.exists("android/settings.gradle.kts") else False,
        "app gradle": patch_app_gradle(kts),
    }
    print("android patched:", ", ".join(f"{k}={'changed' if v else 'already ok'}" for k, v in results.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
