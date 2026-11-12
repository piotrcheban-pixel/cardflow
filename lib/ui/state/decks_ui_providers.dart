import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

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

  /// Открывает/закрывает поле поиска; при закрытии сбрасывает запрос.
  void toggle() => state = !state;

  /// Закрывает поле поиска.
  void close() => state = false;
}

/// Видимость поля поиска.
final NotifierProvider<DecksSearchVisibilityNotifier, bool>
decksSearchVisibleProvider =
    NotifierProvider<DecksSearchVisibilityNotifier, bool>(
      DecksSearchVisibilityNotifier.new,
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
final StreamProvider<List<DeckSummary>> deckSummariesProvider =
    StreamProvider<List<DeckSummary>>((ref) {
      final DeckQuery query = ref.watch(decksQueryProvider);
      return ref.watch(deckRepositoryProvider).watchSummaries(query: query);
    });

/// Конкретная колода; `null` — колода удалена/не найдена.
final StreamProviderFamily<Deck?, String> deckProvider =
    StreamProvider.family<Deck?, String>((ref, String deckId) {
      return ref.watch(deckRepositoryProvider).watchDeck(deckId);
    });

/// Карточки колоды (для экрана колоды, порядок — `created_at`).
final StreamProviderFamily<List<Card>, String> deckCardsProvider =
    StreamProvider.family<List<Card>, String>((ref, String deckId) {
      return ref.watch(cardRepositoryProvider).watchCards(deckId);
    });

/// Сводка по конкретной колоде (счётчики шапки экрана колоды).
///
/// Считается репозиторием; включая архивные, чтобы экран открывался и для
/// колоды, которую только что восстановили после undo.
final StreamProviderFamily<DeckSummary?, String> deckSummaryProvider =
    StreamProvider.family<DeckSummary?, String>((ref, String deckId) {
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
