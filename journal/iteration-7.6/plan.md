# Итерация 7.6 — «Пустой ответ» модели: диагностика и фикс (2026-11-14)

Owner note: экран настроек API и сохранение ключей работают, но при генерации карточек
появляется ошибка «Нейросеть вернула пустой ответ».

## Шаг 1. Диагностика (факты получены командами в этой сессии)

Ключ не выводился: проверка только present/absent (`DEEPSEEK_API_KEY` — present в Windows User scope).

### 1.1 Живой DeepSeek (OpenAI-compatible путь)

| Запрос | HTTP | finish_reason | content | Вывод |
|---|---|---|---|---|
| `deepseek-chat`, strict `response_format: json_schema` | **400** | — | — | DeepSeek не поддерживает `json_schema`: `This response_format type is unavailable now` |
| `deepseek-chat`, fallback без `response_format` | 200 | **stop** | 1296 символов, **обёрнут в ```json … ``` ** | markdown-ограждение подтверждено |
| `deepseek-reasoner`, strict | 400 | — | — | то же ограничение |
| `deepseek-reasoner`, без схемы | 200 | **stop** | 975 символов, чистый JSON | reasoning 1955 токенов |
| production-путь `CardGenerationService`, 22 480 символов материалов, limit=20 | 200 | stop | — | `deepseek-chat` — 12 карточек (7902 токена), `deepseek-reasoner` — 7 карточек |

Вывод: ответы модели **не пустые**; markdown-обёртка уже снимается tolerant-парсером
(`_decodeCardsJson` в `CardGenerationService`, тест есть); `deepseek-reasoner` не выбран в
аккаунте владельца ниже.

### 1.2 Что реально произошло у владельца (drift-БД приложения)

Файл: `%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite` (ключи там не хранятся).

Аккаунт из `app_settings.generation.providers`:
`id=openai_compatible, label=DeepSeek, protocol=openai-completions, base_url=https://api.deepseek.com,
model=deepseek-flash, context_tokens=16000`.

`generation_jobs` — 5 записей, **все `status=done`, `error_code=NULL`, `cards_count=0`**,
`tokens_used` 1249–1609, `chunk_count=1`:

```
21:34:37 deepseek-flash done tokens=1609 cards=0
21:34:47 deepseek-flash done tokens=1426 cards=0
23:06:21 deepseek-flash done tokens=1558 cards=0
23:06:29 deepseek-flash done tokens=1336 cards=0
23:08:25 deepseek-chat  done tokens=1249 cards=0
```

`status=done` + `failures` пусто означает: модель вернула **валидный пустой массив** `{"cards":[]}`
(схема A8.4 пройдена, все фрагменты обработаны). Приложенные файлы:
`1_Характеристика_минералов.pdf`, `2_Приложение_8_Форма_описания_горных_пород.pdf`,
`3_Приложение_9_Метаморфические_горные_породы.pdf`.

### 1.3 Разбор приложенных PDF парсером приложения

```
1_Характеристика_минералов.pdf              pages=1 chars=215
2_Приложение_8_Форма_описания_горных_пород  pages=1 chars=349
3_Приложение_9_Метаморфические_горные_породы pages=1 chars=294
                                              итого 858 символов
```

Превью текста — только шапки таблиц и номера столбцов («№ п/п Окраска / Цвет черты …
1 2 3 4 5 … 25»). Это **пустые бланки-формы**, а не учебный материал: фактов в них нет.

### 1.4 Корневая причина

1. Парсинг ответа LLM **не сломан**: `finish_reason=stop`, ответ валидный `{"cards":[]}`.
2. Модель по правилу 13 промпта («Если материала нет — верни пустой массив cards») вернула
   пустой массив — это корректное поведение на пустом бланке.
3. UI (`lib/ui/generation/generation_screen.dart:374`) показывает на **успешный** пустой
   результат текст `generationErrorEmptyResponse` — «Нейросеть вернула пустой ответ. Попробуйте
   ещё раз». Это вводит в заблуждение: повтор не поможет, причина — материалы без текста.
4. Сопутствующий дефект: `maxOutputTokens` (8192) адаптер OpenAI-compatible **не передаёт** —
   `max_tokens` отсутствует в теле запроса (подтверждено диагностикой: `hasMaxTokens=false`),
   поэтому действует серверный дефолт DeepSeek (4096) — риск обрезания длинных ответов.
5. DeepSeek отклоняет `response_format: json_schema` (400) — fallback без схемы работает, но
   каждый фрагмент тратит пробный запрос.

## Шаг 2. План фикса

| # | Задача | Файлы | Проверка |
|---|---|---|---|
| F1 | Понятное сообщение на пустой результат модели (отличать от пустого ответа провайдера) | `lib/l10n/app_ru.arb`, `lib/ui/generation/generation_screen.dart` | widget-тест: done + 0 карточек → новый текст, старый отсутствует |
| F2 | `max_tokens` в OpenAI-compatible запросе (`maxOutputTokens` = 8192) | `lib/api/providers/openai_compatible_adapter.dart`, `generation_provider_adapter.dart` | unit-тест тела запроса |
| F3 | Лестница совместимости: strict → без `response_format` → без `max_tokens` (по 400) | `lib/api/generation/card_generation_service.dart` | unit-тесты: 2-й запрос без схемы, 3-й без `max_tokens`, не больше трёх |
| F4 | Вынести разбор JSON модели в чистый извлекатель + BOM/fences/текст вокруг | `lib/api/generation/cards_json_extractor.dart` (новый) | unit-тесты, включая ```` ```json { "cards": [] } ``` ```` |
| F5 | Документация и журнал | `docs/api-schema.md`, `docs/decisions/ADR-021-*.md`, `journal/iteration-7.6/*`, `journal/STATE.md`, `journal/KNOWN_LIMITATIONS.md` | — |

## Шаг 3. Тесты (красная фаза)

1. `test/unit/api/generation/cards_json_extractor_test.dart` — markdown-fence (кейс владельца),
   fence без языка, ` ```JSON ` в верхнем регистре, текст до/после, BOM, битый JSON,
   tolerant=false отвергает ограждение.
2. `test/unit/api/providers/openai_compatible_adapter_test.dart` — `max_tokens` = maxOutputTokens,
   `sendMaxTokens=false` → поля нет.
3. `test/unit/api/generation/card_generation_service_test.dart` — лестница fallback: второй
   запрос без `response_format`, третий без `max_tokens`; все 400 → `badRequest`, ровно три запроса.
4. `test/widget/generation/generation_screen_test.dart` — пустой результат модели → новый ARB-текст.

## Риски

- Третий шаг лестницы — защита от серверов, требующих `max_completion_tokens` вместо
  `max_tokens` (OpenAI o-серии через пользовательский base_url). Живых таких серверов в
  окружении нет (L1/L47) — покрыто unit-тестами.
- `response_format: json_schema` у DeepSeek остаётся отклоняемым: пробный strict-запрос
  на каждый фрагмент — записано в `KNOWN_LIMITATIONS.md` (L50).
- Спец-текст `generationErrorEmptyResponse` из SPEC A6.8 не меняется; новый текст — отдельная
  строка ARB для «валидный ответ без карточек».

## Критерии приёмки

- Все новые тесты красные до фикса и зелёные после.
- `fvm flutter test --coverage --exclude-tags golden` — без падений, покрытие ≥80 %.
- `fvm flutter analyze` — 0 issues; `dart format --set-exit-if-changed` — 0 changed.
- Живой DeepSeek-прогон подтверждает: strict → 400, fallback с `max_tokens` → 200, карточки.
- CI зелёный после push.
