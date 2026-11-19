import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/l10n/app_localizations_ru.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Красная фаза: импорт/экспорт `.zip` через UI (SPEC A6.9).
///
/// Фейковые `DeckTransferService`/`FileGateway`: без плагинов, сети и БД.
void main() {
  Future<void> pumpDecks(
    WidgetTester tester, {
    required FakeDeckRepository repository,
    FakeDeckTransferService? transfer,
    FakeFileGateway? gateway,
    FakeCardRepository? cards,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: repository,
          transferService: transfer,
          fileGateway: gateway,
          cardRepository: cards,
        ),
        routes: decksRoutes(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> startImport(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('decks-import')));
    await tester.pumpAndSettle();
  }

  FakeDeckRepository repositoryWithImportedDeck() {
    return FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(
          id: 'imported-deck',
          name: 'Импортированная колода',
          totalCards: 3,
        ),
      ],
    );
  }

  group('Импорт ZIP', () {
    testWidgets('отмена выбора файла — тихий no-op', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository();
      final FakeDeckTransferService transfer = FakeDeckTransferService();
      final FakeFileGateway gateway = FakeFileGateway()..importPath = null;

      await pumpDecks(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      await startImport(tester);

      expect(gateway.pickImportCalls, 1);
      expect(transfer.previewCalls, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('валидный архив: предпросмотр → импорт → переход в колоду', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = repositoryWithImportedDeck();
      final FakeDeckTransferService transfer = FakeDeckTransferService();
      final FakeFileGateway gateway = FakeFileGateway();

      await pumpDecks(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      final AppLocalizations l10n = l10nOf(tester);
      await startImport(tester);

      // Предпросмотр: имя, версия формата, карточки, дубликаты, медиа.
      expect(find.text(l10n.importPreviewTitle), findsOneWidget);
      expect(
        find.text(l10n.importPreviewDeckName('Импортированная колода')),
        findsOneWidget,
      );
      expect(find.text(l10n.importPreviewFormatVersion(1)), findsOneWidget);
      expect(find.text(l10n.importPreviewCards(5)), findsOneWidget);
      expect(find.text(l10n.importPreviewDuplicates(2)), findsOneWidget);
      expect(find.text(l10n.importPreviewMedia(1)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('import-confirm')));
      await tester.pumpAndSettle();

      expect(transfer.importCalls, 1);
      expect(transfer.lastImportDeckName, isNull);
      expect(find.text(l10n.deckImportSuccess), findsOneWidget);
      expect(find.byType(DeckScreen), findsOneWidget);
      expect(find.text('Импортированная колода'), findsOneWidget);
    });

    testWidgets('отмена в диалоге предпросмотра не импортирует', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = repositoryWithImportedDeck();
      final FakeDeckTransferService transfer = FakeDeckTransferService();
      final FakeFileGateway gateway = FakeFileGateway();

      await pumpDecks(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      await startImport(tester);
      expect(find.text(l10nOf(tester).importPreviewTitle), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('import-cancel')));
      await tester.pumpAndSettle();

      expect(transfer.importCalls, 0);
      expect(find.byType(DecksScreen), findsOneWidget);
      expect(find.byType(DeckScreen), findsNothing);
    });

    testWidgets(
      'ошибки архива: каждый код → своя строка ARB, без сырых текстов',
      (WidgetTester tester) async {
        final AppLocalizations l10n = AppLocalizationsRu();
        final Map<ArchiveErrorCode, String> expected =
            <ArchiveErrorCode, String>{
              ArchiveErrorCode.unsupportedVersion:
                  l10n.archiveErrorUnsupportedVersion,
              ArchiveErrorCode.corruptZip: l10n.archiveErrorCorruptZip,
              ArchiveErrorCode.missingEntry: l10n.archiveErrorMissingEntry,
              ArchiveErrorCode.invalidMeta: l10n.archiveErrorInvalidMeta,
              ArchiveErrorCode.invalidCards: l10n.archiveErrorInvalidCards,
              ArchiveErrorCode.tooLarge: l10n.archiveErrorTooLarge,
              ArchiveErrorCode.mediaMissing: l10n.archiveErrorMediaMissing,
              ArchiveErrorCode.deckNotFound: l10n.archiveErrorDeckNotFound,
              ArchiveErrorCode.invalidEntryName:
                  l10n.archiveErrorInvalidEntryName,
            };

        for (final MapEntry<ArchiveErrorCode, String> entry
            in expected.entries) {
          final FakeDeckRepository repository = FakeDeckRepository();
          final FakeDeckTransferService transfer = FakeDeckTransferService()
            ..previewError = ArchiveException(
              entry.key,
              details: 'сырой стектрейс: секрет',
            );
          final FakeFileGateway gateway = FakeFileGateway();

          await pumpDecks(
            tester,
            repository: repository,
            transfer: transfer,
            gateway: gateway,
          );
          await startImport(tester);

          expect(
            find.text(entry.value),
            findsOneWidget,
            reason: 'Неверное сообщение для кода ${entry.key.name}',
          );
          expect(find.textContaining('сырой стектрейс'), findsNothing);
          expect(find.byType(AlertDialog), findsNothing);
        }
      },
    );

    testWidgets('прочие ошибки → общая строка ARB без текста исключения', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository();
      final FakeDeckTransferService transfer = FakeDeckTransferService()
        ..previewError = StateError('internal boom / secret path');
      final FakeFileGateway gateway = FakeFileGateway();

      await pumpDecks(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      await startImport(tester);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.archiveErrorUnknown), findsOneWidget);
      expect(find.textContaining('internal boom'), findsNothing);
    });

    testWidgets('ошибка чтения файла → общая строка ARB', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = FakeDeckRepository();
      final FakeDeckTransferService transfer = FakeDeckTransferService();
      final FakeFileGateway gateway = FakeFileGateway()
        ..readError = StateError('boom: read failed');

      await pumpDecks(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      await startImport(tester);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.archiveErrorUnknown), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      expect(transfer.previewCalls, 0);
    });

    testWidgets('ошибка импорта после подтверждения → строка ARB', (
      WidgetTester tester,
    ) async {
      final FakeDeckRepository repository = repositoryWithImportedDeck();
      final FakeDeckTransferService transfer = FakeDeckTransferService()
        ..importError = const ArchiveException(
          ArchiveErrorCode.invalidCards,
          details: 'сырой стектрейс',
        );
      final FakeFileGateway gateway = FakeFileGateway();

      await pumpDecks(
        tester,
        repository: repository,
        transfer: transfer,
        gateway: gateway,
      );
      await startImport(tester);
      await tester.tap(find.byKey(const ValueKey<String>('import-confirm')));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.archiveErrorInvalidCards), findsOneWidget);
      expect(find.textContaining('сырой стектрейс'), findsNothing);
      expect(find.byType(DeckScreen), findsNothing);
    });
  });
}
