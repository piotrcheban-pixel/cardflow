import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/ui/settings/about_links.dart';

void main() {
  group('О приложении (SPEC A6.6)', () {
    test('версия совпадает с pubspec.yaml', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final RegExpMatch? match = RegExp(
        r'^version:\s*(\S+)$',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'в pubspec.yaml нет version');
      final String version = match!.group(1)!.split('+').first;
      expect(appVersion, version);
    });

    test('политика приватности — https-ссылка на docs/privacy.md', () {
      expect(privacyPolicyUri.scheme, 'https');
      expect(privacyPolicyUri.path, endsWith('/docs/privacy.md'));
      expect(File('docs/privacy.md').existsSync(), isTrue);
    });
  });
}
