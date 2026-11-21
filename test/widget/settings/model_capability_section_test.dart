import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/settings/model_capability_section.dart';

import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart' show ruLocalizationDelegates;

/// Блок характеристик модели в настройках (ADR-039 §6).
void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: ruLocalizationDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('показывает лимиты с источником и датой', (
    WidgetTester tester,
  ) async {
    final DateTime observedAt = DateTime.utc(2026, 11, 20);
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => ModelLimits(
            contextTokens: Sourced<int>(
              128000,
              source: CapabilitySource.providerApi,
              observedAt: observedAt,
              sourceRef: 'https://api.deepseek.com/models',
            ),
            maxOutputTokens: const Sourced<int>.absent(),
            maxImagesPerRequest: Sourced<int>(
              8,
              source: CapabilitySource.assumption,
            ),
          ),
          refresh: () async => true,
          reset: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Характеристики модели'), findsOneWidget);
    expect(find.textContaining('128 000'), findsOneWidget);
    expect(find.textContaining('из API провайдера'), findsOneWidget);
    expect(find.textContaining('проверено 20.11.2026'), findsOneWidget);
    // Неизвестны три значения: лимит входа, лимит вывода и вход изображений.
    expect(find.textContaining('неизвестно'), findsNWidgets(3));
    expect(find.textContaining('допущение приложения'), findsOneWidget);
  });

  testWidgets('вход изображений: значение, источник и дата проверки', (
    WidgetTester tester,
  ) async {
    final DateTime observedAt = DateTime.utc(2026, 11, 21);
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => ModelLimits(
            supportsImageInput: Sourced<bool>(
              true,
              source: CapabilitySource.providerApi,
              observedAt: observedAt,
              sourceRef: 'https://api.deepseek.com/models',
            ),
          ),
          refresh: () async => true,
          reset: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // §3.10: «вход изображений» — с источником и датой проверки.
    expect(find.textContaining('Вход изображений'), findsOneWidget);
    expect(find.textContaining('поддерживается'), findsOneWidget);
    expect(find.textContaining('из API провайдера'), findsOneWidget);
    expect(find.textContaining('проверено 21.11.2026'), findsOneWidget);
  });

  testWidgets('неизвестный вход изображений не показан как поддержка', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => const ModelLimits.absent(),
          refresh: () async => true,
          reset: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Finder row = find.byKey(
      const ValueKey<String>('capability-image-input'),
    );
    expect(row, findsOneWidget);
    final Text text = tester.widget<Text>(row);
    expect(text.data, contains('неизвестно'));
    expect(
      text.data,
      isNot(contains('поддерживается')),
      reason:
          'неизвестное значение нельзя выдавать за подтверждённую поддержку',
    );
  });

  testWidgets('допущение визуально отличается от подтверждённого значения', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => const ModelLimits(
            supportsImageInput: Sourced<bool>(
              true,
              source: CapabilitySource.assumption,
            ),
          ),
          refresh: () async => true,
          reset: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Text assumed = tester.widget<Text>(
      find.byKey(const ValueKey<String>('capability-image-input')),
    );
    expect(assumed.data, contains('допущение приложения'));
    expect(
      assumed.style?.fontStyle,
      FontStyle.italic,
      reason: 'допущение не должно выглядеть как подтверждённое значение',
    );
  });

  testWidgets('обновление и сброс вызывают действия', (
    WidgetTester tester,
  ) async {
    var refreshes = 0;
    var resets = 0;
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => const ModelLimits.absent(),
          refresh: () async {
            refreshes++;
            return true;
          },
          reset: () async {
            resets++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('capabilities-refresh')),
    );
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('Характеристики обновлены.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-reset')));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(find.text('Значения сброшены к автоматическим.'), findsOneWidget);
  });

  testWidgets('ручное редактирование контекста/входа/выхода', (
    WidgetTester tester,
  ) async {
    CapabilityDraft? saved;
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => ModelLimits(
            contextTokens: Sourced<int>(
              128000,
              source: CapabilitySource.providerApi,
              observedAt: DateTime.utc(2026, 11, 20),
              sourceRef: 'https://api.deepseek.com/models',
            ),
            maxOutputTokens: const Sourced<int>.absent(),
          ),
          refresh: () async => true,
          reset: () async {},
          save: (CapabilityDraft draft) async => saved = draft,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-edit')));
    await tester.pumpAndSettle();
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
    expect(saved, isNotNull);
    expect(saved!.contextTokens, 65536);
    expect(saved!.maxInputTokens, 60000);
    expect(saved!.maxOutputTokens, 8192);
  });

  testWidgets('пустое поле ручного ввода — автоматическое значение', (
    WidgetTester tester,
  ) async {
    CapabilityDraft? saved;
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => const ModelLimits.absent(),
          refresh: () async => true,
          reset: () async {},
          save: (CapabilityDraft draft) async => saved = draft,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.isEmpty, isTrue);
  });

  testWidgets('ошибка загрузки показывается без исключения', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ModelCapabilitySection(
          account: testProviderAccount(modelId: 'deepseek-chat'),
          loadLimits: () async => throw StateError('cache broken'),
          refresh: () async => false,
          reset: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось прочитать характеристики модели.'),
      findsOneWidget,
    );
  });
}
