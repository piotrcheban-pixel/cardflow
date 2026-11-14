# Итерация 7.5 — проверка (verify)

**Дата:** 2026-11-14 · **Снимок:** рабочее дерево после зелёной фазы (коммит — в конце итерации)

## Команды и вывод

| Гейт | Команда | Результат |
|---|---|---|
| Тесты | `fvm flutter test --exclude-tags golden` | **1254 passed + 1 skipped** (skip — live-тест без `DEEPSEEK_API_KEY` в env процесса; с ключом — 1 passed) |
| Покрытие | `fvm flutter test --coverage --exclude-tags golden` | рукописный код **92.6 % (8759/9457)**; raw lcov со сгенерированным — 76.1 % (13 244 строки); новые файлы: `card_generation_service` 100 %, `drift_provider_accounts_store` 100 %, `secure_api_key_store` 100 %, `api_key_verifier` 96.0 %, `provider_endpoint` 93.9 %, экран провайдеров 91.8 %, диалоги 92.7 % |
| Анализатор | `fvm flutter analyze` | `No issues found!` |
| Формат | `fvm dart format --set-exit-if-changed lib test integration_test` | 317 файлов, **0 changed** |
| Сборка | `fvm flutter build windows --release` | `√ Built build\windows\x64\runner\Release\cardflow.exe` (54,7 с) |
| Реальное хранилище | `fvm flutter test integration_test/secure_api_key_store_windows_test.dart -d windows` | **All tests passed!** (DPAPI: write → read → совпадение → delete) |
| Живой DeepSeek | `fvm flutter test test/live --tags live` (ключ из Windows User scope, значение не выводилось) | **1 passed**, `LIVE DeepSeek OK: model=deepseek-chat, cards=3, tokens=1138` |
| Guard-тесты | в общем прогоне | `no_webview`, `ru_strings`, `no_secrets`, `architecture`, `ci_pdfium` — зелёные |

## Критерии приёмки итерации (plan.md §7)

| # | Критерий | Статус | Доказательство |
|---|---|---|---|
| 1 | Ключ сохраняется и читается | **выполнено** | `api_key_store_test.dart` (round-trip, независимость, trim, пустой ключ) + Windows integration-тест на реальном плагине; регрессия D1 в widget-тесте экрана провайдеров |
| 2 | Каталог из 9 провайдеров, автозаполнение адреса/модели | **выполнено** | `provider_preset_test.dart` (9 пресетов, адреса, протоколы, модели, ключ у Ollama); widget-тест «добавление DeepSeek из каталога» проверяет `https://api.deepseek.com` без ручного ввода |
| 3 | Экран провайдеров: список, «+ Добавить», два пути, «Проверить подключение», удаление, основной; старых полей нет | **выполнено** | `generation_settings_screen_test.dart` (13 тестов) + `settings_screen_test.dart` (сводка/пусто); старые строки ARB удалены |
| 4 | Генерация использует выбранный аккаунт | **выполнено** | `generation_flow_test.dart`: DeepSeek-аккаунт → `POST https://api.deepseek.com/chat/completions`, `Bearer`, `model=deepseek-chat`, `generation_jobs.provider='deepseek'`; живой DeepSeek — 3 карточки |
| 5 | Гейты качества | **выполнено** | таблица выше + CI: push `7892b08..a20cd5e`, run [`43632334916`](https://github.com/piotrcheban-pixel/cardflow/actions/runs/43632334916) — **9/9 job success** (`format + analyze`, `test` × 3 ОС, `build-desktop` × 3, `build-mobile` × 2) |

## Не проверено (KNOWN_LIMITATIONS)

- Live-вызовы OpenAI/Gemini/Anthropic/OpenRouter/Moonshot/MiniMax/Groq/Ollama — **L47** (нет ключей/локальных серверов).
- Secure storage на Android/iOS/macOS/Linux — **L28** (Windows проверен).
- Windows integration-тест вне CI — **L48**; кнопки «Проверить подключение» на живых API — **L49**.
- Дизайн (стекло/тени/анимации) — по условию владельца отдельной задачей.
