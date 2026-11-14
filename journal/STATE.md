# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Итерация:** 7 «Статистика + настройки» — **шаг 1 (план)** ·
**Режим:** ИТЕРАЦИИ
**Факты (сверено командами в этой сессии):** `git status --short` → пусто; `HEAD = origin/main =
b2293cc6ac0f931f008e313f2790dd10d5afad1c` (docs: remember session constructor iteration). Прежняя запись
«итерация 6 не запушена» устарела — исправлена: push выполнен, CI run
[43618351413](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43618351413) — conclusion success.
Базовый прогон: `fvm flutter test --exclude-tags golden` → **1102 passed + 1 skipped** (совпадает с итогом
итерации 6). Flutter 3.47.9 / Dart 3.13.7 (FVM); Windows 11; Android SDK/JDK/Xcode/Linux — нет (L2).
Независимый reviewer недоступен (L35).

## Следующее действие

1. Шаг 2 итерации 7: красная фаза — домен/данные настроек (`AppSettings`, drift-store) и статистики
   (`StatisticsCalculator`, `DriftStatisticsRepository`) + widget-спецификации экранов A6.5/A6.6 и оболочки A6.1.
2. Затем шаги 3–7 итерации 7 (зелёная фаза, ревью Lead, verify, память, ретроспектива); push — по команде владельца.
3. Открытые вопросы к владельцу: нет.

## Итерация 7 — план (SPEC A6.1/A6.5/A6.6, B2)

- Домен/данные: `AppSettings` (JSON `version=1` в `app_settings`), `AppSettingsStore` + drift-реализация;
  статистика за 365 дней (удержание, тепловая карта, слабые темы, прогноз 7 дней, недельный прогресс,
  токены за неделю) — `StatisticsCalculator` + `DriftStatisticsRepository` (схема БД не меняется).
- UI: оболочка A6.1 (`NavigationBar` / `NavigationRail`, «Сессия» скрыта без активной сессии),
  экран «Статистика» A6.5, экран «Настройки» A6.6 (внешний вид, API, обучение, доступность, о приложении).
- Действие настроек: тема/dynamic color/шрифт дислексии/размер текста/контраст; haptics; motion
  (Выразительная/Стандартная); desired retention и шаги обучения → `FsrsScheduler`; дневные лимиты →
  `ReviewQueue`; модель по умолчанию → экран генерации. «Тренировать» слабой темы → конструктор с тегом.
- Проверки: статистика на реальной drift-БД, настройки в `app_settings`, интеграция production-графа,
  guard-тесты, полный прогон/покрытие/анализ/формат/сборка Windows.

## Итерация 6 — итог (завершена, запушена `b2293cc`, CI success)

Конструктор сессии (ADR-018): домен `SessionBuilder`/`SessionConfig`/`SessionPlan`, drift-порт пресетов и
пиявок, экран A6.7, маршруты `/constructor` (`?deck=`), `/session/classic`, `/session/feed`, `prebuilt`-план
в классике и ленте, лимит минут таймером. 1102 passed/1 skipped; coverage 93.1% (7236/7772); analyze 0;
format 269/0; build windows; ревью Lead `70b1d97` (M1–M3 закрыты `0bdc0ab`). Не проверено: L35, L40–L42.

## Итерация 5 — итог (завершена, запушена `9bd09ad`, CI 9/9 `43612309379`)

Occlusion/cloze/LaTeX (ADR-017), редактор масок, медиа-транзакции, общий рендер карточек.
1020 passed/1 skipped; coverage 93.1% (6468/6946); ревью M1–M4 закрыты `0e4e11b`.

## Итерация 4 — итог (завершена, запушена `e90f660`, CI 9/9)

Лента (ADR-016), политика свайпов, Stories, `FeedCardView`, `/decks/:deckId/feed`. 959 passed/1 skipped.

## Итерация 3c — итог (завершена, запушена `e5f64c4`, CI 9/9)

Пайплайн генерации, `generation_jobs`, экран A6.8, предпросмотр, ключи API; ADR-015.

## Итерация 3b — итог (завершена, CI 9/9)

Схема A8.4, адаптеры провайдеров, retry/backoff, redaction, `ApiKeyStore`, production-проводка; ADR-011/012/013.

## Итерация 3a — итог (завершена, CI 9/9)

Нативные парсеры A8.3 + `ParsedDocument`; 603 теста; coverage 95.3%; L26 закрыт зелёным CI.

## Известные ограничения (актуальные)

L1 (ключи OpenAI/Gemini/Anthropic), L2 (только локальные сборки — CI их покрывает), L4 (хуки),
L5 (навыки), L6 (golden), **L6c** (dynamic color: код и переключатель в итерации 7, реальная ОС — не проверено),
L7 (.doc/.xls), L8 (desktop_drop 0.8.4), L10 (due-счётчики), L11 (живые диалоги file_picker),
L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15,
L16 (L17 снят startup-GC), L18 (neighbor-squish), L19 («Новые» vs очередь), L20 (сессия без requeue),
L23 (реальные файлы), L24 (вложенные таблицы DOCX/нумерация), L25 (25 МБ/OOM), L27 (формула без кэша),
**L28** (платформенный secure storage), **L30** (живые HTTP-контракты: success DeepSeek пройден),
**L31** (cap 429), **L32** (Ollama/LM Studio не проверялись), **L33** (реальный DnD-жест не проверялся),
**L34** (оценка токенов эвристическая), **L35** (независимый reviewer итераций 4–7 недоступен),
**L36** (авто-продвижение при покрытии маршрутом), **L37** (реальный свайп-жест не проверялся),
**L38/L39** (реальные picker/рисование масок, screen-reader масок), **L40–L42** (лимит минут, память
конструктора, ручная приёмка).
