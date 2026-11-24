import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/generation/api_key_verifier.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/api/models/model_capability_service.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_capability_discovery.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_accounts_store.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';

/// Итерация 7.5 (ADR-020): экран «Провайдеры».
///
/// Проверяется: пустое состояние, добавление из каталога и пользовательское,
/// сохранение ключа в защищённое хранилище (в том числе когда адрес/модель
/// вводить не нужно — регрессия D1 владельца), проверка подключения,
/// изменение, удаление, выбор основного, проверка записи ключа (D3).
class _PendingAccountsStore implements ProviderAccountsStore {
  final Completer<ProviderAccounts> completer = Completer<ProviderAccounts>();

  @override
  Future<ProviderAccounts> read() => completer.future;

  @override
  Future<void> write(ProviderAccounts accounts) async {}
}

class _FailingAccountsStore implements ProviderAccountsStore {
  /// Сколько чтений упадут до успеха.
  int failuresLeft = 1;
  int readCalls = 0;

  @override
  Future<ProviderAccounts> read() async {
    readCalls++;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('boom-read');
    }
    return ProviderAccounts.empty;
  }

  @override
  Future<void> write(ProviderAccounts accounts) async {}
}

class _EmptyCapabilityCache implements ModelCapabilityCache {
  @override
  Future<void> invalidateAccount(String accountId) async {}

  @override
  Future<ModelCapabilityRecord?> read({
    required String accountId,
    required ProviderProtocol protocol,
    required String baseUrl,
    required String model,
  }) async => null;

  @override
  Future<List<ModelCapabilityRecord>> readAll() async =>
      const <ModelCapabilityRecord>[];

  @override
  Future<void> write(ModelCapabilityRecord record) async {}
}

/// Сервис характеристик без drift-кэша: в widget-тесте БД не поднимается.
class _FakeCapabilityService extends ModelCapabilityService {
  _FakeCapabilityService()
    : super(
        dio: Dio(),
        readApiKey: (String id) async => null,
        cache: _EmptyCapabilityCache(),
      );

  @override
  Future<ModelLimits> limitsFor(ProviderAccount account) async =>
      const ModelLimits.absent();

  @override
  Future<CapabilityRefresh> refresh(ProviderAccount account) async =>
      CapabilityRefresh(
        result: DiscoveryResult(
          status: DiscoveryStatus.unsupported,
          accountId: account.id,
          model: account.modelId,
        ),
      );
}

class _Transport implements GenerationTransport {
  _Transport({this.error});

  final Object? error;
  int calls = 0;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    final Object? failure = error;
    if (failure != null) throw failure;
    return <String, Object?>{'ok': true};
  }
}

void main() {
  late FakeProviderAccountsStore store;
  late FakeApiKeyStore keys;
  late _Transport transport;

  setUp(() {
    store = FakeProviderAccountsStore();
    keys = FakeApiKeyStore();
    transport = _Transport();
  });

  List<Override> overrides() =>
      decksOverrides(
        deckRepository: FakeDeckRepository(),
        providerAccountsStore: store,
        apiKeyStore: keys,
      )..add(
        apiKeyVerifierProvider.overrideWithValue(
          ApiKeyVerifier(
            adapters: <GenerationProviderAdapter>[
              const OpenAiAdapter(),
              const GeminiAdapter(),
              const AnthropicAdapter(),
              const OpenAiCompatibleAdapter(),
            ],
            apiKeyStore: keys,
            transport: transport,
          ),
        ),
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<Override>? customOverrides,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: customOverrides ?? overrides(),
        home: const GenerationSettingsScreen(),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> openAddMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('providers-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openPresetDialog(WidgetTester tester) async {
    await openAddMenu(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('providers-add-preset')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openCustomDialog(WidgetTester tester) async {
    await openAddMenu(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('providers-add-custom')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('provider-save')));
    await tester.pumpAndSettle();
  }

  Future<void> hideSnackbar(WidgetTester tester) async {
    M3ESnackbar.defaultController.dismiss(immediate: true);
    await tester.pumpAndSettle();
  }

  testWidgets('loading: индикатор загрузки, затем пустое состояние', (
    WidgetTester tester,
  ) async {
    final _PendingAccountsStore pending = _PendingAccountsStore();
    await pumpScreen(
      tester,
      settle: false,
      customOverrides: decksOverrides(
        deckRepository: FakeDeckRepository(),
        providerAccountsStore: pending,
        apiKeyStore: keys,
      ),
    );

    expect(find.byType(AppSkeleton), findsWidgets);
    final AppLocalizations l10n = l10nOf(tester);
    expect(find.text(l10n.providersTitle), findsOneWidget);

    pending.completer.complete(ProviderAccounts.empty);
    await tester.pumpAndSettle();

    expect(find.byType(AppSkeleton), findsNothing);
    expect(find.text(l10n.providersEmptyTitle), findsOneWidget);
    expect(find.text(l10n.providersEmptyDescription), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('providers-add')), findsOneWidget);
  });

  testWidgets('ошибка загрузки: сообщение из ARB и повтор', (
    WidgetTester tester,
  ) async {
    final _FailingAccountsStore failing = _FailingAccountsStore();
    await pumpScreen(
      tester,
      customOverrides: decksOverrides(
        deckRepository: FakeDeckRepository(),
        providerAccountsStore: failing,
        apiKeyStore: keys,
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);
    expect(find.text(l10n.settingsLoadError), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, l10n.retry));
    await tester.pumpAndSettle();
    expect(failing.readCalls, 2);
    expect(find.text(l10n.providersEmptyTitle), findsOneWidget);
  });

  testWidgets(
    'добавление DeepSeek из каталога: ключ сохраняется без ввода адреса',
    (WidgetTester tester) async {
      await pumpScreen(tester);
      final AppLocalizations l10n = l10nOf(tester);

      await openPresetDialog(tester);
      expect(find.text(l10n.providersAddPreset), findsWidgets);
      // Адрес заполняется из каталога и не редактируется.
      expect(find.text('https://api.deepseek.com'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('provider-key')),
        'sk-deepseek-key',
      );
      await tapSave(tester);

      expect(store.writeCalls, 1);
      final ProviderAccount saved = store.accounts.accounts.single;
      expect(saved.id, 'deepseek');
      expect(saved.presetId, 'deepseek');
      expect(saved.baseUrl, 'https://api.deepseek.com');
      expect(saved.modelId, 'deepseek-flash');
      expect(
        keys.keys['deepseek'],
        'sk-deepseek-key',
        reason:
            'регрессия D1: ключ пишется в secure storage без ручного ввода '
            'адреса и модели',
      );
      expect(find.text(l10n.providersSaved), findsOneWidget);
      expect(find.text('sk-deepseek-key'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('provider-card-deepseek')),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsKeyConfigured), findsOneWidget);

      await hideSnackbar(tester);
    },
  );

  testWidgets('каталог: выбор другого поставщика и модели', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);
    await openPresetDialog(tester);

    await tester.tap(
      find
          .descendant(
            of: find.byType(AppDialog),
            matching: find.byType(DropdownButtonFormField<String>),
          )
          .first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('OpenRouter').last);
    await tester.pumpAndSettle();
    expect(find.text('https://openrouter.ai/api/v1'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-key')),
      'sk-openrouter',
    );
    await tapSave(tester);

    final ProviderAccount saved = store.accounts.accounts.single;
    expect(saved.id, 'openrouter');
    expect(saved.baseUrl, 'https://openrouter.ai/api/v1');
    expect(saved.modelId, 'openai/gpt-4o-mini');
    expect(keys.keys['openrouter'], 'sk-openrouter');
    await hideSnackbar(tester);
  });

  testWidgets(
    'каталог: без ключа у облачного провайдера — ошибка, без записи',
    (WidgetTester tester) async {
      await pumpScreen(tester);
      final AppLocalizations l10n = l10nOf(tester);
      await openPresetDialog(tester);
      await tapSave(tester);

      expect(find.text(l10n.settingsKeyEmptyError), findsOneWidget);
      expect(store.writeCalls, 0);
      expect(keys.writeCalls, 0);
      expect(find.byType(AppDialog), findsOneWidget);
    },
  );

  testWidgets('каталог: локальному серверу ключ не нужен', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);
    await openPresetDialog(tester);

    await tester.tap(
      find
          .descendant(
            of: find.byType(AppDialog),
            matching: find.byType(DropdownButtonFormField<String>),
          )
          .first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ollama (Local)').last);
    await tester.pumpAndSettle();

    await tapSave(tester);

    final ProviderAccount saved = store.accounts.accounts.single;
    expect(saved.id, 'ollama');
    expect(saved.requiresApiKey, isFalse);
    expect(saved.baseUrl, 'http://localhost:11434/v1');
    expect(keys.writeCalls, 0);
    expect(find.text(l10nOf(tester).providersKeyNotRequired), findsOneWidget);
    await hideSnackbar(tester);
  });

  testWidgets('пользовательская модель API: поля и сохранение', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);
    await openCustomDialog(tester);
    expect(find.text(l10n.providersAddCustom), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-name')),
      'Мой сервер',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-base-url')),
      'http://localhost:1234/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-model')),
      'qwen2.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-key')),
      'sk-local',
    );
    await tapSave(tester);

    final ProviderAccount saved = store.accounts.accounts.single;
    expect(saved.label, 'Мой сервер');
    expect(saved.presetId, isNull);
    expect(saved.protocol, ProviderProtocol.openaiCompletions);
    expect(saved.baseUrl, 'http://localhost:1234/v1');
    expect(saved.modelId, 'qwen2.5');
    expect(keys.keys[saved.id], 'sk-local');
    expect(
      saved.id,
      'provider',
      reason: 'Кириллическое имя даёт безопасный slug по умолчанию (ADR-020)',
    );
    await hideSnackbar(tester);
  });

  testWidgets('пользовательская модель: пустые поля — ошибки, без записи', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);
    await openCustomDialog(tester);
    await tapSave(tester);

    expect(find.text(l10n.providersNameEmptyError), findsOneWidget);
    expect(find.text(l10n.settingsAddressEmptyError), findsOneWidget);
    expect(find.text(l10n.settingsModelEmptyError), findsOneWidget);
    expect(store.writeCalls, 0);
  });

  testWidgets(
    'пользовательская модель: переключатель изображений сохраняется',
    (WidgetTester tester) async {
      await pumpScreen(tester);
      await openCustomDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('provider-name')),
        'Свой сервер',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('provider-base-url')),
        'http://localhost:1234/v1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('provider-model')),
        'qwen2.5',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('provider-supports-vision')),
      );
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(store.accounts.accounts.single.supportsVision, isTrue);
      await hideSnackbar(tester);
    },
  );

  testWidgets('пользовательская модель: Vision выводится из имени flash', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester);
    await openCustomDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-name')),
      'DeepSeek Flash',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-base-url')),
      'https://api.deepseek.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-model')),
      'deepseek-flash',
    );
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(store.accounts.accounts.single.supportsVision, isTrue);
    await hideSnackbar(tester);
  });

  testWidgets('изменение: новая модель, ключ не трогаем пустым полем', (
    WidgetTester tester,
  ) async {
    store.accounts = ProviderAccounts.empty.withAccount(
      testProviderAccount(presetId: 'deepseek'),
    );
    keys.keys['deepseek'] = 'sk-existing';
    await pumpScreen(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-edit-deepseek')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find
          .descendant(
            of: find.byType(AppDialog),
            matching: find.byType(DropdownButtonFormField<String>),
          )
          .last,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('DeepSeek Reasoner').last);
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(
      store.accounts.accountById('deepseek')!.modelId,
      'deepseek-reasoner',
    );
    expect(keys.keys['deepseek'], 'sk-existing');
    expect(keys.writeCalls, 0);
    await hideSnackbar(tester);
  });

  testWidgets('проверка подключения: успех и ошибка ключа', (
    WidgetTester tester,
  ) async {
    store.accounts = ProviderAccounts.empty.withAccount(
      testProviderAccount(presetId: 'deepseek'),
    );
    keys.keys['deepseek'] = 'sk-deepseek';
    await pumpScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-check-deepseek')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.providersCheckValid), findsOneWidget);
    expect(transport.calls, 1);
    await hideSnackbar(tester);

    transport = _Transport(
      error: const GenerationException(GenerationErrorCode.invalidApiKey),
    );
    await pumpScreen(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('provider-check-deepseek')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.providersCheckInvalid), findsOneWidget);
    await hideSnackbar(tester);
  });

  testWidgets('удаление: подтверждение удаляет аккаунт и ключ', (
    WidgetTester tester,
  ) async {
    store.accounts = ProviderAccounts.empty.withAccount(
      testProviderAccount(presetId: 'deepseek'),
    );
    keys.keys['deepseek'] = 'sk-deepseek';
    await pumpScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-delete-deepseek')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.providersDeleteTitle), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-delete-cancel')),
    );
    await tester.pumpAndSettle();
    expect(store.accounts.accounts, hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-delete-deepseek')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey<String>('provider-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(store.accounts.isEmpty, isTrue);
    expect(keys.keys.containsKey('deepseek'), isFalse);
    expect(find.text(l10n.providersDeleted), findsOneWidget);
    expect(find.text(l10n.providersEmptyTitle), findsOneWidget);
    await hideSnackbar(tester);
  });

  testWidgets('выбор основного провайдера сохраняется', (
    WidgetTester tester,
  ) async {
    store.accounts = ProviderAccounts.empty
        .withAccount(testProviderAccount(presetId: 'deepseek'))
        .withAccount(testProviderAccount(presetId: 'groq'));
    await pumpScreen(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('provider-activate-groq')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('provider-activate-groq')),
    );
    await tester.pumpAndSettle();

    expect(store.accounts.activeAccountId, 'groq');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('provider-active-groq')),
    );
    expect(
      find.byKey(const ValueKey<String>('provider-active-groq')),
      findsOneWidget,
    );
    await hideSnackbar(tester);
  });

  testWidgets('ключ не подтверждён хранилищем: ошибка, аккаунт не сохранён', (
    WidgetTester tester,
  ) async {
    keys.dropWrites = true;
    await pumpScreen(tester);
    final AppLocalizations l10n = l10nOf(tester);

    await openPresetDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-key')),
      'sk-lost-key',
    );
    await tapSave(tester);

    expect(find.text(l10n.providersKeyStoreError), findsOneWidget);
    expect(
      store.writeCalls,
      0,
      reason: 'Аккаунт не сохраняется, если хранилище не вернуло ключ (D3)',
    );
    await hideSnackbar(tester);
  });
  testWidgets('характеристики модели: ручной ввод сохраняется в аккаунт', (
    WidgetTester tester,
  ) async {
    final ProviderAccount account = testProviderAccount(
      presetId: 'deepseek',
      modelId: 'deepseek-chat',
    );
    store.accounts = ProviderAccounts(
      accounts: <ProviderAccount>[account],
      activeAccountId: account.id,
    );
    await pumpScreen(
      tester,
      customOverrides: <Override>[
        ...overrides(),
        modelCapabilityServiceProvider.overrideWithValue(
          _FakeCapabilityService(),
        ),
      ],
    );
    final Finder section = find.byKey(
      ValueKey<String>('model-capabilities-${account.id}'),
    );
    await tester.scrollUntilVisible(section, 300);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey<String>('capabilities-context-field')),
      '65536',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('capabilities-input-field')),
      '60000',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('capabilities-output-field')),
      '8192',
    );
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-save')));
    await tester.pumpAndSettle();

    final ProviderAccount saved = store.accounts.active!;
    expect(saved.contextTokens, 65536);
    expect(saved.maxInputTokens, 60000);
    expect(saved.maxOutputTokens, 8192);
    expect(saved.capabilitiesSource, CapabilitySource.userConfigured);
    expect(saved.capabilitiesConfiguredAt, isNotNull);
  });
}
