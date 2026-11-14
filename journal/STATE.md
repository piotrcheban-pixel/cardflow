# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 6 «Конструктор сессии» — **шаг 3 (зелёная фаза UI) выполнен** ·
**Режим:** ИТЕРАЦИИ
**Факты (сверено командами в этой сессии):** `git status --short` → пусто; `HEAD =
ca1e2b69d8b0e4b78005c5ac1066df7988ff437e` до старта итерации; запись прежнего STATE «HEAD = origin/main =
9bd09ad» устарела на один docs-коммит и исправлена. `fvm flutter test --exclude-tags golden` на старте →
**1020 passed + 1 skipped**; после зелёной фазы домена/данных → **1069 passed + 1 skipped**; после зелёной
фазы UI → **1095 passed + 1 skipped**, `analyze` 0, `format` применён. Flutter 3.47.9 / Dart 3.13.7 (FVM);
Windows 11; Android SDK/JDK/Xcode/Linux — отсутствуют (L2). Независимый reviewer недоступен (L35).

## Следующее действие

1. **Шаг 4 — ревью Lead** на неизменяемом снимке зелёной фазы: чек-лист (границы фильтров, порядок
   операций сборки, гонки таймера лимита минут, ARB-only тексты, безопасность пресетов, дублирование
   логики сессий); отчёт `journal/iteration-6/review.md`; high/medium — fix-коммит с тестом на находку.
2. Затем шаг 5 (verify: coverage, build windows), шаг 6 (summary/STATE/AGENTS), шаг 7 (ретроспектива).
3. Итерация 6 без остановки внутри идёт до шага 7, затем отчёт владельцу и стоп.
4. Открытые вопросы к владельцу: нет.

## Итерация 6 — сделано

- Домен: `SessionConfig` (JSON `version=1`, валидация), `SessionBuilder` (фильтры, базовый порядок,
  разминка ≤4 выученных, интерливинг round-robin, перемешивание по seed, лимит карточек/минут),
  `SessionPlan`, `SessionPreset`; порты пресетов и счётчиков провалов (ADR-018).
- Данные: `DriftSessionPresetRepository` (`session_presets`, без миграций), `DriftLeechRepository`
  (`review_logs.rating = 1`, порог 8), провайдеры в `app_providers`.
- UI: экран A6.7 (`lib/ui/session/session_constructor_screen.dart`), маршруты `/constructor`,
  `/session/classic`, `/session/feed`, пункт «Конструктор» в листе режимов колоды, план в экранах
  классики и ленты (`prebuilt`), лимит минут через таймер экрана, состояние «Сессия не найдена».
- Тесты: domain/data unit, prebuilt-движки, 13 widget-тестов конструктора, плановые сессии
  классики/ленты, интеграция на production-графе и реальной drift-БД (4 теста).


## Итерация 5 — итог (завершена, запушена)

- Сделано: occlusion/cloze/LaTeX (ADR-017), редактор масок, медиа-транзакции, общий рендер карточек.
- Доказательства: 1020 passed/1 skipped; coverage 93.1% (6468/6946); analyze 0; format 0;
  build windows; ревью `journal/iteration-5/review.md` (M1–M4 закрыты `0e4e11b`); CI 9/9 (`9bd09ad`).
- Не проверено: golden (L6), screen-reader (L12/L38), реальные picker/рисование (L11/L38/L39).

## Итерация 4 — итог (завершена, запушена `e90f660`)

`FeedSessionEngine`, политика свайпов, Stories, `FeedCardView`, `FeedSessionScreen`, лист режимов,
`/decks/:deckId/feed`; ADR-016. 959 passed/1 skipped; coverage 93.6%; CI 9/9. Не проверено: L36/L37.

## Итерация 3c — итог (завершена, запушена `e5f64c4`)

Пайплайн генерации, `generation_jobs`, экран A6.8, предпросмотр, ключи API; ADR-015. 897 passed;
coverage 93.2%; CI 9/9. Не проверено: L1, L11/L33, L25, L28, ADR-014.

## Итерация 3b — итог (завершена)

Схема A8.4, адаптеры провайдеров, retry/backoff, redaction, `ApiKeyStore`, production-проводка;
ADR-011/012/013. 800 passed/1 skipped; coverage 95.1%; CI 9/9. Не проверено: L1, L28, ADR-014, L32.

## Итерация 3a — итог (завершена)

Нативные парсеры A8.3 + `ParsedDocument`; 603 теста; coverage 95.3%; ревью `ecf845a`; L26 закрыт
зелёным CI. Не проверено: L23, L24, L25, L27.

## Известные ограничения (актуальные)

L1 (ключи OpenAI/Gemini/Anthropic), L2 (только локальные сборки — CI их покрывает), L4 (хуки),
L5 (навыки), L6 (golden), L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (desktop_drop 0.8.4),
L10 (due-счётчики), L11 (живые диалоги file_picker), L12 (screen-reader/golden M3E),
L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15, L16 (L17 снят startup-GC),
L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без requeue), L23 (реальные файлы),
L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула без кэша),
**L28** (платформенный secure storage), **L30** (живые HTTP-контракты: success DeepSeek пройден,
остальные открыты), **L31** (cap 429), **L32** (Ollama/LM Studio не проверялись),
**L33** (реальный DnD-жест не проверялся), **L34** (оценка токенов эвристическая),
**L35** (независимый reviewer итераций 4–6 недоступен), **L36** (авто-продвижение при покрытии
маршрутом), **L37** (реальный свайп-жест не проверялся), **L38/L39** (реальные picker/рисование масок,
screen-reader масок). Ограничений «CI/пуш не выполнялись» больше нет.
