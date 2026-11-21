import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
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
          .widget<Text>(find.byKey(const ValueKey<String>('plan-detail-catalog')))
          .data,
      '${plan.estimate.catalogTokens}',
    );
    expect(
      find.byKey(const ValueKey<String>('plan-detail-note')),
      findsOneWidget,
    );
  });

  testWidgets('точный подсчёт показывает count_tokens, партии — из плана', (
    WidgetTester tester,
  ) async {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[docOf('Материал лекции о фотосинтезе.')],
      capabilities: capabilitiesOf(),
      wishes: '5 карточек',
      requestedCards: 5,
      exactInputTokens: 777,
      inputTokenSource: 'count_tokens:openaiCompletions',
    );
    await tester.pumpWidget(
      wrap(GenerationPlanDetails(plan: plan, model: 'gpt-test')),
    );
    await tester.pumpAndSettle();
    await expand(tester);
    final String input = tester
        .widget<Text>(find.byKey(const ValueKey<String>('plan-detail-input')))
        .data!;
    expect(input, contains('точно'));
    expect(input, contains('нативный подсчёт'));
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('plan-detail-sources')),
          )
          .data,
      isNotEmpty,
    );
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
    },
  );
}
