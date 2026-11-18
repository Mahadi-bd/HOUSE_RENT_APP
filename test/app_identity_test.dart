// Checks the REAL generated platform files. Fails (does not skip) when they are missing or wrong.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rent_solution/core/constants/app_constants.dart';

String _read(List<String> candidates) {
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  fail('None of these files exist: ${candidates.join(', ')}. Run tools/set_app_id.sh.');
}

void main() {
  const id = AppConstants.applicationId;

  test('Android namespace and applicationId', () {
    final gradle = _read(['android/app/build.gradle.kts', 'android/app/build.gradle']);
    expect(RegExp(r'namespace\s*=?\s*"([^"]+)"').firstMatch(gradle)?.group(1), id);
    expect(RegExp(r'applicationId\s*=?\s*"([^"]+)"').firstMatch(gradle)?.group(1), id);
  });

  test('iOS bundle identifier (app target; test target may add .RunnerTests)', () {
    final pbx = _read(['ios/Runner.xcodeproj/project.pbxproj']);
    final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
        .allMatches(pbx)
        .map((m) => m.group(1)!.replaceAll('"', ''))
        .toSet();
    expect(ids, contains(id));
    expect(
      ids.where((v) => !v.endsWith('.RunnerTests')),
      {id},
      reason: 'every non-test target must use $id',
    );
  });

  test('Firebase Android config matches the application id', () {
    final json = _read(['android/app/google-services.json']);
    expect(json, contains('"package_name": "$id"'));
    expect(json, contains('"project_id": "${AppConstants.firebaseProjectId}"'));
  });

  test('Firebase iOS config matches the bundle id', () {
    final plist = _read(['ios/Runner/GoogleService-Info.plist']);
    expect(plist, contains('<string>$id</string>'));
    expect(plist, contains('<string>${AppConstants.firebaseProjectId}</string>'));
  });
}
