# Итерация 7.11 — verify (финальные гейты)

**Дата:** 2026-11-15 · Хост: Windows 11 · Flutter 3.47.9 / Dart 3.13.7 (FVM)

## Гейты

| Гейт | Команда | Результат |
|---|---|---|
| Полный прогон | `fvm flutter test --no-pub --coverage --exclude-tags golden` | **1458 passed + 4 skipped**, 0 failed (3:49) |
| Покрытие | `coverage/lcov.info` | рукописный код **92.0 % (10316/11216)**; всего 11150/14376 (77.6 %) — сгенерированный `app_database.g.dart` не считается |
| Покрытие новых файлов | — | Wikimedia 100 %, practice_queue 100 %, review_limits 100 %, practice engine 93.6 %, practice repository 92.6 %, practice screen 86.4 %, pipeline 95.2 %, pdf renderer 89.7 % |
| Анализатор | `fvm flutter analyze --no-pub` | **No issues found!** |
| Формат | `fvm dart format --set-exit-if-changed lib test` | **0 changed** (349 файлов) |
| Release-сборка | `fvm flutter build windows --release --no-pub` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (79,3 с) |
| Windows-смоук (реальный процесс) | `fvm flutter test integration_test/session_smoke_windows_test.dart -d windows` | **All tests passed** (1:04) |
| Запуск приложения | `fvm flutter run -d windows --no-pub` | Debug-сборка 67,2 с, окно открылось, Impeller/VM Service, ошибок старта нет |

## Windows-смоук: что именно проверено

`integration_test/session_smoke_windows_test.dart` (реальная Windows-сессия, файловая
SQLite, настоящий `MediaStore`, настоящий парсинг ответа Wikimedia, fake HTTP вместо сети):

1. `GenerationPipeline` (production-граф) по теме: модель → `image_query` →
   `CompositeCardImageFinder` → Wikimedia-разбор → скачивание → `GeneratedCard.image`.
2. Импорт карточки: файл иллюстрации **на диске** совпадает с PNG побайтно; у новой
   карточки `due`/`fsrs_json` заполнены (ADR-026).
3. Дневной лимит новых исчерпан (20 «новых» логов за сегодня): «Начать сессию» →
   «Классический» → сообщение «Дневной лимит исчерпан — откройте «Тренировку»…»,
   без пустой сессии.
4. «Начать сессию» → «Тренировка»: экран тренировки, front карточки, **видимая
   иллюстрация** (`card-content-image`), раскрытие ответа, оценка «Знаю».
5. В `review_logs` появилась ровно одна строка `mode='practice'`; `cards.state`,
   `cards.due`, `cards.fsrs_json` карточки не изменились.

## Живые проверки (ключ DeepSeek — только present, значение не выводилось)

`fvm flutter test --no-pub test/live --tags live` (модель по умолчанию `deepseek-chat`):

| Live-тест | Результат |
|---|---|
| Базовый вызов (схема A8.4) | `LIVE DeepSeek OK: model=deepseek-chat, cards=3, tokens=1601` |
| strict → tolerant fallback (ADR-021) | `strict=400, tolerant=200, max_tokens=8192, cards=2` |
| prompt-only + `image_query` (gen-ru-v4) | `cards=3, image_query=3, tokens=1552` |
| **PDF-скан: 3 PNG-страницы как image parts (7.11)** | `LIVE DeepSeek scan OK: pages=3, cards=2, tokens=2905` |
| **Wikimedia Commons: русский запрос (7.11)** | `jpeg, bytes=97201, attribution=… Diego Delso · CC BY-SA 4.0` |

Итого — **5 passed**. С `DEEPSEEK_MODEL=deepseek-flash` те же провайдерные сценарии
дали 3 passed / 2 failed (`invalidResponse`: ответ не соответствует strict-схеме A8.4) —
модель-зависимая строгость, зафиксировано L66.

## Воспроизведение owner-note до фикса (фактические данные приложения)

- БД владельца (`%APPDATA%\ru.example\cardflow\cardflow\cardflow.sqlite`, копия для
  чтения): 43 карточки `state='new'` **с `due IS NULL` и `fsrs_json IS NULL`**;
  за 15.11 — 30 оценок «новых» (`actual_days IS NULL`) при `daily_new_limit = 20`;
  в новой колоде «цуа» — 4 карточки с PNG-файлами, созданные за минуту до сессии.
- Значит `ReviewQueue.build(cards, newLimit: 0)` пуст, а экран колоды проверял
  очередь без лимитов → пустая сессия «Нет карточек к повторению».
- Openverse: первый GET 200, последующие — таймаут; Wikimedia: 1–2 с и релевантные
  изображения по русским запросам.

## Ограничения локальных гейтов

- Android/iOS сборки и живые Vision-провайдеры (OpenAI/Gemini/Anthropic) — по-прежнему
  CI/ключи (L1, L2, L47, L52, L68).
- Ручные клики владельца на его БД не выполнялись (L67); Windows-смоук заменяет
  ручную приёмку на реальном процессе, но не заменяет UX-взгляд владельца.
