# Итерация 3a — «Парсеры». Спайки (шаг 1, до плана)

**Дата:** 2026-11-13 · **Файл:** `test/spike/parser_spike_test.dart` (временный, после спайка удалён; вывод ниже)
**Команда:** `fvm flutter test test/spike/parser_spike_test.dart` → `00:00 +5: All tests passed!`

## S-ENC — кодировки (`enough_convert` 1.7.1)

- `Windows1251Codec` и `Koi8rCodec` (именно `Koi8rCodec`, не `Koi8RCodec`) есть в `package:enough_convert/enough_convert.dart`.
- Roundtrip encode→decode для «Привет, мир! Ёлка и ёжик» — OK; `name` кодеков: `windows-1251`, `KOI8-R`.
- Ограничение: `encode` бросает `FormatException` на символах вне карты (напр. `«` в windows-1251-энкодере);
  для фикстур это не критично (фикстуры собираем из букв/пунктуации, проверенных в тесте), DECODE — без ограничений.
- Вывод: `S-ENC: OK, codecs: windows-1251, KOI8-R`.

## S-OOXML — `archive` + `xml` 7.0.1 (DOCX/PPTX/ODT/ручной XLSX)

- `ZipDecoder().decodeBytes` + `findFile('word/document.xml')` — OK.
- В `xml` 7.0.1 у `XmlElement` нет значения в `.value` (возвращает null): текст берём `element.innerText`.
- Вывод: `S-OOXML: paragraphs = [Первый абзац, Второй абзац]`.

## S-XLSX — `excel_plus` 2.29.2 и кэшированные формулы

- Минимальный XLSX (inlineStr + formula с `<v>`) декодируется: `sheets = [Лист1]`.
- `A1` → `Вопрос`, `B1` → `41`.
- `B2` → **`FormulaCellValue`**, `toString()` = `B1+1` (формула!), а **`cachedValue` = `'42'`** — кэш из `<v>`
  доступен и именно его нужно использовать (SPEC A8.3: «формулы — по кэшированному значению»).
- Вывод: `S-XLSX: B2 runtimeType=FormulaCellValue`; `cachedValue == '42'` — assert прошёл.

## S-PDF — `pdfrx` 2.12.0: текстовый слой

- Минимальный PDF с `BT /F1 24 Tf ... (Hello CardFlow PDF) Tj ET` собран программно (xref считается по смещениям).
- `pdfrxInitialize()` (Dart-вариант из `package:pdfrx/pdfrx.dart`, без Flutter-binding) + `PdfDocument.openData(bytes)`
  → `pages=1`, `page.loadText().fullText == 'Hello CardFlow PDF'`.
- Вывод: `S-PDF: pages=1`, `S-PDF: fullText=Hello CardFlow PDF`.

## S-PDF-isolate — PDF-парсинг в отдельном изоляте

- `Isolate.run(() async { pdfrxInitialize(); PdfDocument.openData(...); page.loadText(); ... })` — **работает**:
  `S-PDF-isolate: text=Isolate PDF Text`.
- Вывод: PDF можно парсить в изоляте (как и остальные форматы) — спец-исключений по A8.3 «тяжёлые файлы в изоляте» не нужно.
  Внутри изолята используется Dart-инициализация pdfrx (`pdfrxInitialize`), Flutter-инициализация (`pdfrxFlutterInitialize`)
  не требуется, т.к. виджеты pdfrx не используются.

## Что это меняет в плане

1. `ParsedDocument`/`ParserException`/нормализация — чистый Dart.
2. DOCX/PPTX/ODT — `archive`+`xml`, текст узлов через `innerText`.
3. XLSX — `excel_plus`: `FormulaCellValue → cachedValue`, остальные `CellValue.toString()`.
4. PDF — `pdfrx` (`pdfrxInitialize` в изоляте), ошибка скана = пустой извлечённый текст.
5. Fixtures — генерируем программно в тестах (PDF/DOCX/PPTX/ODT/XLSX/RTF/TXT-кодировки) — бинарные файлы не коммитим.

## Риски, выявленные спайком

- `pdfrx` тянет нативные PDFium (Dart native assets) — тесты с PDF-парсером будут собирать/грузить pdfium на каждой ОС CI;
  впервые это проверится в CI-прогоне итерации 3a (локально Windows — спайк зелёный). Если на какой-то ОС CI упадёт —
  фиксируем `KNOWN_LIMITATIONS` и тег `pdf`/skip по платформе, но цель — зелёные тесты на всех трёх ОС.
- `enough_convert` ENCODE ограничен картой символов — для фикстур использовать только символы, покрытые картой.
