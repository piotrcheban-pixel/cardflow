# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 3a «Парсеры» — **в работе**, шаг 2 (красная фаза) · **Предыдущая:** 2 «Классический режим» завершена; CI-хотфикс «No space left on device» закрыт зелёным прогоном · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; локальная Windows-сборка работает; Android SDK/JDK, Xcode, Linux — отсутствуют; ключей API нет (absent). GitHub-remote `origin` → piotrcheban-pixel/cardflow; локальный `main` = `origin/main` (HEAD `ff32590` + коммиты итерации 3a), рабочее дерево clean. **Последний CI — зелёный:** прогон [`43468349877`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43468349877) attempt 4 — все 9 job success (quality, test×3, build linux/windows/macos/android/ios). В `build android` фикс диска дал 13G → 23G свободного места, `flutter build apk` собрался; `build ios` получил раннер с 4-й попытки (job перезапускался, label не менялся). Push — по команде владельца.

## Следующее действие

Итерация 3a, шаг 2 (красная фаза): фикстуры `test/unit/api/parsers/fixtures/document_fixtures.dart`, тесты T1–T15/T18 и скелеты типов/парсеров → прогон, фрагменты «ожидалось/получено» в `journal/iteration-3a/red-parsers.md` → коммит `test:`. План — `journal/iteration-3a/plan.md`, решение — `ADR-010`, спайки — `journal/iteration-3a/spikes.md` (5/5 зелёные).

## CI-хотфикс после итерации 2 — закрыт

- **Падение:** аннотация check-run `build android` прогона [`43451932776`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43451932776) — `System.IO.IOException: No space left on device : '/home/runner/actions-runner/cached/2.338.2/_diag/Worker_20261113-160553-utc.log'` (упал сам раннер; `test (macos-latest)` не получил раннер — GitHub capacity).
- **Фикс `7d124aa`:** `Free disk space` во всех 4 job'ах до `flutter pub get` (Linux: dotnet/android SDK/ghc/boost/CodeQL + `docker image prune --all`; macOS: Android SDK/Homebrew cache/dotnet), `df -h` до/после; Android SDK сохраняется в android-job (`KEEP_ANDROID_SDK`); `rm -rf ~/.gradle/caches` перед Android-сборкой. `java-version: '21'` не менялся.
- **Результат (attempt 4):** все 9 job success; в `build android` — `df` 13G → 23G после очистки, `Android SDK сохранён`, `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (Gradle 544.6s). `build ios` cancelled в attempts 1–3 (L22), success с 4-й попытки. Детали — `journal/iteration-2/ci-infra-fix.md`.

## Итерация 2 — итог

- **План/реализация:** ADR-008 (классическая сессия: очередь due+new, одна оценка на карточку, немедленная транзакция, undo), ADR-009 (ручная форма: поля/типы/валидация/удаление); домен (`CardDraft`, `CardSchedulingMapper`, `ReviewQueue`), data (`DriftCardRepository` CRUD, `DriftReviewRepository` транзакции/undo, перепривязка `fsrs_json` при импорте), UI (ReviewSessionScaffold A6.4, 4 кнопки с прогнозом A7.2, 3D-flip, haptics, форма карточки, «Начать сессию», маршруты).
- **Доказательства:** `fvm flutter test` → **484 теста зелёные**; `analyze` → 0 issues; `dart format` → 0 changed (110 files); покрытие **95,3% (2523/2648)**; guard 35/35; `build windows --release` → `cardflow.exe`. FSRS-числа: `journal/iteration-2/fsrs-intervals.md`.
- **Ревью:** blocker 0 / critical 0 / high 1 (H1, импорт `fsrs_json`), medium 3; fix-итерация закрыла всё (`journal/iteration-2/review-fixes.md`), low задокументированы (L18–L20). Отчёты: `review.md`, `verify.md`, `summary.md`.
- **Коммиты:** `68b1c1b` (L9/L9b + CI), `e96e76b` (план/ADR), `350222e` (красная фаза), `6d6fa02` (домен+data), `c589e8a` (UI), `d5495f2` (fix findings), `+ docs`, `7d124aa` (CI-хотфикс диска), `74da42e`/`ff32590`/`+ docs` (доказательства и зелёный прогон). Рабочее дерево — clean.
- **Отступления:** не реализованы (не отрисованы) — настройки сессии и другие режимы (4/6), «Изменить/Отложить/Флаг» в сессии, requeue learning (ADR-008), neighbor-squish (L18), stale-счётчики due/«Новые» (L10/L19), cloze-редактор (5), свайп-удаление/приостановка (6).

## Открытые вопросы к владельцу

Нет. Платных зависимостей нет (PDF — pdfrx, MIT); формат `.zip` v1 не менялся; удаление функций SPEC не предлагалось. Push — по отдельной команде в конце итерации.

## Известные ограничения (актуальные)

L1 (ключи API), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (устаревание due-счётчиков), L11 (живые диалоги file_picker/mobile), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15/L16/L17, L18 (neighbor-squish), L19 (семантика «Новые» vs очередь), L20 (сессия без requeue). **L21/L22 сняты** зелёным прогоном `43468349877`; L9/L9b сняты (CI итерации 1), L2b/L3/L6b сняты ранее.
