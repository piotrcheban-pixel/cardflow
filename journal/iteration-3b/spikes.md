# Итерация 3b — спайки (до плана)

**Дата:** 2026-11-13. Цель — снять риски API-слоя генерации до тестов и плана: `json_schema` 5.2.2
(валидация A8.4), `flutter_math_fork` 0.7.4 (проверка LaTeX без рендера), форма fake-адаптера Dio.

## S1. `json_schema` 5.2.2 против канонической схемы A8.4

Скрипт `work/spike_json_schema.dart` (`fvm dart run work/spike_json_schema.dart`, `work/` в `.gitignore`):
схема A8.4 (union-типы `["string","null"]`, `additionalProperties: false`, все свойства в `required`)
и четыре входа.

```
valid => true
valid(+extra) => false
null hint missing => false
bad => false, errors=13
first error: /cards/0: required prop missing: back from {front: 1}
```

Вывод: пакет валидирует строгий ответ и возвращает читаемые ошибки (`ValidationResults.errors`);
`JsonSchema.create(map)` работает в чистом Dart (без Flutter) — годится для unit-тестов.
**Вердикт:** fallback `json_schema_builder` не нужен; статус — `approved`.

## S2. `flutter_math_fork` 0.7.4: проверка LaTeX без рендера

Публичный API не экспортирует `TexParser`, но `Math.tex(String)` в конструкторе парсит выражение и
складывает ошибку в `parseError` (публичное поле) — без `WidgetsBinding` и без `pumpWidget`.
Временный `test/spike_math_test.dart` (удалён после прогона):

```
+1: Math.tex выставляет parseError без WidgetsBinding
All tests passed!
```

Проверено: `x^2 + \frac{1}{2}` → `parseError == null`; `\frac{` → ошибка; `\unknowncommand{x}` → ошибка.
Вывод: локальная проверка A8.4 («попытаться распарсить формулы») реализуется через
`Math.tex(expression).parseError`; тянуть внутренний `src/` не нужно.

## S3. Fake `HttpClientAdapter` в Dio 5.11.1

`dio-5.11.1` позволяет подменить транспорт: `abstract class HttpClientAdapter { Future<ResponseBody> fetch(
RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture); void close({bool force}); }`,
`ResponseBody.fromString(text, statusCode, headers: {...})`. Dio сам применяет `validateStatus` и бросает
`DioException` для не-2xx — значит интеграционные тесты retry/429/5xx/401/отмены можно писать без сети
и без mocktail-моков Dio. Используется в `test/helpers/fake_http_adapter.dart`.
