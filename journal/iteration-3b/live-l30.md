# Live-проверка L30 — DeepSeek (ADR-013), 2026-11-14

Шаг: верификация живого HTTP-контракта OpenAI-compatible адаптера. Код и тесты **не менялись** —
доказательство получено существующим live-тестом `test/live/openai_compatible_deepseek_live_test.dart`
(тег `live`). Итерация 3c не начиналась.

## Окружение (проверено в этой сессии)

| Переменная | Env процесса агента | Windows User scope | Итог |
|---|---|---|---|
| `DEEPSEEK_API_KEY` | absent | **present** | ключ передан новому дочернему процессу значением из реестра; **значение не выводилось** |
| `DEEPSEEK_BASE_URL` | absent | absent | default `https://api.deepseek.com` |
| `DEEPSEEK_MODEL` | absent | absent | default `deepseek-chat` |

Факт хоста: унаследованное окружение процесса DSH не содержит `DEEPSEEK_API_KEY` (переменная задана в
User scope уже после старта процесса), поэтому для прогона она прочитана из реестра
`[Environment]::GetEnvironmentVariable(..., 'User')` и установлена в env **дочернего** процесса pwsh.
Проверка наличия — только present/absent; значение не печаталось и не логировалось.

## Команда и результат

`fvm flutter test test/live --tags live`

```
00:00 +0: loading .../test/live/openai_compatible_deepseek_live_test.dart
00:00 +0: реальный вызов DeepSeek через OpenAI-compatible: один запрос, карточки по канонической схеме A8.4
LIVE DeepSeek OK: model=deepseek-chat, cards=3, tokens=1231
00:02 +1: All tests passed!
```

**Итог: 1 passed, 0 failed, ~2 s.**

## Что этим доказано

- Живой endpoint `POST https://api.deepseek.com/chat/completions` доступен и принимает запрос адаптера.
- Bearer-аутентификация с ключом из `ApiKeyStore`-fake (production-путь `CardGenerationService`).
- Разбор реального ответа (`choices[0].message.content`, `usage.total_tokens` = 1231) и заполнение
  `GenerationResult`.
- Реальная модель вернула 3 карточки, прошедшие **локальную валидацию канонической схемы A8.4** и
  контентные правила (`card_content_validator`); ветка strict `response_format` не упала в fallback
  (иначе ответ пришлось бы извлекать из markdown — тест прошёл без ошибки).
- Модель/провайдер в результате — `openaiCompatible` / `deepseek-chat` (из настроек, а не из запроса).

## Что осталось открытым (L30 частично)

1. Живые OpenAI / Gemini / Anthropic — ключей нет (L1).
2. Живые таймауты, `Retry-After` при 429, коды 401/403 и остановки `truncated`/`refused`/`emptyResponse`/
   `invalidResponse` — live-тест покрывает success-путь; фальшивый ключ/нагрузка для проверки 401/429
   намеренно не подставлялись (риск блокировок на стороне провайдера, не согласовано с владельцем).
3. Ollama / LM Studio — серверы не запущены (L32).

## Контрольный прогон (та же сессия, без ключа в env)

`fvm flutter test --exclude-tags golden` → **800 passed + 1 skipped** (live-тест self-skip без ключа);
`fvm dart format --set-exit-if-changed lib test` → 190 files, 0 changed, exit 0; `fvm flutter analyze` →
No issues found. Совпадает с тем, что записано в `STATE.md` до этой проверки.
