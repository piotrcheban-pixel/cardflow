# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 4 «Лента» — **шаг 1 (план) выполнен** · **Режим:** ИТЕРАЦИИ
**Факты (сверено в этой сессии):** HEAD `e5f64c4` == `origin/main` (docs-коммит 3c отправлен на remote;
`git ls-remote origin HEAD` = `e5f64c4`), дерево clean. Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2);
Windows 11; Windows-сборка работает; Android SDK/JDK, Xcode, Linux — отсутствуют.
`DEEPSEEK_API_KEY`: present в Windows User scope, absent в env агента (значение не выводить).
**Baseline (эта сессия, HEAD `e5f64c4`):** `fvm flutter test --exclude-tags golden --reporter compact` →
**897 passed + 1 skipped**, exit 0; `fvm flutter analyze` → **No issues found!**; `fvm dart format
--set-exit-if-changed lib test` → **218 files, 0 changed**.
**CI 3c:** push выполнен (remote = `e5f64c4`), статус прогона для `e5f64c4` не проверялся (private repo,
анонимный доступ → 404; независимой проверки из сессии нет).

## Следующее действие

1. **Шаг 2 — красная фаза** итерации 4: тесты T1–T16 по `journal/iteration-4/plan.md` на скелетах;
   фрагменты «ожидалось/получено» → `journal/iteration-4/red-feed.md`; коммит `test:`.
2. Затем шаги 3–7 итерации 4 (зелёная фаза, ревью, verify, память, ретроспектива).
3. Push — только по отдельной команде владельца.
4. Открытые вопросы к владельцу: нет.

## Итерация 4 — план (шаг 1)

- Спека: A7.3 (лента), A6.3 (лист режимов), A6.4 (каркас), A4.3/A4.4 (формы/пружины/haptics),
  A5 (`review_logs.mode='feed'`); ADR-016.
- Объём: `FeedSessionEngine` + чистая политика свайпов, Stories-прогресс, `FeedCardView` (свайпы,
  spring-back, морфинг формы), `FeedSessionScreen` (PageView, авто-продвижение 3/5/8, пауза, нижняя
  панель), общий каркас A6.4, роут `/decks/:deckId/feed`, лист режимов, ARB.
- Критерии C1–C16 и задачи T1–T19 — в `journal/iteration-4/plan.md`.

## Итерация 3c — итог (завершена, запушена `e5f64c4`)

- Сделано: оценка токенов/чанкинг, `GenerationPipeline`, drift jobs, транзакционный импорт, экран A6.8,
  предпросмотр, входы, ключи API; ADR-015, `docs/generation-pipeline.md`.
- Доказательства: 897 passed/1 skipped; analyze 0; format 0; coverage 93.2%; build windows; ревью
  `journal/iteration-3c/review.md` + `review-fixes.md`.
- Не проверено: живые OpenAI/Gemini/Anthropic (L1), DnD/picker (L11/L33), 25 МБ/OOM (L25), secure
  storage (L28), негативные HTTP (ADR-014); CI-прогон 3c не проверялся.

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
**L33** (реальный DnD-жест не проверялся), **L34** (оценка токенов эвристическая).
