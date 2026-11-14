# Итерация 5 — verify

**Дата:** 2026-11-14 · **Шаг:** 5 · **Кодовый снимок:** `0e4e11b` (+ исправление аннотации тестового fake)
**Окружение:** Windows 11 · Flutter 3.47.9 / Dart 3.13.7 (FVM) · локаль `ru`.

## Команды и результат

```text
fvm dart format --set-exit-if-changed lib test
  → 253 files, 0 changed

fvm flutter analyze
  → No issues found! (4.9 s)

fvm flutter test --coverage --exclude-tags golden
  → 1020 passed + 1 skipped

fvm flutter test --exclude-tags golden
  → 1020 passed + 1 skipped (повтор на финальном снимке)

fvm dart run tool/coverage_check.dart
  → Итого: 93.1% (6468/6946), порог 80% пройден

fvm flutter build windows --release
  → √ Built build\windows\x64\runner\Release\cardflow.exe (56,2 s)
```

Во время первого verify-прогона анализатор дал **1 warning** на тестовом `_FakePlatformFile.size`
(лишний `@override`, у `PlatformFile` нет поля `size`). Аннотация удалена, после этого analyzer — 0;
полный прогон повторён на итоговом снимке.

## Что проверено именно этой итерацией

- A7.8: occlusion-изображение, прямоугольные/эллиптические маски, тап/показать/скрыть, редактор,
  сохранение в `occlusion_json` + `media`, откат при файловой ошибке, удаление медиа.
- A7.9: cloze-группы, одинаковые номера, форма cloze, production-экраны классики и ленты.
- A7.10: `flutter_math_fork` для `$…$`/`$$…$$`, шаги, fallback с ARB; `\(…\)` не поддержан.
- A6.9: create → export → import → чтение медиа/разметки; схема и `format_version` не менялись.
- Guard-тесты: no WebView/HTML, отсутствие литералов UI, домен без Flutter, no secrets, ru-only.
- L17 закрыт startup-GC; production-граф провайдеров и `main.dart` собираются.

## Не проверено и почему

- **Golden-тесты** не запускались: `--exclude-tags golden`, локально нет Linux-эталона (L6).
- **Live API** не запускался: итерация не меняет сетевой слой; в окружении нет ключей OpenAI/Gemini/
  Anthropic (L1), live-тесты skip.
- **Реальный system file picker, рисование пальцем/мышью, свайпы** — ручная приёмка устройства
  (L11, L37, L38); widget-тесты используют pointer events/fake platform.
- **Screen-reader масок** — доступность итерации 7 (L12/L39).
- **CI** не запускался: push не выполняется без отдельной команды владельца. Локальный Windows-release
  подтверждает desktop-компиляцию; Android/iOS/macOS/Linux — CI (L2).
- **L36** (авто-продвижение под другим маршрутом) не менялся и остаётся ограничением.

## Вывод

Шаги 1–5 итерации 5 завершены: локальные гейты зелёные, покрытие выше порога, Windows-сборка успешна.
Остались remember и improve (шаги 6–7).
