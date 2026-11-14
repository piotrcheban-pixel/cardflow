# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 5 «Occlusion / Cloze / LaTeX» — **шаг 3 завершён** · **Режим:** ИТЕРАЦИИ
**Факты (сверено в этой сессии):** рабочее дерево было чистым; `HEAD = origin/main =
8dfa6e5d29aed3a5a1805d6ebc6f96c84ebf3065`; последние 5 коммитов — docs/handoff после итерации 4.
Прежняя запись об `origin/main = e5f64c4` и 7 незапушенных коммитах устарела и исправлена по git.
Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Windows-сборка работает; Android SDK/JDK, Xcode, Linux —
отсутствуют. Каталог `journal/iteration-5/` отсутствовал: внешняя реализация в репозиторий не поступала.
**Базовый прогон:** `fvm flutter test --exclude-tags golden` → **959 passed + 1 skipped**.
По новой команде владельца 2026-11-14 DSH продолжает итерацию 5; прежний handoff «DSH не начинать» отменён
этой командой. План — `journal/iteration-5/plan.md`; технические развилки — ADR-017.
**Шаги 1–3:** план/ADR-017 (`88bf2e9`), красная фаза (`2df06dd`, доказательства `journal/iteration-5/red.md`),
зелёная реализация. Полный прогон: **1013 passed + 1 skipped**; покрытие **92.8% (6443/6942)**;
`analyze` — 0 issues; `format` — 252 files, 0 changed. Детали — `journal/iteration-5/green.md`.

## Следующее действие

1. **Шаг 4 (ревью):** независимый reviewer в дереве агентов отсутствует; Lead-ревью по чек-листу на
   неизменяемом снимке green-коммита. Все high/medium — отдельным fix-коммитом с тестом на находку.
2. Затем шаг 5 verify (повторные гейты + Windows release), шаг 6 remember и шаг 7 improve.
3. Push не выполнять без отдельной команды владельца.
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

L1 (ключи OpenAI/Gemini/Anthropic), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden),
L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (desktop_drop 0.8.4), L10 (due-счётчики),
L11 (живые диалоги file_picker), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят),
L14 (длины при импорте), L15–L17, L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без
requeue), L23 (реальные файлы), L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула
без кэша), **L28** (платформенный secure storage), **L30** (живые HTTP-контракты: success DeepSeek
пройден, остальные открыты), **L31** (cap 429), **L32** (Ollama/LM Studio не проверялись),
**L33** (реальный DnD-жест не проверялся), **L34** (оценка токенов эвристическая),
**L35** (независимый reviewer итерации 4 недоступен), **L36** (авто-продвижение при покрытии
маршрутом), **L37** (реальный свайп-жест не проверялся).
