# STATE — текущее состояние CardFlow

**Дата:** 2026-11-14 · **Этап:** итерация **7.5** «Провайдеры и фикс сохранения ключей» — **завершена
и запушена**, CI зелёный · **Режим:** ИТЕРАЦИИ (стоп до команды владельца)
**Факты (сверено командами в этой сессии):** на старте `git status --short` → пусто, `HEAD` =
`origin/main` = `7892b08` (документация L45/аудита MVP). Flutter 3.47.9 / Dart 3.13.7 (FVM);
Windows 11; `fvm flutter devices` → Windows desktop доступен; Android SDK/JDK/Xcode/Linux нет (L2).

**Push/CI (2026-11-14):** `origin/main = a20cd5e` (`7892b08..a20cd5e`, 3 коммита итерации 7.5);
CI run [`43632334916`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43632334916) —
**9/9 job success** (`format + analyze`, `test` × 3 ОС, `build-desktop` × 3, `build-mobile` × 2).

## Следующее действие

1. **Стоп:** итерация 7.5 принята локальными гейтами и CI; ждать команды владельца (дизайн-задача
   или Post-MVP).
2. Приёмка владельцем: экран «Провайдеры» — добавить DeepSeek из каталога, вставить ключ,
   «Проверить подключение», «Сгенерировать» (живой DeepSeek-путь подтверждён в этой сессии).
3. Дизайн (стекло, тени, анимации) — **отдельная задача**, в 7.5 не делался (условие владельца).

## Итерация 7.5 — итог

**Диагностика (owner note):** D1 — ключ не сохранялся, потому что `_save()` экрана настроек
валидировал адрес/модель и делал ранний `return` до записи ключа (воспроизведено widget-тестом,
`writeCalls=0`); D2 — генерация по умолчанию уходила в OpenAI без ключа; D3 — «Сохранено»
показывалось без проверки read-back. Платформенное хранилище исправно: Windows integration-тест
на реальном DPAPI — `All tests passed!`.

**Сделано (ADR-020):**
- Домен: `ProviderProtocol`, каталог `kProviderPresets` (9 провайдеров), `ProviderAccount`/
  `ProviderAccounts` (JSON v1 в `app_settings` → `generation.providers`, схема БД не менялась).
- Ключи: `ApiKeyStore` по id аккаунта; write → read-back → только затем сохранение аккаунта.
- Миграция наследия: legacy-адрес/модель и legacy-ключи (`openai`, `gemini`, `anthropic`,
  `openai_compatible`) → аккаунты; «осиротевший» ключ без адреса не теряется.
- `ProviderEndpoint`: все адаптеры уважают базовый адрес аккаунта (прокси/шлюз тоже).
- Генерация: `GenerationRequest`/`GenerationRunRequest` несут аккаунт; `generation_jobs.provider`
  = id аккаунта.
- UI: `/settings/generation` → список карточек + «+ Добавить провайдера» (каталог /
  пользовательская модель), «Проверить подключение», изменение/удаление/основной; блок API в
  настройках — сводка + переход; экран генерации — чипы аккаунтов и модель из пресета.
  `AppSettings.defaultProvider/defaultModelId` удалены (роль — `activeAccountId`).
- ARB: +46 строк (провайдеры), удалены 24 устаревшие строки прежнего экрана.

**Доказательства:** `fvm flutter test --exclude-tags golden` → **1254 passed + 1 skipped**
(skip — live-тест без ключа в env; при ключе из реестра — **1 passed**,
`LIVE DeepSeek OK: model=deepseek-chat, cards=3, tokens=1138`); покрытие рукописного кода
**92.6 % (8759/9457)** (raw lcov с генератами — 76.1 %); `analyze` → `No issues found!`;
`dart format --set-exit-if-changed lib test integration_test` → 317 файлов, 0 changed;
`fvm flutter build windows --release` → `cardflow.exe` (54,7 с);
`fvm flutter test integration_test/secure_api_key_store_windows_test.dart -d windows` →
`All tests passed!` (реальный `flutter_secure_storage`, DPAPI).

## Известные ограничения (актуальные)

L1, L2, L4, L5, L6, L6c, L7, L8, L10, L11, L12, L13, L14, L15, L16, L18, L19, L20, L23, L24, L25,
L27, L30 (DeepSeek — success-путь живьём; негативные контракты по ADR-014 не проверяются),
L31, L32, L33, L34, L35, L36, L37, L38, L39, L40, L41, L42, L43, L44, L46,
**L28** (сужен: Windows проверен integration-тестом, Android/iOS/macOS/Linux — нет),
**L47** (живые вызовы каталога кроме DeepSeek), **L48** (Windows integration-тест вне CI).
