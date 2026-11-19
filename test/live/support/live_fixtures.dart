/// Материалы сценариев live-испытаний (TASK 04, раздел 7).
///
/// Все тексты — нейтральные учебные описания (естественные науки, техника),
/// без персональных данных и без спорных тем. Файлы собираются программно:
/// бинарные фикстуры в репозиторий не коммитятся (AGENTS: фикстуры документов
/// программные).
library;

import 'dart:typed_data';

import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/pdf_parser.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../unit/api/parsers/fixtures/document_fixtures.dart';

/// Тема Test A: базовое понятие нейтральной области (круговорот воды).
const String kLiveTopicShort =
    'Круговорот воды в природе: испарение, '
    'конденсация, осадки и сток';

/// Тема Test B: список понятий для 40 карточек (статика/физика).
const String kLiveTopicMany =
    'Основные понятия статики: сила, момент силы, '
    'плечо, центр масс, равновесие, опора, трение, жёсткость, деформация, '
    'устойчивость, рычаг, блок, наклонная плоскость, реакция опоры, пара сил, '
    'линия действия силы, условие равновесия, статически определимая система';

/// Пожелания Test A: короткий prompt-only.
String liveWishesShort({int cards = 3}) {
  return 'Тема: $kLiveTopicShort. Сделай $cards карточки для интервального '
      'повторения, уровень школьного курса.';
}

/// Пожелания Test B: 40 карточек (несколько запросов при малом лимите вывода).
String liveWishesMany({int cards = 40}) {
  return 'Тема: $kLiveTopicMany. Сделай ровно $cards карточек, по одному '
      'чёткому определению или правилу на карточку, без повторов.';
}

/// Разделы небольшого документа Test C (3 смысловых блока).
const List<String> kLiveSmallDocumentSections = <String>[
  'Испарение — переход воды из жидкого состояния в газообразное. '
      'Оно происходит при любой температуре, но с ростом температуры '
      'скорость испарения увеличивается.',
  'Конденсация — обратный процесс: водяной пар превращается в капли '
      'жидкости. В атмосфере конденсация образует облака и туман.',
  'Осадки выпадают, когда капли в облаке укрупняются настолько, что '
      'не могут удерживаться в воздухе. Часть воды возвращается в океан '
      'и на сушу, замыкая круговорот.',
];

/// Небольшой текстовый документ Test C (3 раздела, ~800 символов).
ParsedDocument liveSmallDocument() {
  return _documentFromSections(
    fileName: 'krugovorot-vody.txt',
    format: DocumentFormat.txt,
    sectionTexts: kLiveSmallDocumentSections,
  );
}

/// Test C через **production-парсер** DOCX: проверяет реальное извлечение
/// текста и границы трёх разделов (Heading1), а не только заранее собранный
/// `ParsedDocument`. Программная фикстура — по правилу AGENTS (бинарные файлы
/// в репозиторий не коммитятся).
Future<ParsedDocument> liveSmallDocumentParsed() async {
  final Uint8List docx = buildDocx(
    bodyXml: <String>[
      docxParagraph('Испарение', style: 'Heading1'),
      docxParagraph(kLiveSmallDocumentSections[0]),
      docxParagraph('Конденсация', style: 'Heading1'),
      docxParagraph(kLiveSmallDocumentSections[1]),
      docxParagraph('Осадки', style: 'Heading1'),
      docxParagraph(kLiveSmallDocumentSections[2]),
    ].join(),
  );
  return const DocxParser().parse(docx, fileName: 'krugovorot-vody.docx');
}

/// Большой документ Test D: 8 разделов по ~1000 символов.
///
/// Объём подобран так, чтобы при лимите вывода 8192 токена план делил материал
/// на несколько фрагментов (адаптивное дробление), но сама подготовка не
/// требовала гигабайтов памяти.
ParsedDocument liveBigDocument() {
  final List<String> sections = <String>[
    for (var index = 1; index <= 8; index++) _bigSection(index),
  ];
  return _documentFromSections(
    fileName: 'mehanika-konspekt.txt',
    format: DocumentFormat.txt,
    sectionTexts: sections,
  );
}

/// PNG-вложение Test E (`diagram.png`).
GenerationAttachment livePngAttachment() {
  return GenerationAttachment(
    fileName: 'diagram.png',
    mediaType: AttachmentMediaType.png,
    bytes: pngFixture(width: 320, height: 240),
  );
}

/// PDF с встроенным изображением Test E: парсится тем же `PdfParser`.
///
/// Возвращает документ вместе с изображениями (они попадут в каталог
/// `<images>` и, при Vision, отдельными image-частями запроса).
Future<ParsedDocument> livePdfWithImage() async {
  final Uint8List bytes = buildPdfWithEmbeddedImage(
    text:
        'Схема сил, действующих на тело на наклонной плоскости. '
        'Показаны сила тяжести, нормальная реакция опоры и сила трения.',
    imageBytes: diagramJpeg(),
  );
  return PdfParser().parse(bytes, fileName: 'sily-na-naklonnoy.pdf');
}

/// Собирает `ParsedDocument` из текстов разделов (пустая строка между ними).
ParsedDocument _documentFromSections({
  required String fileName,
  required DocumentFormat format,
  required List<String> sectionTexts,
}) {
  final StringBuffer buffer = StringBuffer();
  final List<ParsedSection> sections = <ParsedSection>[];
  for (var index = 0; index < sectionTexts.length; index++) {
    if (index > 0) buffer.write('\n\n');
    final int start = buffer.length;
    buffer.write(sectionTexts[index].trim());
    sections.add(
      ParsedSection(
        start: start,
        end: buffer.length,
        title: 'Раздел ${index + 1}',
      ),
    );
  }
  return ParsedDocument(
    format: format,
    fileName: fileName,
    text: buffer.toString(),
    sections: sections,
  );
}

/// Один «большой» раздел: понятия, определения и связи.
String _bigSection(int index) {
  return 'Раздел $index. Механика и статика. '
      'Сила — векторная величина, характеризующая действие одного тела на '
      'другое. Момент силы относительно точки равен произведению модуля силы '
      'на плечо. Плечо силы — кратчайшее расстояние от точки до линии действия '
      'силы. Центр масс системы — точка, движение которой описывает движение '
      'системы как целого. Равновесие твёрдого тела требует равенства нулю '
      'суммы сил и суммы моментов сил. Устойчивость равновесия зависит от '
      'положения центра масс относительно площади опоры. Сила трения '
      'препятствует относительному смещению соприкасающихся поверхностей и '
      'направлена вдоль поверхности. Деформация — изменение формы или размеров '
      'тела под действием нагрузки; жёсткость характеризует сопротивление '
      'деформации. '
      'Пример: тело на наклонной плоскости удерживается трением, если '
      'составляющая силы тяжести вдоль плоскости не превышает максимальную '
      'силу трения покоя. '
      'Важно не путать массу и вес: масса — мера инертности, вес — сила '
      'действия тела на опору или подвес. Единицы: ньютон для силы, '
      'килограмм для массы, ньютон-метр для момента силы.';
}
