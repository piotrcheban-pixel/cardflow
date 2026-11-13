# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 3b «Провайдеры» — **завершена** + расширение ADR-013
(OpenAI-совместимый провайдер) — **завершено, live ожидает ключ** · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; Windows-сборка работает; Android SDK/JDK,
Xcode, Linux — отсутствуют; `DEEPSEEK_API_KEY` в процессе агента отсутствует (present = нет). GitHub
`origin` → piotrcheban-pixel/cardflow; `main` и `origin/main` совпадают (push выполнен).
Итог 3b + ADR-013: **800 тестов зелёные + 1 live skipped**, покрытие **95.1% (4071/4279)**, `analyze` 0,
`format` 0 changed, `build windows --release` ок. **CI:** 3b — run `43501572437` (9/9 success),
расширение ADR-013 — run `43505863077` (9/9 success). Финальный docs-коммит проверяется тем же CI
(статус — в отчёте сессии).

## Следующее действие

1. **Итерация 3c «Экран генерации»** — по отдельной команде владельца (не начинать): экран A6.8,
   drag-n-drop/файловый picker, чанкинг по бюджету модели, оценка токенов, прогресс/отмена, дедупликация,
   `generation_jobs`, предпросмотр и импорт. Слой готов: `CardGenerationService` (+ OpenAI-compatible),
   `ApiKeyStore`, `GenerationSettingsStore`, `GenerationErrorCode`, `truncated`, `CancelToken`.
2. **Live-вызов DeepSeek (L30)** — владелец выбрал переменную окружения `DEEPSEEK_API_KEY`, но в текущем
   процессе её нет (окружение процесса не перечитывается): нужен перезапуск сессии с переменной. Команда
   готова: `fvm flutter test test/live --tags live`. Пока ключа нет — L30 остаётся, «проверено» не заявляется.
3. Открытые вопросы к владельцу — только live-ключ (L30); больше нет.

## Расширение 3b — OpenAI-compatible (ADR-013)

- **Сделано:** провайдер `openaiCompatible` (`openai_compatible`); адаптер — копия логики OpenAI с endpoint
  из `base_url`, опциональным Bearer и отключаемым strict `response_format`; настройки адрес+модель в
  `app_settings` (`generation.openai_compatible`), ключ — только `ApiKeyStore` и опционален; сервис: адрес и
  модель из настроек, при `badRequest` ровно один fallback без `response_format`, извлечение JSON из
  markdown/текста только для compatible; новый код `providerNotConfigured` (+ARB); экран «Настройки
  генерации» (адрес/модель/необязательный ключ, валидация, secure-ключ) + маршрут `/settings/generation`
  + иконка на экране колод; ADR-013, `docs/openai-compatible.md`, обновлён `docs/api-schema.md`.
- **Доказательства:** `test/.../openai_compatible_*` (endpoint/адаптер), 20 сервисных тестов (fallback,
  providerNotConfigured, markdown), integration-срезы production-графа (локальный сервер без ключа;
  DeepSeek strict 400 → fallback), `app_settings` через реальную БД; полный прогон 800 passed + 1 skipped;
  coverage 95.1%; `analyze` 0; `format` 0; `build windows --release` — ок; CI run `43505863077` — 9/9 success.
- **Не проверено:** живой DeepSeek-вызов (L30 — ключ не виден процессу), Ollama/LM Studio (L32 — серверы не
  подняты), платформенный secure storage (L28), cap 429 (L31).

## Итерация 3b — итог

- **Сделано:** канон-схема A8.4 + `json_schema`-валидация + проекции под провайдеров; скрытый промпт
  `gen-ru-v2` и сборка `<materials>/<wishes>/<limit>`; контентные правила A8.4 с пометками; 3 адаптера
  (OpenAI/Gemini/Anthropic) + 4-й OpenAI-compatible (ADR-013); retry/backoff (429 `Retry-After`, 5xx/таймауты,
  4 попытки, 4xx без повторов, отмена прерывает паузу); redaction-перехватчик; ключи только в
  `flutter_secure_storage` (`ApiKeyStore`); сервис генерации; ARB-сообщения 13 кодов; production-проводка
  `app_providers`; ADR-011/012/013, `docs/api-schema.md`, `docs/system-prompt.md`, `docs/dependencies.md` §11.
- **Доказательства:** полный прогон **800 passed / 1 skipped**; `coverage_check --min=80` → 95.1%;
  `analyze` 0; `format` 0 changed; `build windows --release` → `cardflow.exe`; ревью `journal/iteration-3b/review.md`;
  fix-коммиты `81efc9a`, `c7a8099`, `8d8f7d4`; CI run `43501572437` — 9/9 success.
- **Не проверено:** живые провайдеры (L1/L30), платформенный secure storage (L28), cap 429 (L31).

## Итерация 3a — итог (завершена)

- Нативные парсеры A8.3 + `ParsedDocument`; 603 теста; покрытие 95.3%; `analyze` 0; Windows-сборка;
  ревью закрыто fix-коммитом `ecf845a`; L26 закрыт зелёным CI (`43491786199`).
- Не проверено: реальные файлы (L23), 25 МБ/OOM (L25), вложенные таблицы/нумерация (L24), формула без
  кэша (L27).

## Открытые вопросы к владельцу

1. Live-ключ DeepSeek: переменная окружения выбрана, но недоступна процессу — нужен перезапуск сессии с
   `DEEPSEEK_API_KEY` (значение в чат не передавать). До этого L30 остаётся открытым.
2. Команда на старт 3c (после отчёта; 3c не начиналась).

## Известные ограничения (актуальные)

L1 (ключи API), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color —
итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (due-счётчики), L11 (живые диалоги file_picker),
L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15–L17,
L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без requeue), L23 (реальные файлы),
L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула без кэша), **L28** (платформенный
secure storage), **L30** (живые HTTP-контракты, включая DeepSeek/Ollama/LM Studio), **L31** (cap 429),
**L32** (Ollama/LM Studio живьём не проверялись). L29 снят (CI 3b + расширение — зелёные);
L9/L9b/L21/L22/L26 сняты; L2b/L3/L6b сняты ранее.
