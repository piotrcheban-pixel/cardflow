import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/sourced.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/settings/model_capability_section.dart';

import '../../helpers/generation_fakes.dart';

/// Блок характеристик модели в настройках (ADR-039 §6).
void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('показывает лимиты с источником и датой', (WidgetTester tester) async {
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
    expect(find.textContaining('неизвестно'), findsOneWidget);
    expect(find.textContaining('допущение приложения'), findsOneWidget);
  });

  testWidgets('обновление и сброс вызывают действия', (WidgetTester tester) async {
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
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-refresh')));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('Характеристики обновлены.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('capabilities-reset')));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(find.text('Значения сброшены к автоматическим.'), findsOneWidget);
  });

  testWidgets('ошибка загрузки показывается без исключения', (WidgetTester tester) async {
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
