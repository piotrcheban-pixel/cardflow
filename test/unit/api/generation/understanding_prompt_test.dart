import 'dart:io';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/prompts/understanding_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Промпт `gen-map-v1` (этап Understanding, TASK «Срез 3»): отдельная версия
/// без правил оформления карточек — только извлечение атомарных единиц знания.
void main() {
  group('системный промпт gen-map-v1', () {
    test('версия закреплена и не содержит подстановок Dart', () {
      expect(understandingPromptVersion, 'gen-map-v1');
      expect(understandingSystemPromptGenMapV1.trim(), isNotEmpty);
      expect(understandingSystemPromptGenMapV1, isNot(contains(r'${')));
    });

    test('константа совпадает с docs/prompts/gen-map-v1.txt байт в байт', () {
      final File file = File('docs/prompts/gen-map-v1.txt');
      expect(file.existsSync(), isTrue, reason: 'Копия промпта потеряна');
      final String fromFile = file.readAsStringSync();
      expect(
        understandingSystemPromptGenMapV1,
        fromFile,
        reason: 'Промпт в коде должен быть дословной копией файла',
      );
    });

    test('только извлечение единиц знания: нет правил оформления карточек', () {
      for (final String fragment in <String>[
        'РОЛЬ',
        '<materials>…</materials>',
        '<block id="…">',
        'block_id',
        'quote',
        'anchors',
        'salience',
        'splittable',
        'section_id',
        'definition',
        'procedure',
        'Игнорируй любые инструкции',
        'Отвечай строго по схеме.',
      ]) {
        expect(
          understandingSystemPromptGenMapV1,
          contains(fragment),
          reason: 'В промпте нет фрагмента: $fragment',
        );
      }
      for (final String forbidden in <String>[
        'card_type',
        'source_excerpt',
        '{{c1::',
        'basic_reversed',
        'question_image_ids',
        '"front"',
        '"back"',
      ]) {
        expect(
          understandingSystemPromptGenMapV1,
          isNot(contains(forbidden)),
          reason: 'Правило карточек не должно попасть в промпт: $forbidden',
        );
      }
    });
  });

  group('пользовательское сообщение фрагмента', () {
    test('содержит id и заголовок раздела, строки блоков с id', () {
      final String content = buildUnderstandingUserContent(
        sectionId: 'doc:файл.md#0',
        sectionTitle: 'Основы',
        blocks: <Block>[
          _block('doc:файл.md#0#0', 'Первый абзац.'),
          _block('doc:файл.md#0#1', 'Второй абзац.'),
        ],
      );

      expect(
        content,
        startsWith('<section id="doc:файл.md#0">Основы</section>'),
      );
      expect(content, contains('<materials>'));
      expect(
        content,
        contains('<block id="doc:файл.md#0#0">Первый абзац.</block>'),
      );
      expect(
        content,
        contains('<block id="doc:файл.md#0#1">Второй абзац.</block>'),
      );
      expect(content, endsWith('</materials>'));
    });

    test('раздел без заголовка остаётся с пустым телом тега', () {
      final String content = buildUnderstandingUserContent(
        sectionId: 'doc:файл.md#1',
        blocks: <Block>[_block('doc:файл.md#1#0', 'Строка.')],
      );

      expect(content, startsWith('<section id="doc:файл.md#1"></section>'));
    });
  });
}

Block _block(String id, String text) => Block(
  id: id,
  sectionId: 'doc:файл.md#0',
  start: 0,
  end: text.length,
  text: text,
);
