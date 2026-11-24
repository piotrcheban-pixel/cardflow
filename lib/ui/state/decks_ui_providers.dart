import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// UI-состояние экрана «Колоды» (итерация 1): поиск, фильтр, список, колода.
///
/// Riverpod 3 без кодогенерации (ADR-002). Данные берутся из репозиториев,
/// провайдеры data-слоя импортируются из `app_providers.dart`, а не дублируются.

/// Запрос списка колод: строка поиска + чип фильтра.
///
/// Поиск и фильтр живут в одном неизменяемом [DeckQuery]: при каждом изменении
/// `deckSummariesProvider` переподписывается на поток репозитория.
class DecksQueryNotifier extends Notifier<DeckQuery> {
  @override
  DeckQuery build() => const DeckQuery();

  /// Обновляет строку поиска (пустая строка — поиск выключен).
  void setSearch(String value) {
    if (state.search == value) return;
    state = state.copyWith(search: value);
  }

  /// Переключает чип фильтра.
  void setFilter(DeckFilter filter) {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter);
  }

  /// Сбрасывает поиск (кнопка очистки поля).
  void clearSearch() => setSearch('');
}

/// Текущий запрос списка колод.
final NotifierProvider<DecksQueryNotifier, DeckQuery> decksQueryProvider =
    NotifierProvider<DecksQueryNotifier, DeckQuery>(DecksQueryNotifier.new);

/// Видимость поля поиска на экране «Колоды» (иконка search — переключатель).
class DecksSearchVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Открывает/закрывает поле поиска; при открытии просит фокус для ввода.
  void toggle() {
    state = !state;
    if (state) ref.read(decksSearchFocusProvider.notifier).request();
  }

  /// Открывает поле поиска (боковая панель / горячая клавиша).
  ///
  /// Кнопка «Найти колоду» обязана довести пользователя до ввода запроса:
  /// поле не только появляется, но и получает фокус (находка «кнопка не
  /// работает» — визуально появлялось поле, но клавиатура в него не попадала).
  void open() {
    state = true;
    ref.read(decksSearchFocusProvider.notifier).request();
  }

  /// Закрывает поле поиска.
  void close() => state = false;
}

/// Видимость поля поиска.
final NotifierProvider<DecksSearchVisibilityNotifier, bool>
decksSearchVisibleProvider =
    NotifierProvider<DecksSearchVisibilityNotifier, bool>(
      DecksSearchVisibilityNotifier.new,
    );

/// Запрос фокуса на поле поиска колод.
///
/// Кнопка «Найти колоду» в боковой панели (и иконка поиска на узком экране)
/// не просто показывает поле — пользователь должен сразу набирать запрос.
/// Штатный `autofocus` не подходит: на широком экране поле видно всегда, и
/// автофокус отбирал бы фокус при каждом входе в раздел. Поэтому открытие
/// поиска увеличивает счётчик, а поле реагирует на его изменение.
class DecksSearchFocusNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Просит поле поиска получить фокус (следующий кадр).
  void request() => state = state + 1;
}

/// Счётчик запросов фокуса поля поиска.
final NotifierProvider<DecksSearchFocusNotifier, int> decksSearchFocusProvider =
    NotifierProvider<DecksSearchFocusNotifier, int>(
      DecksSearchFocusNotifier.new,
    );

/// Видимость ряда чипов фильтра (иконка filter_list — переключатель).
class DecksFiltersVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Скрывает/показывает чипы фильтра.
  void toggle() => state = !state;
}

/// Видимость чипов фильтра.
final NotifierProvider<DecksFiltersVisibilityNotifier, bool>
decksFiltersVisibleProvider =
    NotifierProvider<DecksFiltersVisibilityNotifier, bool>(
      DecksFiltersVisibilityNotifier.new,
    );

/// Сводки колод по текущему запросу (loading/error/data — в [AsyncValue]).
///
/// `autoDispose`: при уходе с экрана подписка снимается, при возврате данные
/// перезапрашиваются (актуальность `due`-счётчиков, KNOWN L10/M13).
final deckSummariesProvider = StreamProvider.autoDispose<List<DeckSummary>>((
  ref,
) {
  final DeckQuery query = ref.watch(decksQueryProvider);
  return ref.watch(deckRepositoryProvider).watchSummaries(query: query);
});

/// Порядок сортировки списка колод (UI-состояние, не фильтр запроса).
enum DecksSort {
  /// Сначала колоды с наибольшим числом карточек к повторению.
  due,

  /// Сначала наиболее изученные (доля карточек не в состоянии «новая»).
  progress,

  /// Сначала самые крупные колоды.
  cards,

  /// По алфавиту.
  name,
}

/// Режим отображения колод.
enum DecksViewMode {
  /// Сетка карточек (по умолчанию на широком экране).
  grid,

  /// Одноколоночный список.
  list,
}

/// Сортировка списка колод.
class DecksSortNotifier extends Notifier<DecksSort> {
  @override
  DecksSort build() => DecksSort.due;

  /// Устанавливает порядок сортировки.
  void set(DecksSort value) {
    if (state == value) return;
    state = value;
  }
}

/// Текущая сортировка колод.
final NotifierProvider<DecksSortNotifier, DecksSort> decksSortProvider =
    NotifierProvider<DecksSortNotifier, DecksSort>(DecksSortNotifier.new);

/// Режим отображения колод.
class DecksViewModeNotifier extends Notifier<DecksViewMode> {
  @override
  DecksViewMode build() => DecksViewMode.grid;

  /// Устанавливает режим отображения.
  void set(DecksViewMode value) {
    if (state == value) return;
    state = value;
  }
}

/// Текущий режим отображения колод.
final NotifierProvider<DecksViewModeNotifier, DecksViewMode>
decksViewModeProvider = NotifierProvider<DecksViewModeNotifier, DecksViewMode>(
  DecksViewModeNotifier.new,
);

/// Все активные колоды без учёта поиска/фильтра экрана «Колоды».
///
/// Нужен шапке, KPI-плиткам и чипам фильтра: счётчики категорий не должны
/// «схлопываться» после выбора фильтра (в макете они считаются по всем колодам).
/// `autoDispose` — как у [deckSummariesProvider].
final allDeckSummariesProvider = StreamProvider.autoDispose<List<DeckSummary>>((
  ref,
) {
  return ref.watch(deckRepositoryProvider).watchSummaries();
});

/// Суммарный остаток карточек к повторению по всем активным колодам.
///
/// Используется оболочкой (боковая панель): это реальный агрегат репозитория,
/// а не отдельное состояние, — поиск/фильтр экрана «Колоды» на него не влияют.
final totalDueCardsProvider = StreamProvider.autoDispose<int>((ref) {
  return ref
      .watch(deckRepositoryProvider)
      .watchSummaries()
      .map(
        (List<DeckSummary> summaries) => summaries.fold<int>(
          0,
          (int sum, DeckSummary summary) => sum + summary.dueCards,
        ),
      );
});

/// Конкретная колода; `null` — колода удалена/не найдена.
///
/// `autoDispose`: при уходе с экрана подписка на поток снимается, ресурсы
/// не держатся (fix-итерация по ревью M13).
final deckProvider = StreamProvider.autoDispose.family<Deck?, String>((
  ref,
  String deckId,
) {
  return ref.watch(deckRepositoryProvider).watchDeck(deckId);
});

/// Карточки колоды (для экрана колоды, порядок — `created_at`).
final deckCardsProvider = StreamProvider.autoDispose.family<List<Card>, String>(
  (ref, String deckId) {
    return ref.watch(cardRepositoryProvider).watchCards(deckId);
  },
);

/// Сводка по конкретной колоде (счётчики шапки экрана колоды).
///
/// Считается репозиторием; включая архивные, чтобы экран открывался и для
/// колоды, которую только что восстановили после undo. `autoDispose` — как
/// у [deckProvider].
final deckSummaryProvider = StreamProvider.autoDispose
    .family<DeckSummary?, String>((ref, String deckId) {
      final repository = ref.watch(deckRepositoryProvider);
      return repository
          .watchSummaries(query: const DeckQuery(includeArchived: true))
          .map((List<DeckSummary> summaries) {
            for (final DeckSummary summary in summaries) {
              if (summary.deck.id == deckId) return summary;
            }
            return null;
          });
    });
