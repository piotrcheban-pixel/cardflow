# Итерация 7.6 — «Пустой ответ» LLM: диагностика, фикс, тесты (2026-11-14)

**Статус:** завершена; push `5925ea0..2ddacc6`, CI run
[`43637919516`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43637919516) — **9/9 job success**.

## Что было (owner note)

Экран настроек API и сохранение ключей работают, но при генерации карточек появляется
«Нейросеть вернула пустой ответ». Задача: диагностика и фикс разбора ответов LLM.

## Диагностика (факты команд, ключ не выводился)

| Проверка | Результат |
|---|---|
| `deepseek-chat`, strict `response_format: json_schema` | **HTTP 400** `This response_format type is unavailable now` |
| `deepseek-chat`, без схемы | **200**, `finish_reason=stop`, content 1296 симв. **в ```json … ```** |
| `deepseek-reasoner`, strict / без схемы | 400 / **200**, `finish_reason=stop`, чистый JSON (reasoning 1955 ток.) |
| production `CardGenerationService`, 22 480 симв., limit=20 | 200: `deepseek-chat` — 12 карточек, `deepseek-reasoner` — 7 |
| `generation_jobs` в drift-БД владельца | 5 записей: **все `done`, `error_code=NULL`, `cards_count=0`**, токены 1249–1609 |
| аккаунт в `app_settings` | `deepseek`, протокол `openai-completions`, model `deepseek-flash`, context 16000 |
| приложенные PDF (парсер приложения) | 3 файла, 858 символов суммарно — **шапки таблиц и номера столбцов** (пустые бланки) |

**Корневая причина:** ответ модели не пуст и не битый — это валидный `{"cards":[]}` по правилу 13
промпта (в PDF нет фактов). Ошибку показывал UI: на успешный пустой результат выводилась строка
«Нейросеть вернула пустой ответ. Попробуйте ещё раз». Сопутствующие дефекты: `max_tokens` вообще не
доходил до провайдера, а strict-схема DeepSeek отклоняется (лишний пробный запрос на фрагмент).

## Что сделано

1. **`max_tokens`** в OpenAI-совместимом запросе = `maxOutputTokens` (8192). Нативные адаптеры без
   изменений (Anthropic/Gemini передают по контракту, OpenAI — нет).
2. **Лестница совместимости** (только `openai-completions`, только по `badRequest`): strict+`max_tokens`
   → без схемы+`max_tokens` → без схемы и `max_tokens`. Не больше трёх запросов; локальная проверка
   A8.4 на любом шаге. Контракт `buildRequest` получил `bool sendMaxTokens = true`.
3. **`CardsJsonExtractor`** (`lib/api/generation/cards_json_extractor.dart`): BOM, markdown-ограждение
   (```` ```json … ``` ````, ```` ``` ````, регистр), пояснительный текст вокруг JSON; tolerant — только
   для совместимого протокола (как и раньше). Логика вынесена из сервиса без изменения поведения.
4. **UI:** пустой `cards` → новая строка ARB `generationNoCardsFound` («Модель не нашла в материалах
   фактов для карточек. Проверьте, что в файлах есть текст (не скан и не пустая форма); если текст
   есть — смените модель»). `generationErrorEmptyResponse` остаётся за кодом `emptyResponse`.
5. **Live-тест** живого контракта DeepSeek: strict → 400, fallback → 200 с `max_tokens=8192`.
6. **Проверка подключения** (`ApiKeyVerifier`) — минимальный совместимый запрос: без strict-схемы и
   без `max_tokens` (`sendMaxTokens: false`), чтобы серверы, требующие `max_completion_tokens`, не
   давали ложный отказ при рабочей генерации.
7. Документы: `docs/decisions/ADR-021-compatible-empty-response.md`, `docs/api-schema.md` (v3),
   `journal/KNOWN_LIMITATIONS.md` (L50, L51), `AGENTS.md` (слой API).

## Красная фаза (фрагмент вывода, `journal/iteration-7.6/red-phase.txt`)

```
openai_compatible_adapter_test.dart: max_tokens передаётся … [E]
  Expected: <4096>
    Actual: <null>
card_generation_service_test.dart: все три запроса 400 → badRequest, не больше трёх [E]
  Expected: <3>
    Actual: <2>
generation_screen_test.dart: модель вернула валидный пустой массив … [E]
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Модель не нашла в материалах фактов для
```

Примечание: извлекатель JSON вынесен механическим рефакторингом (поведение прежнее) и сразу получил
BOM-обработку — для него красная фаза ограничилась новыми тестами, падающими на assertion в остальных
четырёх файлах.

## Доказательства (команды этой сессии)

| Команда | Результат |
|---|---|
| `fvm flutter test --coverage --exclude-tags golden` | **1270 passed + 2 skipped** (live без ключа в env) |
| `fvm dart run tool/coverage_check.dart` | **92.6 % (8772/9469)**, порог 80 пройден |
| `fvm flutter analyze` | `No issues found!` |
| `fvm dart format lib test integration_test` | 319 файлов, 1 changed → повтор `--set-exit-if-changed` 0 changed |
| `fvm flutter build windows --release` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (61,8 с) |
| `fvm flutter test test/live --tags live` (ключ из User scope) | **2 passed**: `LIVE DeepSeek OK: … cards=3`; `LIVE DeepSeek fallback: strict=400, tolerant=200, max_tokens=8192, cards=2` |
| CI run [`43637919516`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43637919516) (`2ddacc6`) | **9/9 job success**: format+analyze, test × 3 ОС, build-desktop × 3, build-mobile Android + iOS |

## Не проверено

- Третий шаг лестницы на живом сервере, требующем `max_completion_tokens` (L51) — unit-тесты.
- Повторный strict-запрос DeepSeek на каждый фрагмент остаётся (L50): кэш возможностей сервера — post-MVP.
- Приёмочный прогон в GUI владельцем (генерация из PDF-бланков теперь даёт понятное сообщение).

## ADR итерации

- `docs/decisions/ADR-021-compatible-empty-response.md`.
