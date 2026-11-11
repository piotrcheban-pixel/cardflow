# ADR-002 — Управление состоянием: Riverpod 3 без кодогенерации

**Дата:** 2026-11-11 · **Статус:** принято (итерация 0) · **Связано:** SPEC A3, B2; `docs/agent-prompt.md` §6 («Управление состоянием в SPEC не задано: выбери в итерации 0 и оформи ADR-002»), ADR-001, `docs/dependencies.md`

## Контекст

SPEC не задаёт state management. Требования, которые вытекают из продукта и правил проекта:

- архитектура `lib/{domain,data,api,ui}`, причём **`domain/` без импортов Flutter** (AGENTS.md), значит бизнес-логика должна тестироваться без widget tree;
- асинхронные потоки повсюду: drift-стримы (списки колод/карточек, счётчики due), пайплайн генерации (прогресс «фрагмент K из M», отмена, частичный успех, ошибки по файлу), сетевые ретраи (429/5xx), настройки и тема;
- минимум церемоний для MVP: итерации 0–7 делает агент, важно не утонуть в бойлерплейте;
- кодогенерация в проекте уже есть (`freezed`, `drift_dev`, `json_serializable`, `build_runner`) — но для состояния её хочется **не** добавлять, чтобы не плодить лишние шаги `build_runner` и не связывать состояние с генератором;
- UI-стек уже определён: `material_ui` 1.11.0, `go_router` 18.1.4 (ADR-001); желательно не вносить вторую несовместимую парадигму.

Кандидаты (факты — pub.dev API/score на 2026-11-11, см. `journal/iteration-0/dependency-spike.md` §5):

| Кандидат | Версия | Релиз | Лицензия | sdk/flutter | Кодогенерация | Likes / pts | Зависит от `material_ui` |
|---|---|---|---|---|---|---|---|
| **flutter_riverpod + riverpod** | 3.5.0 | 2026-11-06 | MIT | `^3.12.0` / `>=3.0.0` | **не требуется** (опционально `riverpod_generator`) | 2920 / 160 (+ riverpod 4043) | да (`^1.0.0`) |
| flutter_bloc + bloc | 9.1.1 / 9.2.1 | 2025-05-02 / 2026-05-12 | MIT | `>=2.14.0 <4.0.0` | не требуется | 8091 / 160 | нет |
| provider | 6.1.5+1 | 2025-08-19 | MIT | `>=2.12.0 <4.0.0` | не требуется | 11012 / 150 | нет |

## Варианты

1. **`provider` 6.1.5+1** — самый простой API (`ChangeNotifier` + `context.watch`/`read`). Минусы: нет встроенных async-примитивов (loading/error/data пишем руками на каждый экран), состояние мутабельное (`notifyListeners`), хуже тестируется без widget tree, релиз 15 месяцев назад, pub points 150. Для пайплайна генерации и drift-стримов потребуется много ручного кода.
2. **`flutter_bloc` 9.1.1 + `bloc` 9.2.1** — предсказуемая event→state машина, отличная тестируемость, но самый большой бойлерплейт (на каждый экран события/состояния/мапперы); для MVP из ~8 экранов и множества мелких состояний — избыточно. Медленнее последний релиз `flutter_bloc` (2025-05).
3. **`flutter_riverpod` 3.5.0, manual providers (без `riverpod_generator`)** — провайдеры объявляются вручную (`Provider`, `NotifierProvider`, `AsyncNotifierProvider`, `StreamProvider`, `FutureProvider`); `AsyncValue` закрывает loading/error/data/refresh; `ref.watch/read/listen`; зависимости провайдеров тестируются `ProviderContainer` из чистого `riverpod` (без Flutter); встроенные `autoDispose`/`family`; активный релиз (2026-11-06), 160 pts. Требует `material_ui ^1.0.0` — совпадает с выбранной базой (ADR-001).
4. **Без библиотеки** (`ValueNotifier`/`InheritedWidget`/собственный DI) — контролируемо, но придётся самим писать DI, scope, отмену, async-обвязку; дублирование кода и тестов.

## Решение

Принимаем **вариант 3**: `flutter_riverpod ^3.5.0` + `riverpod ^3.5.0` (**manual providers, без кодогенерации**). `riverpod_generator`/`riverpod_annotation` **не подключаем** в MVP — состояние пишется руками, без `.g.dart`.

Правила размещения (чтобы не нарушить чистоту архитектуры):

- `lib/domain/` — **никаких** импортов Riverpod и Flutter: сущности, FSRS-адаптер, чистые функции, репозиторные интерфейсы.
- `lib/data/` — реализации репозиториев (drift/API/файлы), без UI; провайдеры-обёртки над репозиториями допускаются здесь только если файл не тянет Flutter (пакет `riverpod` — чистый Dart).
- `lib/ui/state/` — `ProviderScope`, провайдеры состояния экранов/сессий (`ConsumerWidget`/`ConsumerStatefulWidget`), навигационные редьюсеры.
- Тесты: `ProviderContainer` + `mocktail` в `test/unit/`; widget-тесты — `ProviderScope` с overrides.

Минимальный пример (проверить API на runtime-спайке после установки Flutter):

```dart
// lib/ui/state/decks_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final deckRepositoryProvider = Provider<DeckRepository>((ref) => throw UnimplementedError()); // override в main

final decksProvider = StreamProvider<List<Deck>>((ref) {
  return ref.watch(deckRepositoryProvider).watchAll();
});

// lib/ui/decks/decks_screen.dart
class DecksScreen extends ConsumerWidget {
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    return decks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => ErrorView(), // текст ошибки — только из ARB
      data: (items) => DecksList(items: items),
    );
  }
}
```

## Последствия

**Плюсы:** один выбранный механизм на весь UI; async-состояния без ручных enum'ов; отмена/перезагрузка «из коробки» (`ref.invalidate`, `autoDispose`); state-testable без Flutter (важно для 80% покрытия и TDD); нет кодогенерации для состояния; совместимость с выбранной базой `material_ui`; активная поддержка (релиз за 5 дней до решения).

**Минусы и риски:** (а) новая парадигма — запрет `BuildContext`-зависимостей в бизнес-логике нужно соблюдать дисциплиной; (б) `flutter_riverpod 3.5.0` тянет `material_ui ^1.0.0` — если ADR-001 будет пересмотрен в пользу framework-Material, версия Riverpod должна остаться `<=3.4.x` (там зависимости от `material_ui` нет) — зафиксировать при пересмотре; (в) API 3.x отличается от распространённых примеров 2.x (`Ref`-типы, `Notifier`), примеры брать из актуальной документации.

**Обязательства:** ADR-002 в силе для итераций 0–7; смена библиотеки — только новым ADR с миграцией провайдеров и тестов; `ProviderScope` один на приложение; тексты ошибок — из ARB; в golden/widget-тестах — `ProviderScope(overrides: …)`, без реальных сетей/БД.

## Источники

- pub.dev: https://pub.dev/packages/flutter_riverpod · https://pub.dev/packages/riverpod · https://pub.dev/packages/riverpod_generator
- CHANGELOG flutter_riverpod 3.5.0 (миграция на `material_ui`): https://github.com/rrousselGit/riverpod/blob/master/packages/flutter_riverpod/CHANGELOG.md
- pub.dev: https://pub.dev/packages/flutter_bloc · https://pub.dev/packages/bloc · https://pub.dev/packages/provider
- Документация Riverpod 3: https://riverpod.dev
