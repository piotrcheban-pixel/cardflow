# Red-фаза guard-тестов (шаг 1.1)

**Дата:** 2026-11-17 · **Команда сравнения:** `fvm flutter test --no-pub test/guards`

Guard-тесты по построению «зелёные» на текущем коде (они охраняют будущее), поэтому
red-фаза проверена **мутациями**: в `lib/ui/` временно вносилось нарушение, тест
падал с ожидаемым сообщением, нарушение откатывалось. Ниже — фактический вывод.

## 1. Новый сырой цвет и прямой `HapticFeedback`

Временный `lib/ui/_red_probe.dart` (удалён после прогона):

```dart
const Color probeColor = Color(0xFF123456);
const Color probeName = Colors.purple;
void probeHaptics() => HapticFeedback.heavyImpact();
ValueKey<String> probeKey() => const ValueKey<String>('probe-new-key');
```

Вывод (фрагменты):

```
design_tokens: реальный репозиторий сырые цвета только в nc_colors.dart [E]
  Сырые цвета вне lib/ui/design/tokens/nc_colors.dart. Используйте NcTheme/NcColors (REDESIGN-SPEC §1.1, ADR-035):
  lib/ui/_red_probe.dart	Color(0xFF123456)
  lib/ui/_red_probe.dart	Colors.purple
    Actual: ['lib/ui/_red_probe.dart']
  Прямые вызовы HapticFeedback.* вне lib/ui/design/haptics.dart. Используйте NcHaptics (REDESIGN-SPEC §7):
  lib/ui/_red_probe.dart
ui_keys: ... новые ключи добавлены в снимок в том же коммите [E]
    Actual: ['probe-new-key']
  Новые ключи не попали в test/guards/fixtures/ui_keys.txt: probe-new-key.
```

## 2. Исчезнувший ключ (переименование в экране)

В `lib/ui/study/typing_screen.dart` временно `typing-diff` → `typing-diff-renamed`:

```
    Actual: ['typing-diff']
  Ключи из снимка исчезли из lib/ui/** — это ломает контракт с виджет-тестами (REDESIGN-PLAN): typing-diff
    Actual: ['typing-diff-renamed']
  Новые ключи не попали в test/guards/fixtures/ui_keys.txt: typing-diff-renamed.
```

Откат подтверждён: `git diff --stat lib/ui/study/typing_screen.dart` — пусто.

## 3. Состояние после откатов

```
fvm flutter test --no-pub test/guards → +65: All tests passed!
```

## Отклонение от плана (зафиксировано в ADR-035)

План предполагал, что `design_tokens_test` будет «сразу зелёным». Фактически в
`lib/ui/` на старте было 30 литералов цвета (экраны «Теста»/«Ввода»/«Пар»,
просмотр картинки, старый `AppTheme`) и 7 файлов с прямыми `HapticFeedback.*`.
Экранные файлы на этапе 1 не редактируются, поэтому нарушения **заморожены** в
`fixtures/design_tokens_baseline.txt` и `fixtures/haptics_baseline.txt`; guard
падает и на новом нарушении, и на «закрытом долге» (фикстуру надо обновить).
Долг закрывается в этапах 3–4, когда экраны переходят на `Nc*`-компоненты.
