import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review.dart'
    show reviewModeClassic, reviewModeFeed;
import 'package:cardflow/domain/session/session_config.dart';

/// Красная фаза итерации 6: конфиг конструктора (SPEC A6.7, ADR-018) —
/// значения по умолчанию, JSON-контракт `session_presets.config_json`, валидация.
void main() {
  const List<String> decks = <String>['deck-1', 'deck-2'];

  group('SessionConfig: умолчания', () {
    test('без фильтров, классика, 20 карточек, переключатели выключены', () {
      const SessionConfig config = SessionConfig(deckIds: decks);

      expect(config.deckIds, decks);
      expect(config.tags, isEmpty);
      expect(config.cardTypes, isEmpty);
      expect(config.states, isEmpty);
      expect(config.mode, SessionMode.classic);
      expect(config.limit.kind, SessionLimitKind.cards);
      expect(config.limit.value, 20);
      expect(config.shuffle, isFalse);
      expect(config.interleave, isFalse);
      expect(config.warmup, isFalse);
    });

    test('copyWith заменяет только переданные поля', () {
      const SessionConfig config = SessionConfig(deckIds: decks);
      final SessionConfig changed = config.copyWith(
        tags: <String>{'даты'},
        states: <SessionStateFilter>{SessionStateFilter.review},
        mode: SessionMode.feed,
        limit: const SessionLimit.minutes(10),
        shuffle: true,
        interleave: true,
        warmup: true,
      );

      expect(changed.deckIds, decks);
      expect(changed.tags, <String>{'даты'});
      expect(changed.states, <SessionStateFilter>{SessionStateFilter.review});
      expect(changed.mode, SessionMode.feed);
      expect(changed.limit.kind, SessionLimitKind.minutes);
      expect(changed.limit.value, 10);
      expect(changed.shuffle, isTrue);
      expect(changed.interleave, isTrue);
      expect(changed.warmup, isTrue);
      expect(config.tags, isEmpty, reason: 'исходный конфиг не меняется');
    });
  });

  group('SessionConfig: JSON', () {
    test('toJson фиксирует версию контракта и детерминированный порядок', () {
      const SessionConfig config = SessionConfig(
        deckIds: <String>['deck-b', 'deck-a'],
        tags: <String>{'Язык', 'биология'},
        cardTypes: <CardType>{CardType.cloze, CardType.basic},
        states: <SessionStateFilter>{
          SessionStateFilter.review,
          SessionStateFilter.newCards,
        },
        mode: SessionMode.feed,
        limit: SessionLimit.minutes(15),
        shuffle: true,
      );

      expect(config.toJson(), <String, Object?>{
        'version': 1,
        'deck_ids': <String>['deck-b', 'deck-a'],
        'tags': <String>['биология', 'Язык'],
        'card_types': <String>['basic', 'cloze'],
        'states': <String>['new', 'review'],
        'mode': 'feed',
        'limit': <String, Object?>{'kind': 'minutes', 'value': 15},
        'shuffle': true,
        'interleave': false,
        'warmup': false,
      });
    });

    test('round-trip полного конфига сохраняет равенство', () {
      const SessionConfig config = SessionConfig(
        deckIds: decks,
        tags: <String>{'даты'},
        cardTypes: <CardType>{CardType.basicReversed},
        states: <SessionStateFilter>{SessionStateFilter.leeches},
        mode: SessionMode.feed,
        limit: SessionLimit.cards(50),
        shuffle: true,
        interleave: true,
        warmup: true,
      );

      final SessionConfig restored = SessionConfig.fromJson(config.toJson());

      expect(restored, config);
      expect(restored.hashCode, config.hashCode);
    });

    test('fromJson: минимальный JSON — умолчания для необязательных полей', () {
      final SessionConfig config = SessionConfig.fromJson(<String, Object?>{
        'version': 1,
        'deck_ids': <String>['deck-1'],
      });

      expect(config.deckIds, <String>['deck-1']);
      expect(config.mode, SessionMode.classic);
      expect(config.limit, const SessionLimit.cards(20));
      expect(config.tags, isEmpty);
      expect(config.shuffle, isFalse);
    });

    test('fromJson: неизвестные ключи игнорируются (совместимость вперёд)', () {
      final SessionConfig config = SessionConfig.fromJson(<String, Object?>{
        'version': 1,
        'deck_ids': <String>['deck-1'],
        'future_option': 'значение',
        'limit': <String, Object?>{'kind': 'cards', 'value': 10, 'extra': 1},
      });

      expect(config.limit.value, 10);
    });

    test('fromJson: неизвестная версия контракта — FormatException', () {
      expect(
        () => SessionConfig.fromJson(<String, Object?>{
          'version': 2,
          'deck_ids': <String>['deck-1'],
        }),
        throwsFormatException,
      );
    });

    test('fromJson: без версии/колод — FormatException', () {
      expect(
        () => SessionConfig.fromJson(<String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.fromJson(<String, Object?>{
          'version': 1,
          'deck_ids': <String>[],
        }),
        throwsFormatException,
        reason: 'пресет без колод невалиден (ADR-018)',
      );
    });

    test('fromJson: неизвестные значения фильтров — FormatException', () {
      Map<String, Object?> json({
        required String key,
        required Object? value,
      }) => <String, Object?>{
        'version': 1,
        'deck_ids': <String>['deck-1'],
        key: value,
      };

      expect(
        () => SessionConfig.fromJson(
          json(key: 'card_types', value: <String>['image']),
        ),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.fromJson(
          json(key: 'states', value: <String>['suspended']),
        ),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.fromJson(json(key: 'mode', value: 'audio')),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.fromJson(
          json(
            key: 'limit',
            value: <String, Object?>{'kind': 'hours', 'value': 1},
          ),
        ),
        throwsFormatException,
      );
    });

    test('fromJson: лимит вне диапазона — FormatException', () {
      Map<String, Object?> json(String kind, int value) => <String, Object?>{
        'version': 1,
        'deck_ids': <String>['deck-1'],
        'limit': <String, Object?>{'kind': kind, 'value': value},
      };

      expect(
        () => SessionConfig.fromJson(json('cards', 0)),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.fromJson(json('cards', 501)),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.fromJson(json('minutes', 0)),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.fromJson(json('minutes', 181)),
        throwsFormatException,
      );
      expect(
        SessionConfig.fromJson(json('cards', 1)).limit,
        const SessionLimit.cards(1),
      );
    });
  });

  group('SessionLimit', () {
    test('бюджет времени есть только у лимита минут', () {
      expect(const SessionLimit.cards(10).timeBudget, isNull);
      expect(
        const SessionLimit.minutes(15).timeBudget,
        const Duration(minutes: 15),
      );
      expect(const SessionLimit.minutes(5).isMinutes, isTrue);
      expect(const SessionLimit.cards(5).isMinutes, isFalse);
    });
  });

  group('SessionMode', () {
    test('wire-имена совпадают со значениями review_logs.mode', () {
      expect(SessionMode.classic.wireName, reviewModeClassic);
      expect(SessionMode.feed.wireName, reviewModeFeed);
      expect(SessionMode.classic.wireName, 'classic');
      expect(SessionMode.feed.wireName, 'feed');
      expect(SessionMode.fromWire('feed'), SessionMode.feed);
      expect(() => SessionMode.fromWire('audio'), throwsFormatException);
    });
  });
}
