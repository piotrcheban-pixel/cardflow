import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Бренды и имена форматов, для которых латиница разрешена (SPEC 3.1).
///
/// `API`, `Word`, `Excel`, `PowerPoint`, `cloze`, `X` добавлены в итерации 3c:
/// они дословно входят в тексты, заданные SPEC A6.6/A6.8/A8.4 (блок «API»,
/// подпись зоны прикрепления, подсказка пожеланий, тип карточки cloze).
/// `c` — не слово интерфейса, а обязательный маркер синтаксиса `{{c1::…}}` из A7.9.
/// Основание — ADR-015 §8/ADR-017; правило «интерфейс только на русском» не ослаблено.
const List<String> allowedLatinTokens = <String>[
  'CardFlow',
  'OpenAI',
  'Gemini',
  'Anthropic',
  'PDF',
  'DOCX',
  'XLSX',
  'PPTX',
  'MD',
  'RTF',
  'ODT',
  'ZIP',
  'JPG',
  'JPEG',
  'PNG',
  'LaTeX',
  'FSRS',
  'API',
  'Word',
  'Excel',
  'PowerPoint',
  'cloze',
  'c',
  'X',
];

/// Служебные слова ICU-плюрализации/селекта — не английский текст интерфейса.
const List<String> _icuKeywords = <String>[
  'plural',
  'select',
  'selectordinal',
  'zero',
  'one',
  'two',
  'few',
  'many',
  'other',
  'offset',
];

/// Убирает из ICU-сообщения синтаксис, оставляя только пользовательский текст.
String stripIcuSyntax(String message) {
  var result = message;
  // Простые подстановки: {name}, {count}.
  result = result.replaceAll(RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\}'), ' ');
  // Заголовок сложного аргумента: {count, plural, ...} / {gender, select, ...}.
  result = result.replaceAll(
    RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\s*,\s*(plural|select|selectordinal)\s*,'),
    ' ',
  );
  // Селекторы веток: =0{ / one{ / other{ / offset:1 ... (открывающая скобка остаётся).
  result = result.replaceAll(
    RegExp(r'(=\d+|zero|one|two|few|many|other|offset:\d+)\s*\{'),
    ' ',
  );
  // Экранирование апострофа в ARB.
  result = result.replaceAll("''", "'");
  return result;
}

/// Возвращает латинские фрагменты сообщения вне allow-list (пусто — нарушений нет).
List<String> latinOutsideAllowList(String message) {
  var text = stripIcuSyntax(message);
  final sorted = [...allowedLatinTokens]
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final token in sorted) {
    // Слово-целиком: «PDF» в «PDF-файл» разрешён, «MDX» — нет (не allow-list).
    text = text.replaceAll(
      RegExp('(?<![A-Za-z])${RegExp.escape(token)}(?![A-Za-z])'),
      ' ',
    );
  }
  for (final keyword in _icuKeywords) {
    text = text.replaceAll(RegExp('\\b$keyword\\b'), ' ');
  }
  return RegExp('[A-Za-z]+')
      .allMatches(text)
      .map((match) => match.group(0)!)
      .toList();
}

/// Ищет строковые литералы, переданные в текстовые виджеты напрямую:
/// `Text('…')`, `SelectableText('…')`, `Text.rich(TextSpan(text: '…'))`.
List<String> hardcodedTextLiterals(String dartSource) {
  final patterns = <RegExp>[
    RegExp('''\\b(?:Text|SelectableText)\\s*\\(\\s*(?:const\\s+)?['"]'''),
    RegExp(
      '''\\bText\\.rich\\s*\\(\\s*(?:const\\s+)?TextSpan\\s*\\(\\s*text\\s*:\\s*['"]''',
    ),
  ];
  final matches = <int>[];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(dartSource)) {
      matches.add(match.start);
    }
  }
  matches.sort();
  return matches
      .map(
        (start) => dartSource.substring(
          start,
          (start + 40).clamp(0, dartSource.length),
        ),
      )
      .toList();
}

Map<String, dynamic> loadArb() {
  final raw = readRepoFile('lib/l10n/app_ru.arb');
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('ru_strings: ARB-файл', () {
    test('app_ru.arb валиден, содержит локаль ru и строки без латиницы вне allow-list', () {
      final arb = loadArb();
      expect(arb['@@locale'], 'ru');

      final violations = <String>[];
      for (final entry in arb.entries) {
        // @-ключи — метаданные gen-l10n, не пользовательский текст.
        if (entry.key.startsWith('@')) continue;
        final value = entry.value;
        if (value is! String) continue;
        final latin = latinOutsideAllowList(value);
        if (latin.isNotEmpty) {
          violations.add('${entry.key}: ${latin.join(', ')} → "$value"');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'В app_ru.arb найдена латиница вне allow-list: $violations',
      );
    });

    test('все пользовательские строки ARB непустые', () {
      final arb = loadArb();
      for (final entry in arb.entries) {
        if (entry.key.startsWith('@')) continue;
        if (entry.value is String) {
          expect(
            (entry.value as String).trim(),
            isNotEmpty,
            reason: 'Пустая строка: ${entry.key}',
          );
        }
      }
    });
  });

  group('ru_strings: литералы в lib/ui', () {
    test('в lib/ui нет строковых литералов, переданных в Text(...)', () {
      final files = repoFiles(
        'lib/ui',
        excludedDirs: const <String>{'.dart_tool', 'build'},
        include: (name) => name.endsWith('.dart'),
      );
      expect(
        files,
        isNotEmpty,
        reason: 'В lib/ui нет Dart-файлов — проверка не имеет смысла.',
      );
      final violations = <String>[];
      for (final file in files) {
        for (final literal in hardcodedTextLiterals(file.readAsStringSync())) {
          violations.add('${file.path}: $literal');
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Текст интерфейса должен идти из AppLocalizations, найдены литералы: $violations',
      );
    });
  });

  group('ru_strings: самопроверка детектора', () {
    test('пропускает русский текст и allow-list', () {
      expect(latinOutsideAllowList('Сохранить карточку'), isEmpty);
      expect(
        latinOutsideAllowList('Формат PDF и DOCX, модель OpenAI'),
        isEmpty,
      );
      expect(latinOutsideAllowList('Открыть CardFlow'), isEmpty);
    });

    test('ловит английский текст', () {
      expect(latinOutsideAllowList('Save card'), isNotEmpty);
      expect(latinOutsideAllowList('Файл в формате XLSX'), isEmpty);
      expect(latinOutsideAllowList('Экспорт в XLSX-файл'), isEmpty);
    });

    test('allow-list действует по границам слов: MDX не разрешён', () {
      expect(latinOutsideAllowList('Файл MDX'), isNotEmpty);
      expect(latinOutsideAllowList('Формат MD'), isEmpty);
      expect(latinOutsideAllowList('Файл PDF-документ'), isEmpty);
    });

    test('понимает ICU-плюрализацию и подстановки', () {
      const message =
          '{count, plural, =0{нет карточек} one{одна карточка} few{# карточки} many{# карточек} other{# карточки}}';
      expect(latinOutsideAllowList(message), isEmpty);
      expect(latinOutsideAllowList('Привет, {name}!'), isEmpty);
    });

    test('ловит английское слово внутри ветки плюрализации', () {
      const message = '{count, plural, one{one card} other{many cards}}';
      expect(latinOutsideAllowList(message), isNotEmpty);
    });

    test('находит литерал в Text(...) и не находит локализованный вызов', () {
      expect(hardcodedTextLiterals("Text('Привет')"), hasLength(1));
      expect(hardcodedTextLiterals("Text(\n  'Привет',\n)"), hasLength(1));
      expect(hardcodedTextLiterals('Text(l10n.appTitle)'), isEmpty);
      expect(hardcodedTextLiterals('Text(context.l10n.appTitle)'), isEmpty);
    });

    test('ловит литералы в SelectableText и Text.rich', () {
      expect(hardcodedTextLiterals("SelectableText('Привет')"), hasLength(1));
      expect(
        hardcodedTextLiterals("Text.rich(TextSpan(text: 'Привет'))"),
        hasLength(1),
      );
      expect(
        hardcodedTextLiterals('Text.rich(TextSpan(text: l10n.appTitle))'),
        isEmpty,
      );
    });

    test('ARB существует по ожидаемому пути', () {
      final arbFile = File(
        '${projectRoot().path}${Platform.pathSeparator}lib${Platform.pathSeparator}l10n'
        '${Platform.pathSeparator}app_ru.arb',
      );
      expect(arbFile.existsSync(), isTrue);
    });
  });
}
