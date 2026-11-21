import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/generation/generation_plan_details.dart';

import '../../helpers/pump_app.dart' show ruLocalizationDelegates;

/// 7.18.1 §2.5: раскрывающийся блок «Подробнее» карточки плана.
void main() {
  ParsedDocument docOf(String text) => ParsedDocument(
    format: DocumentFormat.txt,
    fileName: 'лекция.txt',
    text: text,
    sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
  );

  ModelCapabilities capabilitiesOf() => const ModelCapabilities(
    contextWindowTokens: 128000,
    contextSource: CapabilitySource.officialCatalog,
    maxOutputTokens: 8192,
  );

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: ruLocalizationDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  ModelLimits userLimits({DateTime? at, GenerationPricing? pricing}) =>
      ModelLimits(
        contextTokens: Sourced<int>(
          128000,
          source: CapabilitySource.userConfigured,
          observedAt: at,
        ),
        maxInputTokens: Sourced<int>(
          120000,
          source: CapabilitySource.userConfigured,
          observedAt: at,
        ),
        maxOutputTokens: const Sourced<int>.absent(),
        pricing: pricing == null
            ? const Sourced<GenerationPricing>.absent()
            : Sourced<GenerationPricing>(
                pricing,
                source: CapabilitySource.officialCatalog,
              ),
      );

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-plan-details')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('показывает модель, контекст с датой, стратегию и числа плана', (
    WidgetTester tester,
  ) async {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[docOf('Материал лекции о фотосинтезе.')],
      capabilities: capabilitiesOf(),
      wishes: '5 карточек',
      requestedCards: 5,
    );
    final DateTime at = DateTime.utc(2026, 11, 20);
    await tester.pumpWidget(
      wrap(
        GenerationPlanDetails(
          plan: plan,
          model: 'deepseek-chat',
          limits: userLimits(at: at),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expand(tester);

    expect(
      find.byKey(const ValueKey<String>('plan-detail-model')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('plan-detail-model')))
          .data,
      'deepseek-chat',
    );
    final String context = tester
        .widget<Text>(find.byKey(const ValueKey<String>('plan-detail-context')))
        .data!;
    expect(context, contains('128 000'));
    expect(context, contains('задано вручную'));
    expect(context, contains('проверено 20.11.2026'));
    final String input = tester
        .widget<Text>(find.byKey(const ValueKey<String>('plan-detail-input')))
        .data!;
    expect(input, contains('приблизительно'));
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('plan-detail-strategy')),
          )
          .data,
      'весь документ в одном запросе',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('plan-detail-parts')))
          .data,
      '${plan.partCount}',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('plan-detail-batches')),
          )
          .data,
      '${plan.chunks.length}',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('plan-detail-cost')))
          .data,
      contains('неизвестна'),
    );
    // §3.4: каталог изображений входит в `D` — его токены видны в «Подробнее».
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('plan-detail-catalog')),
          )
          .data,
      '${plan.estimate.catalogTokens}',
    );
    expect(
      find.byKey(const ValueKey<String>('plan-detail-note')),
      findsOneWidget,
    );
  });

  testWidgets('число провайдера отдельно от резерва и бюджета', (
    WidgetTester tester,
  ) async {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[docOf('Материал лекции о фотосинтезе.')],
      capabilities: capabilitiesOf(),
      wishes: '5 карточек',
      requestedCards: 5,
      nativeCount: const NativeInputCount(
        tokens: 777,
        source: 'count_tokens:openaiCompletions',
      ),
    );
    await tester.pumpWidget(
      wrap(GenerationPlanDetails(plan: plan, model: 'gpt-test')),
    );
    await tester.pumpAndSettle();
    await expand(tester);
    String textOf(String id) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(id))).data!;
    // §3: результат провайдера — отдельная строка, а не «бюджет с запасом».
    expect(textOf('plan-detail-input'), 'нативный подсчёт: 777 токенов');
    expect(textOf('plan-detail-input-native'), contains('777'));
    expect(textOf('plan-detail-input-margin'), contains('24'));
    expect(textOf('plan-detail-input-budget'), contains('801'));
    expect(
      textOf('plan-detail-input-budget'),
      isNot(contains('нативный')),
      reason: 'резерв не выдаётся за результат нативного подсчёта',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('plan-detail-sources')),
          )
          .data,
      isNotEmpty,
    );
  });

  testWidgets('смешанный подсчёт: native + оценённая схема, не «точно»', (
    WidgetTester tester,
  ) async {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[docOf('Материал лекции о фотосинтезе.')],
      capabilities: capabilitiesOf(),
      wishes: '5 карточек',
      requestedCards: 5,
      nativeCount: const NativeInputCount(
        tokens: 777,
        estimatedExtraTokens: 100,
        estimatedComponents: <String>[NativeInputCount.schemaComponent],
        source: 'count_tokens:gemini-generate-content',
      ),
    );
    await tester.pumpWidget(
      wrap(GenerationPlanDetails(plan: plan, model: 'gemini-test')),
    );
    await tester.pumpAndSettle();
    await expand(tester);
    String textOf(String id) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(id))).data!;
    expect(textOf('plan-detail-input'), contains('смешанный: нативно 777'));
    expect(textOf('plan-detail-input-extra'), contains('100'));
    expect(textOf('plan-detail-input-extra'), contains('схема ответа'));
    // 777 + 100 = 877; резерв 10 % = 88; бюджет 965.
    expect(textOf('plan-detail-input-margin'), contains('88'));
    expect(textOf('plan-detail-input-budget'), contains('965'));
    expect(
      plan.inputPlan!.accuracy,
      InputAccuracy.estimated,
      reason: 'смешанный результат не показывается как полностью точный',
    );
  });

  testWidgets('неизвестный Vision — предупреждение, а не «не поддерживает»', (
    WidgetTester tester,
  ) async {
    final ModelCapabilities capabilities = resolveModelCapabilities(
      ProviderAccount(
        id: 'custom',
        label: 'Свой сервер',
        protocol: ProviderProtocol.anthropicMessages,
        baseUrl: 'https://api.example.test',
        modelId: 'some-model',
        requiresApiKey: true,
      ),
    );
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[docOf('Материал лекции о фотосинтезе.')],
      capabilities: capabilities,
      documentImages: <DocumentImage>[
        DocumentImage(
          fileName: 'схема.png',
          bytes: Uint8List.fromList(
            List<int>.generate(4096, (int i) => (i * 7 + 1) % 251),
          ),
          mediaType: AttachmentMediaType.png,
          width: 800,
          height: 600,
        ),
      ],
      requestedCards: 3,
    );
    await tester.pumpWidget(
      wrap(GenerationPlanDetails(plan: plan, model: 'some-model')),
    );
    await tester.pumpAndSettle();
    await expand(tester);
    final String warnings = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('plan-detail-warnings')),
        )
        .data!;
    expect(warnings, contains('Совместимость изображений'));
    expect(warnings, isNot(contains('не принимает изображения')));
  });

  testWidgets(
    'известный тариф — стоимость, неизвестные лимиты — предупреждение',
    (WidgetTester tester) async {
      final GenerationPlan plan = const GenerationPlanBuilder().build(
        documents: <ParsedDocument>[docOf('Материал лекции о фотосинтезе.')],
        capabilities: capabilitiesOf(),
      );
      await tester.pumpWidget(
        wrap(
          GenerationPlanDetails(
            plan: plan,
            model: 'gpt-test',
            limits: userLimits(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expand(tester);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('plan-detail-cost')),
            )
            .data,
        contains('неизвестна'),
      );
      // Неизвестный лимит вывода модели честно перечислен, а не выдуман.
      expect(
        find.byKey(const ValueKey<String>('plan-detail-unknown-limits')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('plan-detail-unknown-limits')),
            )
            .data,
        contains('max_output_tokens'),
      );
      // §5: предполагаемые 32 МБ — не характеристика модели; лимит честно
      // перечислен как неизвестный (предупреждение о payload — отдельно).
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('plan-detail-unknown-limits')),
            )
            .data,
        contains('max_request_bytes'),
      );
    },
  );
}
