import 'package:flutter_test/flutter_test.dart';

import '../../tool/extract_ui_keys.dart'
    show UiKeyScan, extractUiKeys, extractUiKeysFromSource;
import 'guard_utils.dart';

/// Фикстура снимка ключей.
const String uiKeysFixturePath = 'test/guards/fixtures/ui_keys.txt';

/// Контракт ключей `ValueKey<String>` (REDESIGN-PLAN, «Ключи — контракт»).
///
/// Снимок `test/guards/fixtures/ui_keys.txt` снят ОДИН раз до правок
/// визуального слоя (редизайн Nocturne, этап 1). Правило: набор ключей в
/// `lib/ui/**` должен совпадать со снимком. Ключ исчез — тест падает (экран
/// потерял контракт с виджет-тестами). Появился новый ключ — его добавляют в
/// снимок в том же коммите (`fvm dart run tool/extract_ui_keys.dart --write`).
void main() {
  group('ui_keys: реальный репозиторий', () {
    test('каждый ключ снимка присутствует в lib/ui/**', () {
      final UiKeyScan scan = extractUiKeys(projectRoot());
      final Set<String> current = scan.keys.map((key) => key.pattern).toSet();
      final List<String> snapshot = readFixtureLines(uiKeysFixturePath);
      expect(
        snapshot,
        isNotEmpty,
        reason: 'Снимок ключей пуст — фикстура не сгенерирована.',
      );

      final List<String> missing =
          snapshot.where((key) => !current.contains(key)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason:
            'Ключи из снимка исчезли из lib/ui/** — это ломает контракт с '
            'виджет-тестами (REDESIGN-PLAN): ${missing.join(', ')}',
      );
    });

    test('новые ключи добавлены в снимок в том же коммите', () {
      final UiKeyScan scan = extractUiKeys(projectRoot());
      final Set<String> current = scan.keys.map((key) => key.pattern).toSet();
      final Set<String> snapshot = readFixtureLines(uiKeysFixturePath).toSet();
      final List<String> added = current.difference(snapshot).toList()..sort();
      expect(
        added,
        isEmpty,
        reason:
            'Новые ключи не попали в test/guards/fixtures/ui_keys.txt: '
            '${added.join(', ')}. Обновите снимок: '
            '`fvm dart run tool/extract_ui_keys.dart --write`.',
      );
    });

    test('снимок отсортирован и без дублей', () {
      final List<String> snapshot = readFixtureLines(uiKeysFixturePath);
      final List<String> sorted = snapshot.toSet().toList()..sort();
      expect(snapshot, sorted);
    });

    test(r'ключи-шаблоны нормализованы в * и не содержат ${...}', () {
      for (final String key in readFixtureLines(uiKeysFixturePath)) {
        expect(key, isNot(contains(r'${')), reason: 'Ключ не нормализован');
        expect(key, isNot(contains(r'$')), reason: 'Ключ не нормализован');
      }
    });
  });

  group('ui_keys: самопроверка экстрактора', () {
    test('литерал и шаблон', () {
      final UiKeyScan scan = extractUiKeysFromSource(
        "key: const ValueKey<String>('review-card'),\n"
        "child: ValueKey<String>('deck-card-\${deck.id}'),\n"
        "id: ValueKey<String>('feed-card-\$index'),\n",
      );
      expect(scan.keys.map((key) => key.pattern).toList(), <String>[
        'review-card',
        'deck-card-*',
        'feed-card-*',
      ]);
      expect(scan.dynamic, isEmpty);
    });

    test('аргумент-выражение: литералы из тернарника, иначе dynamic', () {
      final UiKeyScan scan = extractUiKeysFromSource(
        "key: ValueKey<String>(show ? 'cloze-answer-\$n' : 'cloze-gap-\$n'),\n"
        "key: ValueKey<String>(state.current!.card.id),\n",
      );
      expect(scan.keys.map((key) => key.pattern).toList(), <String>[
        'cloze-answer-*',
        'cloze-gap-*',
      ]);
      expect(scan.dynamic, hasLength(1));
      expect(scan.dynamic.single.expression, 'state.current!.card.id');
    });

    test('многострочный литерал и двойные кавычки', () {
      final UiKeyScan scan = extractUiKeysFromSource(
        'key: const ValueKey<String>(\n  "review-interval-again",\n),\n',
      );
      expect(scan.keys.single.pattern, 'review-interval-again');
    });

    test('объявление поля не считается ключом', () {
      final UiKeyScan scan = extractUiKeysFromSource(
        'final ValueKey<String> faceKey;\n',
      );
      expect(scan.keys, isEmpty);
      expect(scan.dynamic, isEmpty);
    });

    test('не путает похожие конструкторы', () {
      final UiKeyScan scan = extractUiKeysFromSource(
        "key: ValueKey<String>('a'), other: const Key('b'),\n",
      );
      expect(scan.keys.map((key) => key.pattern).toList(), <String>['a']);
    });
  });
}
