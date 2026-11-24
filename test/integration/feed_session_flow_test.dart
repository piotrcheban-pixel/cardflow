import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/ui/review/feed_session_engine.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Сквозной сценарий ленты на реальной in-memory drift-БД (ADR-044).
///
/// Лента — свободный просмотр: ни листание, ни раскрытие ответа не должны
/// создавать `review_logs`, менять `due`/`fsrs_json`/`state` карточки.
void main() {
  late AppDatabase db;
  late Directory mediaDirectory;
  late ProviderContainer container;
  final DateTime createdTime = DateTime.utc(2026, 11, 14, 10);

  setUp(() {
    db = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_feed_');
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
  });

  test('просмотр ленты не пишет review_logs и не меняет расписание', () async {
    await db
        .into(db.decks)
        .insert(
          DecksCompanion.insert(
            id: 'deck-1',
            name: 'Электротехника',
            createdAt: createdTime.millisecondsSinceEpoch,
            updatedAt: createdTime.millisecondsSinceEpoch,
          ),
        );

    final cardRepository = container.read(cardRepositoryProvider);
    final first = (await cardRepository.createCards(
      deckId: 'deck-1',
      draft: const CardDraft(front: 'Что такое ток?', back: 'Движение заряда'),
      now: createdTime,
    )).single;
    final second = (await cardRepository.createCards(
      deckId: 'deck-1',
      draft: const CardDraft(front: 'Единица напряжения', back: 'Вольт'),
      now: createdTime.add(const Duration(minutes: 1)),
    )).single;

    final cards = await cardRepository.cardsByDeck('deck-1');
    final before = <String, Card>{for (final Card card in cards) card.id: card};

    final engine = FeedSessionEngine(cards: cards)..start();
    expect(engine.state.total, 2);
    expect(engine.state.current!.card.id, first.id);

    // Листание вперёд/назад, раскрытие ответа, быстрый повторный визит.
    engine.visit(1);
    engine.toggleReveal();
    expect(engine.state.items[1].revealed, isTrue);
    engine.visit(0);
    expect(
      engine.state.items[1].revealed,
      isTrue,
      reason: 'раскрытие хранится по карточке',
    );
    engine.toggleReveal();
    expect(engine.state.items[0].revealed, isTrue);

    // Ни одной записи повторения: лента не является классическим повторением.
    expect(await db.select(db.reviewLogs).get(), isEmpty);
    for (final Card original in before.values) {
      final Card after = (await cardRepository.cardById(original.id))!;
      expect(after.due, original.due, reason: 'due не меняется');
      expect(after.fsrsJson, original.fsrsJson, reason: 'FSRS не меняется');
      expect(after.state, original.state, reason: 'состояние не меняется');
      expect(after.suspended, original.suspended);
    }

    expect(second.id, isNot(first.id));
  });
}
