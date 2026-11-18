// Builds docs/dependency_audit.md from pubspec.yaml + pubspec.lock using pub.dev and GitHub.
// Run: dart run tools/dependency_audit.dart   (needs internet; GitHub allows 60 calls/hour)
import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>?> _getJson(HttpClient client, String url) async {
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', 'rent-solution-audit');
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    return jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } on Object {
    return null;
  }
}

Future<void> main() async {
  final lock = File('pubspec.lock').readAsLinesSync();
  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final direct = <String>{};
  var section = '';
  for (final line in pubspec) {
    if (RegExp(r'^[a-z_]+:').hasMatch(line)) {
      section = line.split(':').first;
    } else if ((section == 'dependencies' || section == 'dev_dependencies') &&
        RegExp(r'^  [a-z0-9_]+:').hasMatch(line)) {
      direct.add(line.trim().split(':').first);
    }
  }
  final resolved = <String, String>{};
  String? current;
  for (final line in lock) {
    final name = RegExp(r'^  ([a-z0-9_]+):$').firstMatch(line);
    if (name != null) {
      current = name.group(1);
    }
    final version = RegExp(r'^    version: "([^"]+)"').firstMatch(line);
    if (version != null && current != null) {
      resolved[current] = version.group(1)!;
    }
  }
  final client = HttpClient();
  final out = StringBuffer()
    ..writeln('# Dependency audit')
    ..writeln('Generated ${DateTime.now().toUtc().toIso8601String()} from pubspec.lock.')
    ..writeln()
    ..writeln('| Package | Resolved | Latest | Last published | License tag | Open issues | Free | Open source |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final name in direct.toList()..sort()) {
    if (name == 'flutter' || name == 'flutter_test' || name == 'flutter_localizations' ||
        name == 'integration_test') {
      out.writeln('| $name | Flutter SDK | - | - | BSD-3-Clause (Flutter SDK) | - | yes | yes |');
      continue;
    }
    final info = await _getJson(client, 'https://pub.dev/api/packages/$name');
    final score = await _getJson(client, 'https://pub.dev/api/packages/$name/score');
    final latest = info?['latest'] as Map<String, dynamic>?;
    final pub = latest?['pubspec'] as Map<String, dynamic>?;
    final tags = ((score?['tags'] as List<dynamic>?) ?? const []).cast<String>();
    final license = tags.where((t) => t.startsWith('license:')).join(', ');
    final osi = tags.contains('license:osi-approved');
    var issues = 'unknown';
    final repo = (pub?['repository'] ?? pub?['homepage'])?.toString() ?? '';
    final gh = RegExp(r'github\.com/([^/]+/[^/#?]+)').firstMatch(repo);
    if (gh != null) {
      final repoInfo = await _getJson(client, 'https://api.github.com/repos/${gh.group(1)!.replaceAll('.git', '')}');
      if (repoInfo != null) {
        issues = '${repoInfo['open_issues_count']} (incl. PRs) https://github.com/${gh.group(1)}/issues';
      }
    }
    out.writeln('| $name | ${resolved[name] ?? '?'} | ${latest?['version'] ?? '?'} | '
        '${latest?['published'] ?? '?'} | ${license.isEmpty ? 'unknown' : license} | $issues | '
        '${osi ? 'yes' : 'check'} | ${osi ? 'yes' : 'check'} |');
  }
  out
    ..writeln()
    ..writeln('Firebase (the service) is the owner-approved proprietary exception; its Flutter SDKs are open source.');
  Directory('docs').createSync(recursive: true);
  File('docs/dependency_audit.md').writeAsStringSync(out.toString());
  stdout.writeln(out);
  client.close();
}
