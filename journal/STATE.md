# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 3b «Провайдеры» — **завершена** (шаги 1–7; verify — `journal/iteration-3b/verify.md`) · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; Windows-сборка работает; Android SDK/JDK,
Xcode, Linux — отсутствуют; ключей API нет (absent). GitHub `origin` → piotrcheban-pixel/cardflow;
локальный `main` = `origin/main` + коммиты L26-доков и итерации 3b (**не запушены** — push по команде владельца).
Итог 3b: **745 тестов зелёные**, покрытие **95.0% (3808/4007)**, `analyze` 0, `format` 0 changed,
`build windows --release` ок; ревью — 0 blocker/critical/high, 2 medium + 10 low закрыты fix-коммитами.
CI 3b не выполнялся (L29).

## Следующее действие

1. **Итерация 3c «Экран генерации»** — по отдельной команде владельца: экран A6.8, drag-n-drop/файловый
   picker, чанкинг по бюджету модели, оценка токенов, прогресс/отмена, дедупликация, `generation_jobs`,
   предпросмотр и импорт. Слой 3b готов: `CardGenerationService`, `ApiKeyStore`, `GenerationErrorCode`,
   `truncated`, `CancelToken`.
2. Push коммитов 3b — по команде владельца (только тогда пойдёт CI-прогон; L29).
3. Открытые вопросы к владельцу — нет.

## Итерация 3b — итог

- **Сделано:** канон-схема A8.4 + `json_schema`-валидация + проекции под 3 провайдеров; скрытый промпт
  `gen-ru-v2` и сборка `<materials>/<wishes>/<limit>`; контентные правила A8.4 с пометками; 3 адаптера
  (OpenAI/Gemini/Anthropic); retry/backoff (429 `Retry-After`, 5xx/таймауты, 4 попытки, 4xx без повторов,
  отмена прерывает паузу); redaction-перехватчик (заголовки/URI редактируются, тела не логируются);
  ключи только в `flutter_secure_storage` (`ApiKeyStore`); сервис генерации; ARB-сообщения 12 кодов;
  production-проводка `app_providers`; ADR-011/012, `docs/api-schema.md`, `docs/system-prompt.md`,
  `docs/dependencies.md` §11.
- **Доказательства:** `fvm flutter test --exclude-tags golden` → 745; `coverage_check --min=80` → 95.0%;
  `analyze` 0; `format` 0; `build windows --release` → `cardflow.exe`; ревью `journal/iteration-3b/review.md`;
  fix-коммиты `81efc9a`, `c7a8099`, `8d8f7d4` (medium #2/#1 + lows #5–#12 с новыми тестами/документацией).
- **Не проверено:** живые провайдеры (L1/L30), платформенный `flutter_secure_storage` (L28), CI 3b (L29),
  cap 429 — осознанное отступление (L31).

## Итерация 3a — итог (завершена)

- Нативные парсеры A8.3 + `ParsedDocument`; 603 теста; покрытие 95.3%; `analyze` 0; Windows-сборка;
  ревью закрыто fix-коммитом `ecf845a`; L26 закрыт зелёным CI (`43491786199`).
- Не проверено: реальные файлы (L23), 25 МБ/OOM (L25), вложенные таблицы/нумерация (L24), формула без
  кэша (L27).

## Открытые вопросы к владельцу

Нет. Новых зависимостей/платных пакетов нет; SPEC не менялся; удаление функций не предлагалось.
Нужна команда на push и/или старт 3c.

## Известные ограничения (актуальные)

L1 (ключи API), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color —
итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (due-счётчики), L11 (живые диалоги file_picker),
L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15–L17,
L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без requeue), L23 (реальные файлы),
L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула без кэша), **L28** (платформенный
secure storage), **L29** (CI 3b после push), **L30** (живые HTTP-контракты провайдеров), **L31** (cap 429).
L9/L9b/L21/L22/L26 сняты; L2b/L3/L6b сняты ранее.
