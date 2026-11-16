import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/data/cards/card_image_refresher.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_image_refresh_result.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// «Найти картинку заново» в редакторе карточки (7.14, шаг 3).
void main() {
  final Uint8List png = const PlaceholderImageGenerator()
      .generate(seed: 'card-form-image')
      .bytes;

  Card card() => makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Какой тип моста состоит из треугольных ячеек?',
    back: 'Ферменный мост.',
    mediaIds: const <String>['media-1'],
  );

  Future<void> pumpEditForm(
    WidgetTester tester, {
    required FakeCardMediaRepository media,
    required CardImageRefresher refresher,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: FakeCardRepository(cards: <Card>[card()]),
          cardMediaRepository: media,
          cardImageRefresher: refresher,
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/cards/card-1/edit',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('кнопка «Найти картинку заново» обновляет картинку', (
    tester,
  ) async {
    final refresher = _FakeRefresher(CardImageRefreshResult.updated);
    await pumpEditForm(
      tester,
      media: FakeCardMediaRepository(
        bytesById: <String, Uint8List>{'media-1': png},
        metadataById: <String, MediaMetadata>{
          'media-1': const MediaMetadata(
            provider: 'placeholder',
            isPlaceholder: true,
            query: 'truss bridge',
          ),
        },
      ),
      refresher: refresher,
    );

    final l10n = l10nOf(tester);
    final refresh = find.byKey(
      const ValueKey<String>('card-form-refresh-image'),
    );
    expect(refresh, findsOneWidget);
    await tester.scrollUntilVisible(
      refresh,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(refresh);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(refresher.calls, 1);
    expect(refresher.lastMediaId, 'media-1');
    expect(find.text(l10n.cardImageRetrySuccess), findsOneWidget);
  });

  testWidgets('если картинку не нашли — сообщение, карточка остаётся', (
    tester,
  ) async {
    final refresher = _FakeRefresher(CardImageRefreshResult.notFound);
    await pumpEditForm(
      tester,
      media: FakeCardMediaRepository(
        bytesById: <String, Uint8List>{'media-1': png},
        metadataById: <String, MediaMetadata>{
          'media-1': const MediaMetadata(
            provider: 'placeholder',
            isPlaceholder: true,
            query: 'truss bridge',
          ),
        },
      ),
      refresher: refresher,
    );

    final refresh = find.byKey(
      const ValueKey<String>('card-form-refresh-image'),
    );
    await tester.scrollUntilVisible(
      refresh,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(refresh);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10nOf(tester).cardImageRetryNotFound), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('card-form-image-preview')),
      findsOneWidget,
    );
  });

  testWidgets('без сохранённого запроса — отдельное сообщение', (tester) async {
    final refresher = _FakeRefresher(CardImageRefreshResult.noQuery);
    await pumpEditForm(
      tester,
      media: FakeCardMediaRepository(
        bytesById: <String, Uint8List>{'media-1': png},
      ),
      refresher: refresher,
    );

    final refresh = find.byKey(
      const ValueKey<String>('card-form-refresh-image'),
    );
    await tester.scrollUntilVisible(
      refresh,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(refresh);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10nOf(tester).cardImageRetryNoQuery), findsOneWidget);
  });
}

/// Фейковый сервис повторного поиска без БД и сети.
class _FakeRefresher implements CardImageRefresher {
  _FakeRefresher(this.result);

  final CardImageRefreshResult result;
  int calls = 0;
  String? lastMediaId;

  @override
  AppDatabase get database => throw UnimplementedError();

  @override
  MediaStore get mediaStore => throw UnimplementedError();

  @override
  CardImageFinder get imageFinder => throw UnimplementedError();

  @override
  Future<CardImageRefreshResult> refreshMedia(String mediaId) async {
    calls++;
    lastMediaId = mediaId;
    return result;
  }

  @override
  Future<int> retryPlaceholders({int limit = 5}) async => 0;
}
