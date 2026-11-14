# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 3c «Экран генерации» — **в работе** · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; Windows-сборка работает;
Android SDK/JDK, Xcode, Linux — отсутствуют. `DEEPSEEK_API_KEY`: present в Windows User scope,
absent в унаследованном env агента (для live-прогона передавать из реестра дочернему процессу;
значение не печатать). GitHub `origin` → piotrcheban-pixel/cardflow; `main` = `origin/main`.
**Проверено в сессии 2026-11-14 (HEAD `3878777`, дерево clean):** `fvm flutter test --exclude-tags golden`
→ **800 passed + 1 skipped**; `fvm flutter analyze` → No issues; `fvm dart format --set-exit-if-changed
lib test` → 0 changed. HEAD `3878777` — docs-only (ADR-014), код с `2d83caf` не менялся.
Покрытие 95.1% и `build windows --release` — из прогона 3b, в этой сессии не перемерялись.
**CI:** 3b/ADR-013/live L30/host-facts — 9/9 job success (прогоны `43501572437`, `43505863077`,
`43510331361`, `43511718280`); прогон для 3c — в отчёте итерации.

## Следующее действие

1. **Итерация 3c — шаг 1 (план) выполнен:** `journal/iteration-3c/plan.md`, ADR-015,
   `docs/generation-pipeline.md`. Дальше — **шаг 2, красная фаза**: тесты T1–T20 на скелетах,
   фрагменты «ожидалось/получено» в `journal/iteration-3c/red-generation.md`.
2. После красной фазы — зелёная по слоям (домен → API → данные → UI → проводка), затем ревью,
   verify, память, шаг 7.
3. Открытые вопросы к владельцу: нет; live-границы — ADR-014, команда на старт 3c получена.

## Итерация 3c — что входит (кратко)

A6.8: файлы (picker + DnD), пожелания, провайдер/модель, имя колоды, оценка токенов, генерация с
прогрессом/отменой, предпросмотр с чекбоксами и инлайн-редактированием, импорт all/selected/cancel,
частичный успех и повтор упавших. A8.5: бюджет/чанкинг, split-once, дедупликация, `generation_jobs`,
импорт одной транзакцией. Входы с «Колод» и «Колоды». ADR-015.

## Итерация 3b — итог (завершена)

- Схема A8.4 + `json_schema`, проекции провайдеров, промпт `gen-ru-v2`, контент-валидатор, 3 адаптера +
  OpenAI-compatible (ADR-013), retry/backoff, redaction, `ApiKeyStore`, `CardGenerationService`, ARB,
  production-проводка `app_providers`; ADR-011/012/013.
- Доказательства: 800 passed / 1 skipped; coverage 95.1%; analyze 0; format 0; build windows; CI 9/9.
- Не проверено: живые OpenAI/Gemini/Anthropic (L1); платформенный secure storage (L28);
  негативные HTTP-контракты (ADR-014); Ollama/LM Studio (L32). DeepSeek success — L30 (пройден).

## Итерация 3a — итог (завершена)

Нативные парсеры A8.3 + `ParsedDocument`; 603 теста; покрытие 95.3%; analyze 0; Windows-сборка;
ревью закрыто `ecf845a`; L26 закрыт зелёным CI `43491786199`. Не проверено: реальные файлы (L23),
25 МБ/OOM (L25), вложенные таблицы/нумерация (L24), формула без кэша (L27).

## Открытые вопросы к владельцу

1. Нет. Команда на 3c получена; live-границы закрыты ADR-014.

## Известные ограничения (актуальные)

L1 (ключи OpenAI/Gemini/Anthropic), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden),
L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (desktop_drop 0.8.4), L10 (due-счётчики),
L11 (живые диалоги file_picker), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят),
L14 (длины при импорте), L15–L17, L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без
requeue), L23 (реальные файлы), L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула
без кэша), **L28** (платформенный secure storage), **L30** (живые HTTP-контракты: success DeepSeek
пройден 2026-11-14, остальные открыты), **L31** (cap 429), **L32** (Ollama/LM Studio не проверялись).
