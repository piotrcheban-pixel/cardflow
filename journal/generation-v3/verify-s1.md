# Verify — генерация v3, срез 1 (ContentModel документа)

**Дата:** 2026-11-27 · **Срез:** `TASK.txt` «Срез 1. ContentModel: Document →
Section → Block с якорями» · **Снимок:** `main`, от `fbdd1c3` (docs среза 0).

## Что проверялось

Модель содержимого `Document → Section → Block` с якорями, адаптер
`ParsedDocument → ContentModel`, отсев мусора флагом, нормализация сравнения,
восстановление блока по id.

## Красная фаза

`journal/generation-v3/red-s1.txt` — прогон тестов до реализации; падения
assertion-level (например, `Expected: NoiseKind:<NoiseKind.runningHeaderFooter>
Actual: <null>`, `Expected: ['Введение', 'Первый абзац текста.', 'Второй
абзац.'] Actual: []`), а не только ошибка компиляции.

## Гейты итогового снимка

| Команда | Результат |
|---|---|
| `.fvm\versions\3.47.9\bin\flutter.bat analyze --no-pub lib test` | **No issues found!** (0 issues) |
| `.fvm\versions\3.47.9\bin\dart.bat format --set-exit-if-changed lib test` | **623 files — 0 changed** |
| `.fvm\versions\3.47.9\bin\flutter.bat test --no-pub --exclude-tags golden` | **2825 passed + 17 skipped**, `exit 0` |
| baseline до среза | 2801 passed + 17 skipped |
| новые тесты | **+24** (`content_model_test` 13, `content_normalizer_test` 6, `content_model_parsers_test` 5) |

Пять фикстур DoD: PDF (2 страницы, колонтитул + номера + подпись `Fig.`),
DOCX (3 раздела по заголовкам, колонтитул/номер/`Рис.`), PPTX (2 слайда), MD
(один раздел), скан без текстового слоя (`buildScannedPdf` → `scannedPdf` →
**пустая модель без исключения**).

## Известная хрупкость прогона

Первый полный прогон упал на
`test/integration/settings_persistence_file_db_test.dart`:
`TimeoutException after 0:00:30` (файловая drift-БД в OneDrive под нагрузкой
полного прогона). Отдельный прогон файла — зелёный, повторный полный прогон —
зелёный. К срезу 1 отношения не имеет: новые файлы в `lib/api/generation/`
тест не затрагивает.
