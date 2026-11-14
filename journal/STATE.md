# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 4 «Лента» — **завершена (шаги 1–7)** · **Режим:** ИТЕРАЦИИ
**Факты (сверено в этой сессии):** локальный HEAD — docs-коммит итерации 4 (`docs: complete iteration 4
verification and memory`); `origin/main` = `e5f64c4` (итерация 3c), push итерации 4 не выполнялся —
локальная ветка впереди на 7 коммитов.
Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; Windows-сборка работает; Android SDK/JDK,
Xcode, Linux — отсутствуют. `DEEPSEEK_API_KEY`: present в Windows User scope, absent в env агента
(значение не выводить).
**Проверено в этой сессии (`1857589`):** `fvm flutter test --coverage --exclude-tags golden` →
**959 passed + 1 skipped** (baseline 897 → +62); покрытие **93.6% (5788/6181)** (feed-файлы 95.8–100%);
`fvm flutter analyze` → No issues; `fvm dart format --set-exit-if-changed lib test` → 229 files, 0 changed;
`fvm flutter build windows --release` → `cardflow.exe` (51,9 s).
**CI:** прогон итерации 4 — после push; для 3c статус не проверялся (private repo, анонимно 404).

## Следующее действие

1. **Итерация 4 завершена (шаг 7).** Отчёт владельцу; push — по отдельной команде.
2. **Следующая по плану — итерация 5 «Occlusion / Cloze / LaTeX»** (маски, раскрытие,
   `flutter_math_fork`, fallback разметки, редактор масок) — только по отдельной команде владельца.
3. **CI-прогон итерации 4** — после push; до этого статус неизвестен.
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
