# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 3c «Экран генерации» — **завершена** (шаги 1–7) · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; Windows-сборка работает;
Android SDK/JDK, Xcode, Linux — отсутствуют. `DEEPSEEK_API_KEY`: present в Windows User scope,
absent в унаследованном env агента (значение не выводить). GitHub `origin` →
piotrcheban-pixel/cardflow; `main` = локальный HEAD `9db83ab` (push не выполнялся).
**Проверено в сессии 2026-11-14 (HEAD `9db83ab`, дерево clean):** `fvm flutter test --exclude-tags golden`
→ **897 passed + 1 skipped**; `fvm flutter analyze` → No issues; `fvm dart format --set-exit-if-changed
lib test` → 0 changed; coverage 93.2% (5219/5597); `fvm flutter build windows --release` → `cardflow.exe`.
Ревью: 2 high, 12 medium, 11 low; H/M закрыты fix-коммитом `9db83ab` с новыми тестами.
**CI:** 3b/ADR-013/live L30/host-facts — 9/9 success (`43501572437`, `43505863077`, `43510331361`,
`43511718280`); прогон 3c — после push.

## Следующее действие

1. **Итерация 3c завершена.** Отчёт владельцу; push — по отдельной команде.
2. **Следующая по плану — итерация 4 «Лента»** (PageView, жесты, Stories-прогресс, авто-продвижение,
   haptic, возврат пружиной) — **только по отдельной команде владельца**.
3. **CI-прогон 3c** — после push; до этого статус CI для `9db83ab` неизвестен.
4. Открытые вопросы к владельцу: нет.

## Итерация 3c — итог

- Сделано: оценка токенов/бюджеты моделей, чанкинг по разделам с `<limit>`, `GenerationPipeline`
  (последовательные вызовы, прогресс/отмена, split-once, дедуп, partial/retry, `generation_jobs`),
  drift job-репозиторий, транзакционный импорт (reversed, дедуп), файловый шлюз 25 МБ, экран A6.8,
  предпросмотр с чекбоксами/редактированием, входы с «Колод»/«Колоды», ключи API трёх провайдеров;
  ADR-015, `docs/generation-pipeline.md`.
- Доказательства: 897 passed/1 skipped; analyze 0; format 0; coverage 93.2%; build windows; ревью
  `journal/iteration-3c/review.md` + `review-fixes.md`; интеграционный production-граф генерации/импорта.
- Не проверено: живые OpenAI/Gemini/Anthropic (L1), реальный DnD/picker (L11/L33), 25 МБ/OOM (L25),
  secure storage на платформе (L28), негативные HTTP-контракты (ADR-014); CI после push.

## Итерация 3b — итог (завершена)

Схема A8.4 + `json_schema`, проекции провайдеров, промпт `gen-ru-v2`, контент-валидатор, 3 адаптера +
OpenAI-compatible (ADR-013), retry/backoff, redaction, `ApiKeyStore`, `CardGenerationService`, ARB,
production-проводка; ADR-011/012/013. 800 passed/1 skipped; coverage 95.1%; CI 9/9. Не проверено:
живые OpenAI/Gemini/Anthropic (L1), платформенный secure storage (L28), негативные HTTP (ADR-014),
Ollama/LM Studio (L32). DeepSeek success — L30 (пройден).

## Итерация 3a — итог (завершена)

Нативные парсеры A8.3 + `ParsedDocument`; 603 теста; покрытие 95.3%; analyze 0; Windows-сборка;
ревью закрыто `ecf845a`; L26 закрыт зелёным CI `43491786199`. Не проверено: реальные файлы (L23),
25 МБ/OOM (L25), вложенные таблицы/нумерация (L24), формула без кэша (L27).

## Известные ограничения (актуальные)

L1 (ключи OpenAI/Gemini/Anthropic), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden),
L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (desktop_drop 0.8.4), L10 (due-счётчики),
L11 (живые диалоги file_picker), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят),
L14 (длины при импорте), L15–L17, L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без
requeue), L23 (реальные файлы), L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула
без кэша), **L28** (платформенный secure storage), **L30** (живые HTTP-контракты: success DeepSeek
пройден, остальные открыты), **L31** (cap 429), **L32** (Ollama/LM Studio не проверялись),
**L33** (реальный DnD-жест не проверялся), **L34** (оценка токенов эвристическая).
