# Итерация 7.5 — зелёная фаза

**Дата:** 2026-11-14 · **ADR:** ADR-020

## Что сделано по шагам

1. **Диагностика D1–D3′** (см. `red.md`): ключ не сохранялся из-за раннего `return` по адресу/модели;
   генерация по умолчанию уходила в OpenAI; «Сохранено» показывалось без проверки read-back;
   реальное Windows-хранилище исправно (integration-тест).
2. **Домен** (`lib/domain/generation/`): `provider_protocol.dart`, `provider_preset.dart` (9
   провайдеров), `provider_account.dart` (`ProviderAccount`/`ProviderAccounts`, JSON v1, slug-id),
   `provider_accounts_store.dart`; `api_key_store.dart` стал строковым; `generation_request.dart`/
   `generation_run.dart` несут аккаунт; `generation_model.dart` — только бюджеты по контексту.
3. **Данные** (`lib/data/`): `drift_provider_accounts_store.dart` (`generation.providers` в
   `app_settings`, миграция наследия 3b–7, включая «осиротевший» ключ без адреса);
   `secure_api_key_store.dart` — id аккаунта (`cardflow.api_key.<id>`), legacy-имена сохранены.
4. **API** (`lib/api/`): `provider_endpoint.dart` — общий резолвер адреса; все четыре адаптера
   уважают `baseUrl`; `card_generation_service.dart` и `api_key_verifier.dart` работают по аккаунту;
   пайплайн пишет в `generation_jobs` id аккаунта и модель.
5. **UI** (`lib/ui/`): `generation_settings_screen.dart` переписан (карточки, «+ Добавить
   провайдера», каталог/пользовательская модель, «Проверить подключение», изменение/удаление/
   основной, read-back ключа); `provider_account_dialogs.dart`, `provider_labels.dart`; блок API в
   `settings_screen.dart` — сводка + переход; `generation_screen.dart` — чипы аккаунтов и модель из
   пресета.
6. **ARB:** +47 строк (провайдеры/диалоги/проверка), удалены 24 устаревшие строки прежнего экрана.
7. **Тесты:** новые — каталог/аккаунты (26), хранилище аккаунтов и миграция (10), резолвер адресов
   (9), экран провайдеров (13), интеграционный срез DeepSeek (1), Windows integration-тест secure
   storage (1); переписаны сервис/верификатор/пайплайн/экраны; удалены тесты удалённого UI
   (`generation_settings_keys_test.dart`, старый `generation_settings_key_bug_test.dart` — регрессия
   D1 перенесена в тест экрана провайдеров).

## Ключевые решения

- Провайдер = аккаунт с протоколом (а не enum): один протокол `openai-completions` покрывает
  DeepSeek/OpenRouter/Moonshot/MiniMax/Groq/Ollama и пользовательские серверы.
- Ключ хранится по id аккаунта; legacy-имена совпадают с id миграции → старые ключи читаются.
- Запись ключа отделена от записи аккаунта; read-back обязателен (D3).
- `AppSettings.defaultProvider/defaultModelId` удалены: роль «по умолчанию» играет `activeAccountId`.
- Схема БД/`schemaVersion` не менялись.

## Зелёные гейты (см. `verify.md`)

`fvm flutter test --exclude-tags golden` → 1254 passed + 1 skipped; `analyze` 0; `dart format` 317/0;
`fvm flutter build windows --release` → `cardflow.exe`; покрытие рукописного кода 92.6 %.
