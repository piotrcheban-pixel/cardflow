import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Красная фаза: экран «Настройки генерации», блок OpenAI-совместимого
/// сервера (ADR-013, SPEC A6.6/3.4/A8.6).
///
/// Проверяется: загрузка сохранённых значений, индикатор наличия ключа,
/// валидация до записи, сохранение адреса/модели в `GenerationSettingsStore`,
/// запись/удаление ключа только через `ApiKeyStore` (secure storage),
/// снекбары из ARB, состояние ошибки загрузки с повтором. Значение ключа
/// не выводится ни в поле, ни в текстовые виджеты.

/// Хранилище настроек, чтение которого возвращает управляемый `Future`.
class _PendingSettingsStore implements GenerationSettingsStore {
  /// Завершается тестом, чтобы проверить состояние загрузки.
  final Completer<OpenAiCompatibleSettings> completer =
      Completer<OpenAiCompatibleSettings>();

  @override
  Future<OpenAiCompatibleSettings> readOpenAiCompatible() => completer.future;

  @override
  Future<void> writeOpenAiCompatible(OpenAiCompatibleSettings settings) async {}
}

/// Хранилище настроек с падающим чтением (проверка ошибки загрузки и retry).
class _FlakySettingsStore implements GenerationSettingsStore {
  /// Создаёт хранилище; [failuresLeft] — сколько чтений упадут до успеха.
  _FlakySettingsStore({required this.settings, required this.failuresLeft});

  /// Настройки, отдаваемые при успешном чтении.
  OpenAiCompatibleSettings settings;

  /// Оставшееся число падений чтения.
  int failuresLeft;

  /// Сколько раз читали настройки.
  int readCalls = 0;

  /// Сколько раз писали настройки.
  int writeCalls = 0;

  @override
  Future<OpenAiCompatibleSettings> readOpenAiCompatible() async {
    readCalls++;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('boom-read');
    }
    return settings;
  }

  @override
  Future<void> writeOpenAiCompatible(OpenAiCompatibleSettings value) async {
    writeCalls++;
    settings = value;
  }
}

/// Хранилище настроек с падающей записью (снекбар ошибки сохранения).
class _FailingWriteSettingsStore implements GenerationSettingsStore {
  /// Сколько раз читали настройки.
  int readCalls = 0;

  /// Сколько раз пытались записать настройки.
  int writeCalls = 0;

  @override
  Future<OpenAiCompatibleSettings> readOpenAiCompatible() async {
    readCalls++;
    return const OpenAiCompatibleSettings();
  }

  @override
  Future<void> writeOpenAiCompatible(OpenAiCompatibleSettings settings) async {
    writeCalls++;
    throw StateError('boom-write');
  }
}

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    GenerationSettingsStore? settingsStore,
    FakeApiKeyStore? apiKeyStore,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          generationSettingsStore:
              settingsStore ?? FakeGenerationSettingsStore(),
          apiKeyStore: apiKeyStore ?? FakeApiKeyStore(),
        ),
        home: const GenerationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder baseUrlField() =>
      find.byKey(const ValueKey<String>('settings-base-url'));

  Finder modelField() => find.byKey(const ValueKey<String>('settings-model'));

  Finder apiKeyField() =>
      find.byKey(const ValueKey<String>('settings-api-key'));

  Finder saveButton() => find.byKey(const ValueKey<String>('settings-save'));

  String fieldText(WidgetTester tester, Finder finder) =>
      tester.widget<TextField>(finder).controller!.text;

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(saveButton());
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Убирает снекбар (и его таймер), чтобы он не влиял на следующие тесты.
  Future<void> hideSnackbar(WidgetTester tester) async {
    M3ESnackbar.defaultController.dismiss(immediate: true);
    await tester.pumpAndSettle();
  }

  group('Настройки генерации: загрузка', () {
    testWidgets('loading: индикатор загрузки, затем поля и заголовки из ARB', (
      WidgetTester tester,
    ) async {
      final _PendingSettingsStore store = _PendingSettingsStore();

      await tester.pumpWidget(
        appWithHome(
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(),
            generationSettingsStore: store,
            apiKeyStore: FakeApiKeyStore(),
          ),
          home: const GenerationSettingsScreen(),
        ),
      );
      await tester.pump();

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.settingsTitle), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(baseUrlField(), findsNothing);

      store.completer.complete(const OpenAiCompatibleSettings());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(baseUrlField(), findsOneWidget);
      expect(modelField(), findsOneWidget);
      expect(apiKeyField(), findsOneWidget);
    });

    testWidgets('пустые поля и нет индикатора ключа без сохранённых настроек', (
      WidgetTester tester,
    ) async {
      final FakeGenerationSettingsStore store = FakeGenerationSettingsStore();
      final FakeApiKeyStore keys = FakeApiKeyStore();

      await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.settingsTitle), findsOneWidget);
      expect(find.text(l10n.settingsOpenAiCompatibleTitle), findsOneWidget);
      expect(
        find.text(l10n.settingsOpenAiCompatibleDescription),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsServerAddressLabel), findsOneWidget);
      expect(find.text(l10n.settingsModelLabel), findsOneWidget);
      expect(find.text(l10n.settingsApiKeyLabel), findsOneWidget);
      expect(find.text(l10n.settingsApiKeyHelper), findsOneWidget);
      // Подсказки заданы в декорациях (видны, когда подпись поля всплывает).
      expect(
        tester.widget<TextField>(baseUrlField()).decoration!.hintText,
        l10n.settingsServerAddressHint,
      );
      expect(
        tester.widget<TextField>(modelField()).decoration!.hintText,
        l10n.settingsModelHint,
      );
      expect(fieldText(tester, baseUrlField()), isEmpty);
      expect(fieldText(tester, modelField()), isEmpty);
      expect(fieldText(tester, apiKeyField()), isEmpty);
      expect(find.text(l10n.settingsApiKeyConfigured), findsNothing);
      expect(store.readCalls, 1);
      expect(keys.readCalls, 1);
    });

    testWidgets('поле ключа скрыто и без автокоррекции (SPEC 3.4)', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      final TextField keyField = tester.widget<TextField>(apiKeyField());
      expect(keyField.obscureText, isTrue);
      expect(keyField.autocorrect, isFalse);
      expect(keyField.enableSuggestions, isFalse);
    });

    testWidgets('загружает сохранённые адрес и модель и индикатор ключа', (
      WidgetTester tester,
    ) async {
      final FakeGenerationSettingsStore store = FakeGenerationSettingsStore(
        const OpenAiCompatibleSettings(
          baseUrl: 'http://localhost:11434/v1',
          model: 'llama3.1',
        ),
      );
      final FakeApiKeyStore keys = FakeApiKeyStore(<GenerationProvider, String>{
        GenerationProvider.openaiCompatible: 'sk-stored-key',
      });

      await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

      final AppLocalizations l10n = l10nOf(tester);
      expect(fieldText(tester, baseUrlField()), 'http://localhost:11434/v1');
      expect(fieldText(tester, modelField()), 'llama3.1');
      expect(find.text(l10n.settingsApiKeyConfigured), findsOneWidget);
      // Сохранённый ключ не подставляется в поле и не рендерится текстом.
      expect(fieldText(tester, apiKeyField()), isEmpty);
      expect(find.text('sk-stored-key'), findsNothing);
    });

    testWidgets('ошибка загрузки: сообщение из ARB и повтор грузит настройки', (
      WidgetTester tester,
    ) async {
      final _FlakySettingsStore store = _FlakySettingsStore(
        settings: const OpenAiCompatibleSettings(
          baseUrl: 'http://localhost:1234/v1',
          model: 'qwen2.5',
        ),
        failuresLeft: 1,
      );

      await pumpSettings(tester, settingsStore: store);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.settingsLoadError), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, l10n.retry),
        findsOneWidget,
        reason: 'Должна быть кнопка «Повторить»',
      );
      expect(
        find.textContaining('boom'),
        findsNothing,
        reason: 'Сырой текст исключения не должен показываться пользователю',
      );
      expect(baseUrlField(), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, l10n.retry));
      await tester.pumpAndSettle();

      expect(store.readCalls, 2);
      expect(fieldText(tester, baseUrlField()), 'http://localhost:1234/v1');
      expect(fieldText(tester, modelField()), 'qwen2.5');
      expect(find.text(l10n.settingsLoadError), findsNothing);
    });
  });

  group('Настройки генерации: валидация', () {
    testWidgets('пустые адрес и модель: ошибки из ARB, запись не выполняется', (
      WidgetTester tester,
    ) async {
      final FakeGenerationSettingsStore store = FakeGenerationSettingsStore();
      final FakeApiKeyStore keys = FakeApiKeyStore();
      await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

      await tapSave(tester);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.settingsAddressEmptyError), findsOneWidget);
      expect(find.text(l10n.settingsModelEmptyError), findsOneWidget);
      expect(store.writeCalls, 0);
      expect(keys.writeCalls, 0);
      expect(keys.deleteCalls, 0);
    });

    testWidgets('некорректный адрес: ошибка из ARB, запись не выполняется', (
      WidgetTester tester,
    ) async {
      final FakeGenerationSettingsStore store = FakeGenerationSettingsStore();
      final FakeApiKeyStore keys = FakeApiKeyStore();
      await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

      await tester.enterText(baseUrlField(), 'example.com');
      await tester.enterText(modelField(), 'deepseek-chat');
      await tester.enterText(apiKeyField(), 'sk-new-key');
      await tapSave(tester);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.settingsAddressInvalidError), findsOneWidget);
      expect(find.text(l10n.settingsAddressEmptyError), findsNothing);
      expect(find.text(l10n.settingsModelEmptyError), findsNothing);
      expect(store.writeCalls, 0);
      expect(keys.writeCalls, 0);
      expect(keys.deleteCalls, 0);
    });

    testWidgets('пустая (из пробелов) модель: ошибка, запись не выполняется', (
      WidgetTester tester,
    ) async {
      final FakeGenerationSettingsStore store = FakeGenerationSettingsStore();
      final FakeApiKeyStore keys = FakeApiKeyStore();
      await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

      await tester.enterText(baseUrlField(), 'https://api.deepseek.com');
      await tester.enterText(modelField(), '   ');
      await tapSave(tester);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.settingsModelEmptyError), findsOneWidget);
      expect(find.text(l10n.settingsAddressInvalidError), findsNothing);
      expect(store.writeCalls, 0);
      expect(keys.writeCalls, 0);
      expect(keys.deleteCalls, 0);
    });
  });

  group('Настройки генерации: сохранение', () {
    testWidgets(
      'валидные данные: адрес и модель в настройки, ключ в secure-хранилище, '
      'снекбар, поле ключа очищено',
      (WidgetTester tester) async {
        final FakeGenerationSettingsStore store = FakeGenerationSettingsStore();
        final FakeApiKeyStore keys = FakeApiKeyStore();
        await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

        await tester.enterText(baseUrlField(), '  https://api.deepseek.com  ');
        await tester.enterText(modelField(), ' deepseek-chat ');
        await tester.enterText(apiKeyField(), ' sk-secret-key ');
        await tapSave(tester);

        final AppLocalizations l10n = l10nOf(tester);
        expect(store.writeCalls, 1);
        expect(
          store.settings,
          const OpenAiCompatibleSettings(
            baseUrl: 'https://api.deepseek.com',
            model: 'deepseek-chat',
          ),
        );
        expect(fieldText(tester, baseUrlField()), 'https://api.deepseek.com');
        expect(fieldText(tester, modelField()), 'deepseek-chat');
        expect(keys.writeCalls, 1);
        expect(keys.deleteCalls, 0);
        expect(keys.keys[GenerationProvider.openaiCompatible], 'sk-secret-key');
        expect(fieldText(tester, apiKeyField()), isEmpty);
        expect(find.text(l10n.settingsApiKeyConfigured), findsOneWidget);
        expect(find.text(l10n.settingsSaved), findsOneWidget);
        expect(
          find.text('sk-secret-key'),
          findsNothing,
          reason: 'Значение ключа не должно выводиться в текстовые виджеты',
        );

        await hideSnackbar(tester);
        expect(find.text(l10n.settingsSaved), findsNothing);
      },
    );

    testWidgets('пустое поле ключа при сохранении удаляет сохранённый ключ', (
      WidgetTester tester,
    ) async {
      final FakeGenerationSettingsStore store = FakeGenerationSettingsStore();
      final FakeApiKeyStore keys = FakeApiKeyStore(<GenerationProvider, String>{
        GenerationProvider.openaiCompatible: 'sk-old-key',
      });
      await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.settingsApiKeyConfigured), findsOneWidget);

      await tester.enterText(baseUrlField(), 'http://localhost:11434/v1');
      await tester.enterText(modelField(), 'llama3.1');
      await tapSave(tester);

      expect(store.writeCalls, 1);
      expect(keys.deleteCalls, 1);
      expect(keys.writeCalls, 0);
      expect(
        keys.keys.containsKey(GenerationProvider.openaiCompatible),
        isFalse,
      );
      expect(find.text(l10n.settingsApiKeyConfigured), findsNothing);
      expect(find.text(l10n.settingsSaved), findsOneWidget);

      await hideSnackbar(tester);
    });

    testWidgets('ошибка сохранения: снекбар из ARB без сырых исключений', (
      WidgetTester tester,
    ) async {
      final _FailingWriteSettingsStore store = _FailingWriteSettingsStore();
      final FakeApiKeyStore keys = FakeApiKeyStore();
      await pumpSettings(tester, settingsStore: store, apiKeyStore: keys);

      await tester.enterText(baseUrlField(), 'https://api.deepseek.com');
      await tester.enterText(modelField(), 'deepseek-chat');
      await tester.enterText(apiKeyField(), 'sk-new-key');
      await tapSave(tester);

      final AppLocalizations l10n = l10nOf(tester);
      expect(store.writeCalls, 1);
      expect(find.text(l10n.settingsSaveError), findsOneWidget);
      expect(
        find.textContaining('boom'),
        findsNothing,
        reason: 'Сырой текст исключения не должен показываться пользователю',
      );
      expect(keys.writeCalls, 0);

      await hideSnackbar(tester);
    });
  });
}
