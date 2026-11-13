# STATE — текущее состояние CardFlow

**Дата:** 2026-11-13 · **Итерация:** 2 «Классический режим» — завершена; выполняется **CI-хотфикс** «No space left on device» (коммит `7d124aa`), push — по команде владельца · **Шаг цикла:** хотфикс вне цикла (между итерациями 2 и 3a) · **Режим:** ИТЕРАЦИИ
**Факты:** Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; локальная Windows-сборка работает; Android SDK/JDK, Xcode, Linux — отсутствуют; ключей API нет (absent). GitHub-remote `origin` → piotrcheban-pixel/cardflow; локальный `main` = `origin/main` + `7d124aa`. Последний зелёный CI — итерация 1, run `43436887755`; прогон итерации 2 упал инфраструктурно (`No space left on device`), фикс диска готов и закоммичен, push/новый прогон — по команде владельца.

## Следующее действие

1. **Push CI-фикса `7d124aa`** (по команде владельца) → дождаться нового прогона CI.
2. Если Android снова упадёт — смотреть лог job'а; при `invalid source release: 21` перевести `java-version` в `build-mobile` на `'17'` (отдельный коммит, YAML-проверка по `journal/iteration-2/ci-infra-fix.md`).
3. **Только после зелёного CI** — итерация 3a «Парсеры» (SPEC A8.3: PDF/DOCX/XLSX/PPTX/ODT/TXT/MD/RTF в нормализованный текст, кодировки, сканы, понятные ошибки, фикстуры; `.doc/.xls` — ADR-003). Перед стартом сверить STATE.md с репозиторием (`git status`, `git log`, тесты).

## CI-хотфикс после итерации 2

- **Диагноз:** прогон упал не по коду/workflow, а на диске раннера — `No space left on device` (лог `/home/runner/actions-runner/cached/.../Worker_*.log`, из сессии недоступен: private repo, нет `gh`/токена).
- **Фикс `7d124aa`** (`.github/workflows/ci.yml`, +120 строк): шаг `Free disk space` во всех 4 job'ах до `flutter pub get` — Linux (`/usr/share/dotnet`, `/usr/local/lib/android`, `/opt/ghc`, `/usr/local/share/boost`, `/opt/hostedtoolcache/CodeQL`, `docker image prune --all`), macOS (`~/Library/Android/sdk`, `~/Library/Caches/Homebrew`, `/usr/local/share/dotnet`), `df -h` до/после. Android SDK сохраняется в android-job (`KEEP_ANDROID_SDK`), иначе `flutter build apk` сломался бы. `build-mobile`/android — `rm -rf ~/.gradle/caches` перед сборкой. `java-version: '21'` не менялся (по условию — только при повторном падении).
- **Проверка YAML:** PyYAML (ключ `on` как строка), JSON Schema SchemaStore `github-workflow.json`, actionlint 1.7.12 (0 findings), `bash -n` 21 run-блока — зелёные; старые шаги побайтово не изменены. Подробности — `journal/iteration-2/ci-infra-fix.md`. **Реальный прогон CI — не проверен (ждёт push).**

## Итерация 2 — итог

- **План/реализация:** ADR-008 (классическая сессия: очередь due+new, одна оценка на карточку, немедленная транзакция, undo), ADR-009 (ручная форма: поля/типы/валидация/удаление); домен (`CardDraft`, `CardSchedulingMapper`, `ReviewQueue`), data (`DriftCardRepository` CRUD, `DriftReviewRepository` транзакции/undo, перепривязка `fsrs_json` при импорте), UI (ReviewSessionScaffold A6.4, 4 кнопки с прогнозом A7.2, 3D-flip, haptics, форма карточки, «Начать сессию», маршруты).
- **Доказательства:** `fvm flutter test` → **484 теста зелёные**; `analyze` → 0 issues; `dart format` → 0 changed (110 files); покрытие **95,3% (2523/2648)**; guard 35/35; `build windows --release` → `cardflow.exe`. FSRS-числа: `journal/iteration-2/fsrs-intervals.md` (new 1м/5м30с/10м/16д; learning 1м/10м/4д/8д; review 10м/27д/65д/164д; relearning 10м/15д/3д/7д).
- **Ревью:** независимый reviewer — blocker 0 / critical 0 / high 1 (H1, импорт `fsrs_json`), medium 3; fix-итерация закрыла всё (`journal/iteration-2/review-fixes.md`), low исправлены/задокументированы (L18–L20). Отчёты: `review.md`, `verify.md`, `summary.md`.
- **Коммиты:** `68b1c1b` (L9/L9b + CI), `e96e76b` (план/ADR), `350222e` (красная фаза, 77 падений — только новые тесты), `6d6fa02` (домен+data), `c589e8a` (UI), `d5495f2` (fix findings ревью), `+ docs`, `7d124aa` (CI-хотфикс диска). Рабочее дерево — clean.
- **Отступления:** не реализованы (не отрисованы) — настройки сессии и другие режимы (4/6), «Изменить/Отложить/Флаг» в сессии, requeue learning (ADR-008), neighbor-squish (L18), stale-счётчики due/«Новые» (L10/L19), cloze-редактор (5), свайп-удаление/приостановка (6).

## Открытые вопросы к владельцу

Нет. Платных зависимостей нет; формат `.zip` v1 не менялся (структура контракта; уточнена строгость импорта FSRS); удаление функций SPEC не предлагалось. Push/CI-прогон — по отдельной команде.

## Известные ограничения (актуальные)

L1 (ключи API), L2 (локальные сборки платформ), L4 (хуки), L5 (навыки), L6 (golden), L6c (dynamic color — итерация 7), L7 (.doc/.xls), L8 (DnD-версия), L10 (устаревание due-счётчиков), L11 (живые диалоги file_picker/mobile), L12 (screen-reader/golden M3E), L13 (двойной decode/UI-изолят), L14 (длины при импорте), L15/L16/L17, L18 (neighbor-squish), L19 (семантика «Новые» vs очередь), L20 (сессия без requeue), **L21** (CI-хотфикс не проверен на раннере — до зелёного прогона). L9/L9b сняты (CI итерации 1), L2b/L3/L6b сняты ранее.
