# Итерация 7 — красная фаза (домен/данные)

**Дата:** 2026-11-14 · **Снимок:** `b632d11` + незакоммиченные тесты/заглушки
**Команда:**
`fvm flutter test test/unit/domain/app_settings_test.dart test/unit/data/settings/drift_app_settings_store_test.dart test/unit/domain/statistics_calculator_test.dart test/unit/data/statistics/drift_statistics_repository_test.dart`

## Результат до реализации

```
00:00 +1 -24: Some tests failed.
[exit code: 1]
```

24 падения, все — `UnimplementedError` из заглушек контракта (`AppSettings.toJson/fromJson/copyWith`,
`StatisticsCalculator.build`, `DriftAppSettingsStore.read/write`, `DriftStatisticsRepository.load/
tokensUsedSince`); один зелёный — проверка значений по умолчанию (геттеры полей конструктора).
Ожидаемое поведение зафиксировано ассертами тестов (имена и `expect`), а не текстом ошибки компиляции:
после реализации все 30 тестов зелёные.

## Что именно проверяют тесты (контракт red-фазы)

- `AppSettings`: дефолты ADR-019 §1; JSON roundtrip + `version=1`; неизвестные ключи; клампы
  `text_scale` 0.8–1.4, retention 0.70–0.95, лимитов 0–999; шаги обучения 1–5, 1–60 мин,
  сортировка/дедуп; непустой список; `FormatException` на неизвестную версию/типы/enum;
  `copyWith` и равенство.
- `DriftAppSettingsStore`: отсутствие строки → дефолты; roundtrip; одна строка при перезаписи;
  битый JSON/неизвестная версия/не-объект → дефолты без удаления строки; `settingKey = 'app.settings'`.
- `StatisticsCalculator`: пустые данные; окно удержания 30 дней включительно (Again — ошибка);
  тепловая карта 365 дней (границы года, порядок, счётчики); неделя 7 дней; слабые темы
  (порог 5 повторов и 20 % ошибок, сортировка, топ-5, несколько тегов карточки, вне года);
  прогноз 7 дней с переносом просроченных в сегодня; `tokensWeek`.
- `DriftStatisticsRepository`: пустая БД; реальные строки `review_logs`/`cards`/`generation_jobs`;
  удержание/карта/прогноз; слабые темы по `tags_json`; токены только в окне `since`; битый
  `tags_json` и не-строки в тегах не ломают загрузку.

## Следующий шаг

Зелёная фаза домена/данных подтверждена: `30 passed` (команда выше, повторный прогон после
реализации — `All tests passed!`), `analyze` новых файлов — 0 issues после устранения warning'ов.
