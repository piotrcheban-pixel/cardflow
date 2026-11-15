# Итерация 7.10 — ревью Lead (чек-лист, L35)

Снимок для ревью — зелёная фаза после полного прогона; независимый reviewer в сессии
недоступен (L35), поэтому чек-лист ведёт Lead. Findings закрываются до verify.

## Чек-лист

| # | Проверка | Итог |
|---|---|---|
| 1 | SPEC A6.8/A8.1: поля необязательны, режимы и тексты — из ARB | ✅ файлы необязательны, все строки ARB, `generationTopicRequired`/`parserErrorGarbledText` |
| 2 | Домен без Flutter, `lib/api/` без Flutter | ✅ `TextSanitizer`/`PdfTextQuality`/`GenerationDiagnostics` — чистый Dart |
| 3 | Промпт скрыт, версия пишется в `generation_jobs.prompt_version` | ✅ `gen-ru-v4`, тест и live-прогон |
| 4 | Тела запросов не логируются; ключи не утекают | ✅ debug-only sink, редакция `sk-…`/`AIza…`/`Bearer`, лимит 2000, no-op в release |
| 5 | Сырые ошибки не в UI | ✅ только `GenerationErrorCode`/`ParserErrorCode` → ARB |
| 6 | Схема БД/`format_version` не менялись | ✅ миграций нет |
| 7 | Производственная проводка исправлений | ✅ `test/integration/generation_flow_test.dart` (prompt-only, real `ImageSearchService`), `generation_pipeline_test.dart` (400 → ARB + диагностика) |
| 8 | Тесты не ослаблены | ✅ старые noMaterials-тесты уточнены под новый контракт (добавлено `wishes: null`), число проверок не уменьшено; покрытие 92.9 % |
| 9 | Guard-тесты (webview/ru/no-secrets/architecture) | ✅ полный прогон зелёный |
| 10 | Отмена/прогресс/partial не затронуты | ✅ пайплайн изменён только добавлением фрагмента и оценки |

## Findings

| # | Уровень | Находка | Фикс |
|---|---|---|---|
| D1 | medium | `generationNoCardsFound` («Модель не нашла в материалах фактов… Проверьте, что в файлах есть текст») вводит в заблуждение в prompt-only: файлов нет, тема есть | строка ARB переписана под оба входа: файлы **или** тема |
| D2 | low | В `docs/system-prompt.md` строка правила 14 длиннее остальных (перенос после «Не добавляй картинки и image_query») | перенос сохранён в одном абзаце, читаемость не влияет на поведение; зафиксировано в docs |
| D3 | low | `PdfTextQuality.utf8Normalized` вызывается из `isUnreadable` и повторно — не вызывается; лишнего прохода нет | замечание снято при чтении кода |
| D4 | low | В `GenerationScreen` оценка токенов пересчитывается на каждый ввод символа темы (`setState`) | объём текста мал, `TokenEstimator` — арифметика O(n); профилирование не требуется |

D1 закрыт fix-коммитом с обновлением ARB и `gen-l10n`; D2/D3/D4 — зафиксированы как
принятые (low, без изменения кода).
