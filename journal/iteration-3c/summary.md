# Итерация 3c — «Экран генерации». Итог

**Дата:** 2026-11-14 · **Режим:** ИТЕРАЦИИ · **Ветка:** `main` · **Коммиты:** `79c7e44` (план),
`475651c` (red), `7dbfbf6` (ядро), `37ac05b` (UI), `f407384` (тесты), `9db83ab` (fix ревью)
**Цель SPEC:** A6.8 (экран генерации), A8.5 (пайплайн), A8.6 (безопасность/ошибки), A6.2/A6.3 (входы).

## Сделано

- **Домен:** `TokenEstimator` (≈2,5 символа/токен), каталог моделей и бюджеты входа, `GenerationChunker`
  (разделы → абзацы → строки → жёсткое деление; `<limit>` 20 карточек; split-once по runes),
  `GenerationJob`/`GenerationJobRepository`, `DocumentGateway`, `GenerationCardStore`.
- **API:** `GenerationPipeline` — задание `running` → оценка/чанкинг → последовательные вызовы с
  прогрессом/отменой → split при `truncated` → дедупликация между фрагментами и с колодой →
  `done/partial/error/cancelled`; fatal-политика; `retryFailed`; `unexpected`-маркировка при сбое БД.
- **Данные:** drift-репозиторий `generation_jobs` (только имена файлов), импорт карточек одной транзакцией
  (дедуп, `basic_reversed` — две строки с `sibling_id`, `state=new`, `content_hash`), `file_picker`-шлюз
  с лимитом 25 МБ и уникальными memory-путями.
- **UI:** экран A6.8 (DnD/picker, файлы со статусами и удалением, пожелания, провайдер/модель, имя колоды,
  оценка токенов, прогресс/отмена/Back, ошибки ARB), предпросмотр (чекбоксы, инлайн-редактирование,
  пометки A8.4, импорт всех/выбранных/отмена, частичный успех + повтор), входы с «Колод» (Split-меню) и
  «Колоды» (Toolbar + меню), роуты `/generate`, `/decks/:id/generate`; блок «Ключи API» на экране настроек.
- **Документация:** ADR-015, `docs/generation-pipeline.md`, `docs/dependencies.md` (факт desktop_drop),
  журналы `plan/red-generation/review/review-fixes/verify/summary`, `STATE.md`, `AGENTS.md`,
  `KNOWN_LIMITATIONS.md` (L33).

## Доказательства

- `fvm flutter test --exclude-tags golden` → **897 passed + 1 skipped** (exit 0).
- `fvm flutter analyze` → **No issues found!**
- `fvm dart format --set-exit-if-changed lib test` → **0 changed**.
- `fvm flutter test --coverage` + `coverage_check --min=80` → **93.2% (5219/5597)**.
- `fvm flutter build windows --release` → `cardflow.exe`.
- Независимое ревью: 2 high, 12 medium, 11 low; H/M закрыты fix-коммитом `9db83ab` с новыми тестами.
- Интеграционный production-граф: генерация → `generation_jobs` → импорт → колода; повторная генерация
  отсеивает существующие карточки.

## ADR итерации

- **ADR-015** — бюджеты/оценка токенов, чанкинг и `<limit>`, каталог моделей, fatal/partial/split-once,
  дедупликация и транзакционный импорт, `generation_jobs`, ключи трёх облачных провайдеров на настройках,
  локализация слов, заданных SPEC (API/Word/Excel/PowerPoint/cloze/X).

## Не проверено / известные ограничения

- Живые OpenAI/Gemini/Anthropic — нет ключей (L1); DeepSeek — L30 (3b, success пройден).
- Реальный DnD/picker на ОС (L11/L23/L33), 25 МБ/OOM (L25), платформенный secure storage (L28),
  негативные HTTP-контракты (ADR-014).
- Точная оценка токенов — эвристика; фактический расход — из ответа.
- CI-прогон 3c — после push по команде владельца.

## Следующее действие

Итерация 3c завершена (шаг 7). Следующая по плану — **итерация 4 «Лента»** — только по отдельной
команде владельца. Push — по команде владельца.
