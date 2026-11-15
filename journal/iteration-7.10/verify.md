# Итерация 7.10 — verify (гейты на финальном снимке)

Дата: 2026-11-15. Замечание окружения: `fvm flutter test`/`build` без `--no-pub` зависают
на `dart pub get --example` (сеть pub в сессии агента), поэтому все команды — с `--no-pub`;
зависимости уже разрешены (`.dart_tool/package_config.json` присутствует).

## Red-фаза (assertion-level)

Команда: `fvm flutter test --no-pub <9 файлов>` → **124 passed, 20 failed**; полный вывод —
`journal/iteration-7.10/red-output.txt`. Примеры (ожидалось/получено):

| Тест | Ожидалось | Получено |
|---|---|---|
| `TextSanitizer: C1` | `'abcd'` | `'a\u0080b\u0085c\u009Fd'` |
| `TextSanitizer: одиночные суррогаты` | `'abc'` | `'a\uD800b\uDC00c'` |
| `PdfTextQuality: много замен` | `true` | `false` |
| `PdfParser: символов замены` | `ParserException(garbledText)` | `ParsedDocument` |
| `PdfParser: C1` | `'Hello CardFlow'` | `'Hello\u0080\u0085\u009F CardFlow'` |
| prompt-test `image_query` | contains «Не добавляй картинки и image_query…» | фрагмент отсутствует |
| `buildGenerationUserContent: пустые материалы` | валидный запрос | `ArgumentError` |
| pipeline `prompt-only` | 1 вызов модели | 0 (noMaterials) |
| service `prompt-only` | пустой `<materials>` | `ArgumentError`/noMaterials |
| диагностика HTTP/сервиса/картинок | sink непустой | пусто |
| widget `старт только с темой` | `runCalls == 1` | 0 |

## Green/verify

| Гейт | Команда | Результат |
|---|---|---|
| Полный прогон | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **1409 passed + 3 skipped** (live без ключа в env) |
| Покрытие | `fvm dart run tool/coverage_check.dart --min=80` | **92.9 % (9393/10114)**, порог пройден |
| Анализатор | `fvm flutter analyze --no-pub` | `No issues found!` |
| Формат | `fvm dart format lib test` + `--set-exit-if-changed lib test` | 334 файла / **0 changed** |
| Windows-сборка | `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (63,9 с) |

## Live-проверки (ключ из Windows User scope; значение не печаталось)

`fvm flutter test --no-pub test/live --tags live` → **3 passed**:

1. `LIVE DeepSeek OK: model=deepseek-chat, cards=3, tokens=1467`
2. `LIVE DeepSeek fallback: strict=400, tolerant=200, max_tokens=8192, cards=2`
3. `LIVE DeepSeek prompt-only: cards=3, image_query=3, prompt=gen-ru-v4, tokens=1502`
   — генерация **без файлов** по теме и `image_query` во всех трёх карточках (правило 14
   промпта v4 работает на живой модели).

## Спайки и живые ограничения

- PDFium (программные фикстуры, `test/unit/api/parsers/`): `buildPdf('\u0080\u0081\u0082')`
  → `codeUnits [128,129,130]`; Type0/ToUnicode → `[65533,…]` и `[55296,…]` — подтверждён корень
  бага «PDF → неожиданный ответ».
- Живой Openverse с хоста агента: HEAD 200, полный GET > 20 с (curl 40–90 с), thumbnail не
  скачался — `ImageSearchService` возвращает `null` (L61). Проводка «image_query → сервис →
  картинка → media» подтверждена интеграционным тестом с реальным сервисом и fake-Dio.
- Живые проблемные PDF/Word владельца недоступны — программные фикстуры (L64).

## Артефакты

`plan.md`, `red-output.txt` (red-фаза, 20 падений), `review.md`, `verify.md`, `summary.md`.
