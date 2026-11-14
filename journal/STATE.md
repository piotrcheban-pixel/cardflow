# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 5 «Occlusion / Cloze / LaTeX» — **завершена (шаги 1–7), запушена, CI зелёный** · **Режим:** ИТЕРАЦИИ
**Факты (сверено в этой сессии):** рабочее дерево чистое; `HEAD = origin/main =
9bd09ad22693d6bed8194825addc90d74c0cdfb1`. Итерация 5 — 7 коммитов на GitHub: `88bf2e9`, `2df06dd`,
`5af8f70`, `0e4e11b`, `9681790`, `8d8f415`, `9bd09ad`. Прежние записи «push не выполнялся» и
«CI итерации 5 не запускался» устарели и исправлены по `git` и GitHub API.
**CI:** прогон [`43612309379`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43612309379)
на коммите `9bd09ad` — **success, 9/9 job** (`format + analyze`, `test` × 3 ОС, `build desktop` × 3,
`build mobile` Android + iOS). Репозиторий переведён в **Public**, биллинг GitHub починен владельцем.
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Windows-сборка работает; Android SDK/JDK, Xcode, Linux —
отсутствуют (локальные сборки — L2; CI их покрыл).
**Шаги 1–3:** план/ADR-017 (`88bf2e9`), красная фаза (`2df06dd`, доказательства `journal/iteration-5/red.md`),
зелёная реализация (`5af8f70`). Полный прогон того шага: **1013 passed + 1 skipped**; покрытие
**92.8% (6443/6942)**; `analyze` 0; `format` 252 files, 0 changed (`journal/iteration-5/green.md`).
**Шаг 4:** независимого reviewer нет (L35); Lead-ревью снимка `5af8f70` — high нет, M1–M4 закрыты
`0e4e11b` с тестами на каждую находку (`journal/iteration-5/review.md`). L17 снят, добавлены L38/L39.
**Шаг 5:** финальные гейты — `format` 253/0; `analyze` 0; **1020 passed + 1 skipped**; покрытие
**93.1% (6468/6946)**; Windows release `cardflow.exe` за 56,2 с (`journal/iteration-5/verify.md`).
**Шаги 6–7:** `summary.md`, `handoff-info.md`, `docs/archive-format.md`, ADR-009 addendum; ретроспектива —
`journal/iteration-5/improve.md`; устойчивые правила внесены в `AGENTS.md`.

## Следующее действие

1. Итерация 5 завершена, запушена и подтверждена зелёным CI (9/9). Работа остановлена по режиму ИТЕРАЦИИ.
2. Ждём отдельной команды владельца на старт итерации 6 «Конструктор» (SPEC B2/A6.7/A7.20): фильтры,
   пресеты `session_presets`, перемешивание/интерлинг/разминка, передача выборки в движки ADR-008/016.
3. Итерацию 6 без команды не начинать.
4. Открытые вопросы к владельцу: нет.

## Итерация 4 — итог

- Сделано: `FeedSessionEngine` (очередь, visit без записи, rate/undo mode=feed, авто-продвижение без
  оценки, завершение по всем оценённым, гонка индекса закрыта), политика свайпов (80 px/300 px·с⁻¹,
  >60% ширины), Stories-прогресс с пульсацией, `FeedCardView` (spring-back, форма 28→16→pill, 3D-flip,
  haptics A7.2, семантика), `FeedSessionScreen` (PageView, 3/5/8 с + пауза + lifecycle, нижняя панель,
  клавиши), общий каркас A6.4 `review_chrome.dart`, лист режимов и `/decks/:deckId/feed`.
- Доказательства: 959 passed/1 skipped; coverage 93.6%; analyze 0; format 0; build windows; ревью
  `journal/iteration-4/review.md` (H1+M1–M4 закрыты `1857589`), verify/summary, ADR-016.
- Не проверено: CI после push, реальные жесты (L37), таймер при покрытии маршрутом (L36), golden (L6),
  полный screen-reader (L12); независимый reviewer недоступен (L35).

## Итерация 3c — итог (завершена, запушена `e5f64c4`)

- Сделано: оценка токенов/чанкинг, `GenerationPipeline`, drift jobs, транзакционный импорт, экран A6.8,
  предпросмотр, входы, ключи API; ADR-015, `docs/generation-pipeline.md`.
- Доказательства: 897 passed/1 skipped; analyze 0; format 0; coverage 93.2%; build windows; ревью
  `journal/iteration-3c/review.md` + `review-fixes.md`.
- Не проверено: L1, L11/L33, L25, L28, ADR-014; CI-прогон 3c не проверялся.

## Итерация 3b — итог (завершена)

Схема A8.4 + `json_schema`, проекции, промпт `gen-ru-v2`, контент-валидатор, 3 адаптера + OpenAI-compatible
(ADR-013), retry/backoff, redaction, `ApiKeyStore`, `CardGenerationService`, ARB, production-проводка;
ADR-011/012/013. 800 passed/1 skipped; coverage 95.1%; CI 9/9. Не проверено: L1, L28, ADR-014, L32.

## Итерация 3a — итог (завершена)

Нативные парсеры A8.3 + `ParsedDocument`; 603 теста; покрытие 95.3%; analyze 0; Windows-сборка; ревью
закрыто `ecf845a`; L26 закрыт зелёным CI `43491786199`. Не проверено: L23, L25, L24, L27.

## Известные ограничения (актуальные)

L1 (ключи OpenAI/Gemini/Anthropic), L2 (только локальные сборки — CI их покрывает), L4 (хуки), L5 (навыки), L6 (golden),
L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (desktop_drop 0.8.4), L10 (due-счётчики),
L11 (живые диалоги file_picker), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят),
L14 (длины при импорте), L15, L16 (L17 снят startup-GC), L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без
requeue), L23 (реальные файлы), L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула
без кэша), **L28** (платформенный secure storage), **L30** (живые HTTP-контракты: success DeepSeek
пройден, остальные открыты), **L31** (cap 429), **L32** (Ollama/LM Studio не проверялись),
**L33** (реальный DnD-жест не проверялся), **L34** (оценка токенов эвристическая),
**L35** (независимый reviewer итераций 4–5 недоступен), **L36** (авто-продвижение при покрытии
маршрутом), **L37** (реальный свайп-жест не проверялся), **L38/L39** (реальные picker/рисование масок,
screen-reader масок). Ограничений «CI/пуш не выполнялись» больше нет.
