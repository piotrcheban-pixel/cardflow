# Итерация 7.5 — Провайдеры и фикс сохранения ключей (план)

**Дата:** 2026-11-14 · **Режим:** ИТЕРАЦИИ · **Ветка:** `main`
**Источник:** owner note (экран настроек API не работает: ключ DeepSeek не сохраняется,
генерация не работает; нужен каталог провайдеров и UI как в DSH).

## 0. Факты на старте

- `git status --short` → пусто; `HEAD` = `origin/main` = `7892b08` (`docs: review of the daily limits fix`).
- Flutter 3.47.9 / Dart 3.13.7 (FVM 4.3.2); Windows 11; `fvm flutter devices` → Windows desktop доступен.
- Провайдерский слой итерации 3b/3c: enum `GenerationProvider` (4 значения), ключи —
  `ApiKeyStore` по enum в `flutter_secure_storage`, настройки «OpenAI-совместимого сервера»
  (`base_url` + `model`) — одна строка `app_settings`.
- Экран `/settings/generation`: один блок OpenAI-совместимого сервера + три отдельных блока
  ключей OpenAI/Gemini/Anthropic. Каталога провайдеров нет, DeepSeek как провайдер в UI отсутствует.

## 1. Диагностика (шаг 1 задачи)

| # | Гипотеза | Чем проверяем | Итог |
|---|---|---|---|
| D1 | Ключ не сохраняется, потому что кнопка «Сохранить» сначала валидирует **адрес и модель**: без них ранний `return`, ключ не пишется | новый widget-тест «ключ без адреса/модели всё равно сохраняется» на текущем экране (падает: `keys.writeCalls` 0 ≠ 1) | воспроизведено |
| D2 | Генерация по умолчанию уходит в OpenAI: `_defaultProvider` выбирает OpenAI без ключа, а `openaiCompatible` — только если заданы **и** адрес, **и** модель; «ключ не задан» → генерация не работает | unit-тест `_defaultProvider`-логики/экрана генерации: аккаунт без ключа не выбирается; интеграционный тест «DeepSeek-аккаунт → запрос на `https://api.deepseek.com/chat/completions`» | подтверждено чтением кода |
| D3 | Платформенное хранилище молча теряет значение, а UI всё равно пишет «Сохранено» (read-back есть, но его результат не влияет на сообщение) | `SecureApiKeyStore` round-trip тест (write→read→equals) + **Windows-integration-тест** на реальном `flutter_secure_storage` (DPAPI) | code review: `settingsSaved` показывался без проверки read-back; исправлено |

**Вывод:** экран смешивает две операции (настройки сервера и ключ), из-за чего ключ не
сохраняется без адреса/модели; провайдер не выбирается из каталога; генерация по умолчанию
берёт OpenAI. Лечится рефакторингом провайдеров (ниже), а не точечной правкой.

## 2. Домен (шаг 2)

- `ProviderProtocol` — `openai-completions`, `openai`, `anthropic-messages`,
  `gemini-generate-content`; отображение в существующие адаптеры (`GenerationProvider`).
- `ProviderPreset` + `kProviderPresets`: DeepSeek, OpenAI, Anthropic, Gemini, OpenRouter,
  Moonshot (Kimi), MiniMax, Groq, Ollama (Local) — base URL, протокол, модели с окном контекста,
  нужен ли ключ.
- `ProviderAccount` — id (=== ключ secure storage), label, presetId, protocol, baseUrl, modelId,
  contextTokens, requiresApiKey; JSON `version=1`; `ProviderAccounts` — список + `activeAccountId`.
- `ApiKeyStore` становится строковым (id аккаунта). Legacy-имена (`openai`, `gemini`, `anthropic`,
  `openai_compatible`) совпадают с id мигрируемых аккаунтов → старые ключи читаются без копирования.

## 3. Хранилище и миграция

- `ProviderAccountsStore` + `DriftProviderAccountsStore` (строка `app_settings` с ключом
  `generation.providers`, JSON v1). Схема БД/`schemaVersion` **не меняются**.
- Миграция при первом чтении: legacy `generation.openai_compatible` → аккаунт
  (`openai_compatible`, протокол openai-completions, base URL/модель из строки, id совпадает с
  legacy-ключом); legacy-ключи `openai`/`gemini`/`anthropic` → аккаунты из каталога с
  моделью по умолчанию. Результат сразу записывается (идемпотентно).

## 4. UI (шаг 3)

- `/settings/generation` — единый список карточек провайдеров: название, модель, base URL,
  статус ключа, отметка «основной»; действия: «Проверить подключение», «Изменить», «Удалить»,
  «Сделать основным». Внизу (в `bottomNavigationBar`, ретро 3c) — «+ Добавить провайдера».
- Диалог добавления: «Сторонний поставщик» (каталог → автозаполнение base URL, выпадающий список
  моделей, поле ключа) и «Пользовательская модель API» (название, base URL, протокол, модель, ключ).
- «Проверить подключение» → `ApiKeyVerifier` (минимальный запрос существующими адаптерами):
  «Успешно» / «Ошибка ключа» / «Нет сети» / «Сервер не настроен».
- Настройки (A6.6): блок API — сводка аккаунтов + переход к экрану провайдеров; отдельные поля
  OpenAI/Gemini/Anthropic и «модель по умолчанию» удаляются (модель теперь у аккаунта).
- Экран генерации: чипы — аккаунты, модель — из пресета аккаунта; выбор по умолчанию — основной
  аккаунт.

## 5. Генерация (шаг 4)

- `GenerationRequest`/`GenerationRunRequest` несут `ProviderAccount`; `CardGenerationService`
  берёт адаптер по протоколу, ключ — по `account.id`, base URL — из аккаунта; спец-ветка
  «OpenAI-совместимый» из сервиса уходит.
- `generation_jobs.provider` = id аккаунта (диагностика «куда ушёл запрос»), `model` = модель.
- Интеграционный тест на production-графе: аккаунт DeepSeek → сохранение → `run` → в fake-транспорт
  ушёл запрос `POST https://api.deepseek.com/chat/completions` с `Authorization: Bearer …`
  и `model=deepseek-chat`.

## 6. Риски

- Широкий рефакторинг контрактов `ApiKeyStore`/`GenerationRequest` → много тестов обновляется;
  каждый шаг — отдельный зелёный коммит.
- Удаляемые настройки «провайдер/модель по умолчанию» (ADR-019 §2) меняют A6.6 → фиксируется
  в ADR-020 и журнале (тесты, описывавшие удалённые поля, переписываются).
- Платформенное поведение secure storage на Android/iOS не проверяется (L28); Windows проверяется
  integration-тестом на реальном плагине.

## 7. Критерии приёмки

1. Ключ сохраняется и читается (`SecureApiKeyStore` round-trip + Windows integration).
2. Каталог из 9 провайдеров; выбор из каталога автозаполняет base URL/модель.
3. На экране провайдеров: список карточек, «+ Добавить провайдера» (2 пути), «Проверить подключение»,
   удаление, выбор основного; старых отдельных полей нет.
4. Генерация использует выбранный аккаунт: интеграционный тест на URL DeepSeek.
5. `flutter test` (без golden) зелёный, покрытие ≥80 %, `analyze` 0, `dart format` 0 changed,
   `flutter build windows --release` ок; push и зелёный CI.
