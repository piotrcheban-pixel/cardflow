# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 3b «Провайдеры» — шаг 2 (красная фаза) · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; Windows-сборка работает; Android SDK/JDK,
Xcode, Linux — отсутствуют; ключей API нет (absent). GitHub `origin` → piotrcheban-pixel/cardflow;
локальный `main` = `origin/main` + 1 docs-коммит L26 (`68812ff`, не запушен — push по команде владельца).
Baseline итерации 3b: `fvm flutter test --exclude-tags golden` → **603 теста зелёные**, дерево clean.
CI: последний зелёный — [`43491786199`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43491786199)
(9/9; L26 снят). CI итерации 3b не выполнялся (нет push).

## Следующее действие

1. **3b, шаг 2:** красная фаза — тесты T1–T22 по `journal/iteration-3b/plan.md` + скелеты типов
   (`UnimplementedError`), прогон и фрагменты «ожидалось/получено» в `journal/iteration-3b/red-api.md`,
   коммит `test:`.
2. Затем зелёная фаза по слоям (домен → схема/промпт → адаптеры → http → валидатор/сервис → UI-маппинг →
   проводка), ревью на снимке, verify, память. Push — только по команде владельца.

## Итерация 3b — план (шаг 1 выполнен)

- План: `journal/iteration-3b/plan.md` (C1–C15, T1–T25). Спайки: `journal/iteration-3b/spikes.md`
  (S1 `json_schema` 5.2.2 — A8.4 валидируется; S2 `Math.tex(...).parseError` — проверка LaTeX;
  S3 fake `HttpClientAdapter` Dio).
- ADR-011 (канон-схема + проекции, адаптеры, локальная валидация, коды ошибок, промпт);
  ADR-012 (retry/backoff/таймауты/отмена, redaction логов, хранение ключей);
  `docs/api-schema.md`, `docs/system-prompt.md`; `docs/dependencies.md` §11.
- Граница: чанкинг/токены/дедупликация/`generation_jobs`/экран A6.8 — итерация 3c; live-вызовы — L1.

## Итерация 3a — итог (завершена)

- Нативные парсеры A8.3 (`lib/api/parsers/`) + `ParsedDocument`; 595→603 теста; покрытие 95.3%;
  `analyze` 0; Windows-сборка; ревью закрыто fix-коммитом `ecf845a`; L26 закрыт зелёным CI.
- Не проверено: реальные файлы (L23), 25 МБ/OOM (L25), вложенные таблицы/нумерация (L24), формула без
  кэша (L27).

## Открытые вопросы к владельцу

Нет. Платных зависимостей нет; SPEC не менялся; удаление функций не предлагалось. Push фикса L26 был
разрешён ранее; для 3b push не запрашивался — CI-прогон 3b ждёт команды владельца.

## Известные ограничения (актуальные)

L1 (ключи API), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color —
итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (due-счётчики), L11 (живые диалоги file_picker),
L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15–L17,
L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без requeue), L23 (реальные файлы),
L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула без кэша). L9/L9b/L21/L22/L26
сняты; L2b/L3/L6b сняты ранее.
