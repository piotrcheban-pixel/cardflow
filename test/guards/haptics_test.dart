import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Единственная точка тактильного отклика — `lib/ui/design/haptics.dart`
/// (REDESIGN-SPEC §7, ADR-035). Прямые вызовы `HapticFeedback.*` в экранах
/// мигрируют на `NcHaptics` в этапах 3–4; до этого они заморожены в
/// `fixtures/haptics_baseline.txt` (та же логика долга, что у цветов).
const String hapticsFile = 'lib/ui/design/haptics.dart';

/// Фикстура замороженного долга (по файлу, без номеров строк).
const String hapticsBaselinePath = 'test/guards/fixtures/haptics_baseline.txt';

/// Вызывает ли исходник `HapticFeedback.*`.
bool usesRawHaptics(String dartSource) {
  for (final String line in dartSource.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    if (line.contains('HapticFeedback.')) return true;
  }
  return false;
}

/// Файлы `lib/ui/**`, вызывающие `HapticFeedback.*` напрямую.
List<String> scanUiRawHaptics() {
  final files = repoFiles('lib/ui', include: (name) => name.endsWith('.dart'));
  final root = projectRoot().path;
  final result = <String>[];
  for (final File file in files) {
    final String relative = file.path
        .substring(root.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (relative == hapticsFile) continue;
    if (usesRawHaptics(file.readAsStringSync())) result.add(relative);
  }
  result.sort();
  return result;
}

void main() {
  group('haptics: реальный репозиторий', () {
    test('HapticFeedback.* только в design/haptics.dart', () {
      final Set<String> current = scanUiRawHaptics().toSet();
      final Set<String> baseline = readFixtureSet(hapticsBaselinePath);

      final List<String> added = current.difference(baseline).toList()..sort();
      expect(
        added,
        isEmpty,
        reason:
            'Прямые вызовы HapticFeedback.* вне $hapticsFile. Используйте '
            'NcHaptics (REDESIGN-SPEC §7):\n${added.join('\n')}',
      );

      final List<String> stale = baseline.difference(current).toList()..sort();
      expect(
        stale,
        isEmpty,
        reason:
            'Файл из $hapticsBaselinePath больше не вызывает HapticFeedback.* '
            '— удалите строку из фикстуры (burn-down):\n${stale.join('\n')}',
      );
    });
  });

  group('haptics: самопроверка детектора', () {
    test('ловит прямой вызов и не ловит комментарий', () {
      expect(
        usesRawHaptics('void f() => HapticFeedback.lightImpact();'),
        isTrue,
      );
      expect(
        usesRawHaptics('// HapticFeedback.lightImpact() в комментарии'),
        isFalse,
      );
      expect(usesRawHaptics('void f() => NcHaptics.flip();'), isFalse);
    });
  });
}
