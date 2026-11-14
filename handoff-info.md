# Handoff — итерация 5 CardFlow (Occlusion / Cloze / LaTeX)

**Дата:** 2026-11-14 · **От:** DSH Lead · **Кому:** внешний агент (Kimi) · **Режим DSH:** ИТЕРАЦИИ,
итерация 4 завершена, **итерацию 5 DSH не начинает**.

## 1. HEAD и CI

- **HEAD на момент передачи:** `33993f4` (`docs: complete iteration 4 verification and memory`),
  последний коммит итерации 4; handoff-коммит — `4ef3038` (`docs: hand off iteration 5 to external agent`).
- **`origin/main`:** `4ef3038` — push итерации 4 + handoff выполнен 2026-11-14 (было `e5f64c4`).
- **CI итерации 4:** run [`43587472135`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43587472135)
  (commit `4ef3038`) — **9/9 job success** (format+analyze, test × ubuntu/windows/macos, build linux/windows/
  macos/android/ios). CI итерации 3c — run `43583803312` (commit `e5f64c4`) — 9/9 success.
- Локальные гейты итерации 4 зелёные: `fvm flutter test --coverage --exclude-tags golden` → **959 passed +
  1 skipped**, покрытие **93.6% (5788/6181)**, `analyze` 0, `format` 0 changed, Windows release — `cardflow.exe`.
- Актуальный status — вкладка Actions репозитория; workflow — `.github/workflows/ci.yml` (push/PR,
  matrix ubuntu/windows/macos, 9 job'ов, `concurrency: cancel-in-progress`).

## 2. Ключевые архитектурные решения (ADR)

| ADR | Решение |
|---|---|
| [`ADR-001`](<docs/decisions/ADR-001-m3e-library.md>) | M3 Expressive — `material_3_expressive` только через `lib/ui/m3e/`; Material-виджеты — `package:material_ui/material_ui.dart` |
| [`ADR-002`](<docs/decisions/ADR-002-state-management.md>) | Riverpod 3 без кодогенерации |
| [`ADR-003`](<docs/decisions/ADR-003-doc-xls.md>) | `.doc`/`.xls` не поддерживаются, понятное сообщение |
| [`ADR-004`](<docs/decisions/ADR-004-fsrs-config.md>) | Конфигурация FSRS (retention/шаги/детерминизм) |
| [`ADR-005`](<docs/decisions/ADR-005-database-opening-migrations.md>) | drift: открытие БД, миграции |
| [`ADR-006`](<docs/decisions/ADR-006-zip-archive-format.md>) | Формат `.zip` экспорта/импорта (`format_version`) |
| [`ADR-007`](<docs/decisions/ADR-007-m3e-integration-deck-list-semantics.md>) | Интеграция M3E и семантика списка колод |
| [`ADR-008`](<docs/decisions/ADR-008-classic-session.md>) | Классическая сессия: очередь, запись каждой оценки в транзакции, undo, единая точка выхода |
| [`ADR-009`](<docs/decisions/ADR-009-manual-card-editor.md>) | Ручной редактор карточек: поля, типы, валидация, неизменность типа |
| [`ADR-010`](<docs/decisions/ADR-010-parsers.md>) | Парсеры документов, `ParsedDocument`, SecureZip, PDFium |
| [`ADR-011`](<docs/decisions/ADR-011-generation-providers.md>) | Провайдеры генерации, канон-схема ответа |
| [`ADR-012`](<docs/decisions/ADR-012-http-resilience-secrets.md>) | HTTP retry/backoff, redaction, секреты |
| [`ADR-013`](<docs/decisions/ADR-013-openai-compatible-provider.md>) | OpenAI-compatible провайдер, настройки, опциональный ключ |
| [`ADR-014`](<docs/decisions/ADR-014-live-verification-scope.md>) | Объём живой проверки HTTP (негативные контракты не гоняются) |
| [`ADR-015`](<docs/decisions/ADR-015-generation-pipeline.md>) | Пайплайн генерации: токены/чанкинг, jobs, импорт, partial/retry |
| [`ADR-016`](<docs/decisions/ADR-016-feed-mode.md>) | Лента: отдельный движок, пороги свайпов, Stories, авто-продвижение 3/5/8, `mode='feed'` |

Для итерации 5 важны: **ADR-009** (форма карточки), **ADR-016** (общий каркас и лента), **ADR-010/015**
(LaTeX-проверка уже в `latex_checker.dart`), **ADR-005** (поля `occlusion_json`/`latex` уже в схеме),
**ADR-001** (никакого WebView, LaTeX — только `flutter_math_fork`).

## 3. Известные ограничения, которые нужно учесть

- **L35 — независимый reviewer итерации 4 недоступен.** В DSH-сессии не было reviewer-подагента; ревью
  сделал Lead по чек-листу на снимке `0c244c6`, H1+M1–M4 закрыты `1857589`. Внешнему агенту стоит
  провести независимое ревью своей итерации (или зафиксировать, что его нет).
- **L36 — авто-продвижение в ленте не останавливается, если поверх открыт другой маршрут** (push),
  хотя приложение в `resumed`. Жизненный цикл приложения таймер останавливает, покрытие маршрутом — нет;
  оценок при этом не пишется, данные не теряются, меняется только текущая страница. Не ломать это
  поведение без ADR/теста; при доработке — `RouteAware`/навигационный наблюдатель.
- **L37 — реальный свайп мышью/пальцем на устройстве не проверялся.** Политика жестов покрыта
  12 unit-тестами и widget-тестами pointer events; ручной прогон на Windows/Android/iOS — за приёмкой.
- Дополнительно для итерации 5: **L6** (golden на Linux CI), **L12** (screen-reader), **L17** (GC медиа —
  occlusion-изображения!), **L18** (neighbor-squish), **L20** (без requeue), **L23/L25** (реальные файлы/
  большие размеры), **L28** (платформенный secure storage). Полный список — [`KNOWN_LIMITATIONS.md`](<journal/KNOWN_LIMITATIONS.md>).

## 4. Что входит в итерацию 5 (SPEC)

- **A7.8 Image Occlusion:** изображение + маски (прямоугольник/эллипс в MVP), тап раскрывает,
  «Показать все»/«Скрыть все»; **обязательный редактор масок** в форме карточки — загрузка изображения,
  рисование, удаление, сохранение в `occlusion_json`; оценка как в классике.
- **A7.9 Cloze:** `{{c1::…}}`, тап-подстановка, несколько пропусков — раскрытие по одному; синтаксис
  проверяется валидатором A8.4.
- **A7.10 LaTeX:** `flutter_math_fork`, `$…$` и `$$…$$` (без `\(…\)`), пошаговое раскрытие, при ошибке —
  текст + предупреждение «Ошибка разметки формулы», карточка не исчезает.
- Рендер — в классике и ленте (это типы/разметка карточек, **не режимы**; в листе режимов их нет).
- Не делать post-MVP (аудио/TTS/STT, экзамен, цейтнот, спидран, синхронизация) и не добавлять WebView.

## 5. Правила проекта (кратко)

- Все команды — через FVM: `fvm flutter test`, `analyze`, `dart format lib test`, `gen-l10n`.
- TDD: red → green; coverage ≥80%; guard-тесты (`no_webview`, `ru_strings`, `no_secrets`,
  `architecture_test`) не ослаблять.
- Текст UI — только `AppLocalizations` из `lib/l10n/app_ru.arb`; локаль только `ru`.
- Секреты — только `ApiKeyStore`; не логировать тела запросов/ответов; не печатать ключи.
- Коммиты — conventional (английский префикс, тело по-русски); push — по команде владельца.
- ADR при конфликте/неоднозначности SPEC; `journal/STATE.md` — единственная память между сессиями.

## 6. Открытые вопросы

Нет.
