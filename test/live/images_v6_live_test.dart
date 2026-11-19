// Live-проверка итерации 7.14 на реальных данных: две колоды («Статика»,
// «Биология»), настоящая сеть и живой DeepSeek.
//
// Запуск (ключ — только из окружения, значение не печатать):
//   $env:DEEPSEEK_API_KEY = <User scope>       (PowerShell, значение не выводить)
//   fvm flutter test test/live/images_v6_live_test.dart --tags live
//
// Тест пишет отчёт `journal/iteration-7.14/live-metrics.{md,json}`: доля
// настоящих картинок, заглушек и карточек без картинки, распределение по
// провайдерам, среднее время догрузки и таблицу «вопрос → запрос → провайдер»
// для ручной оценки уместности.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/images/image_providers.dart';
import 'package:cardflow/api/images/image_search_service.dart';
import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import 'support/live_test_config.dart';

import '../helpers/generation_fakes.dart';

void main() {
  final String? apiKey = _env('DEEPSEEK_API_KEY');
  final String baseUrl =
      _env('DEEPSEEK_BASE_URL') ?? 'https://api.deepseek.com';
  final String model = _env('DEEPSEEK_MODEL') ?? 'deepseek-flash';
  // TASK 04: без явного CARDFLOW_LIVE_TESTS=1 файл не делает запросов.
  final String? liveSkip = liveDetailedTestsSkipReason(
    apiKey: apiKey,
    keyVariable: 'DEEPSEEK_API_KEY',
  );

  test(
    'живые колоды «Статика» и «Биология»: картинки, провайдеры, время',
    () async {
      final Dio dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      addTearDown(() => dio.close(force: true));
      final List<String> diagnostics = <String>[];
      final GenerationDiagnostics diag = GenerationDiagnostics(
        enabled: true,
        sink: diagnostics.add,
      );

      final CardGenerationService service = CardGenerationService(
        adapters: <GenerationProviderAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          diagnostics: diag,
        ),
        maxOutputTokens: 8192,
        diagnostics: diag,
      );

      final List<DeckReport> reports = <DeckReport>[];
      for (final String topic in <String>['Статика', 'Биология']) {
        final _TimedFinder finder = _TimedFinder(
          ImageSearchService(
            dio: dio,
            providers: buildImageProviders(dio: dio),
            diagnostics: diag,
          ),
        );
        final GenerationPipeline pipeline = GenerationPipeline(
          caller: service,
          jobRepository: FakeGenerationJobRepository(),
          cardStore: FakeGenerationCardStore(),
          imageFinder: finder,
          placeholderGenerator: const PlaceholderImageGenerator(),
          diagnostics: diag,
        );
        final Stopwatch total = Stopwatch()..start();
        final GenerationRunResult result = await pipeline.run(
          GenerationRunRequest(
            documents: const <ParsedDocument>[],
            account: ProviderAccount(
              id: 'deepseek',
              label: 'DeepSeek',
              presetId: 'deepseek',
              protocol: ProviderProtocol.openaiCompletions,
              baseUrl: baseUrl,
              modelId: model,
              contextTokens: 128000,
              requiresApiKey: true,
            ),
            deckName: topic,
            wishes:
                'Тема: $topic. Сделай 18 карточек для интервального '
                'повторения, уровень учебника.',
          ),
        );
        total.stop();
        final DeckReport report = DeckReport.fromRun(
          topic: topic,
          cards: result.cards,
          searchCalls: finder.calls,
          runElapsed: total.elapsed,
          tokens: result.tokensUsed,
          imageDirectory: Directory(
            'journal/iteration-7.14/images/'
            '${topic == 'Статика' ? 'statics' : 'biology'}',
          ),
        );
        reports.add(report);
        if (result.cards.length < 15) {
          fail(
            'Колода «$topic»: ${result.cards.length} карточек (<15); '
            'нужен повторный прогон с большим лимитом',
          );
        }
      }

      final String outDir = 'journal/iteration-7.14';
      Directory(outDir).createSync(recursive: true);
      final Map<String, Object?> json = <String, Object?>{
        'prompt': systemPromptVersion,
        'model': model,
        'decks': <Object?>[for (final DeckReport r in reports) r.toJson()],
      };
      File('$outDir/live-metrics.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

      final StringBuffer markdown = StringBuffer()
        ..writeln('# Итерация 7.14 — метрики картинок (живой прогон)')
        ..writeln()
        ..writeln('- Промпт: `$systemPromptVersion`, модель: `$model`')
        ..writeln('- Дата: ${DateTime.now().toIso8601String()}')
        ..writeln();
      for (final DeckReport report in reports) {
        markdown
          ..writeln('## Колода «${report.topic}»')
          ..writeln()
          ..writeln('| Показатель | Значение |')
          ..writeln('|---|---|')
          ..writeln('| Карточек | ${report.total} |')
          ..writeln(
            '| Настоящих картинок | ${report.real} '
            '(${report.realShare.toStringAsFixed(1)} %) |',
          )
          ..writeln(
            '| Заглушек | ${report.placeholders} '
            '(${report.placeholderShare.toStringAsFixed(1)} %) |',
          )
          ..writeln('| Без картинки | ${report.missing} |')
          ..writeln(
            '| Среднее время догрузки | '
            '${report.averageSearchMs.toStringAsFixed(0)} мс |',
          )
          ..writeln('| Токены | ${report.tokens} |')
          ..writeln(
            '| Провайдеры | ${report.providers.entries.map((e) => '${e.key}: ${e.value}').join(', ')} |',
          )
          ..writeln()
          ..writeln(
            '| # | Вопрос (front) | image.query | kind | Провайдер | Тип |',
          )
          ..writeln('|---|---|---|---|---|---|');
        var index = 1;
        for (final CardReport card in report.cards) {
          markdown.writeln(
            '| ${index++} | ${_cell(card.front)} | ${_cell(card.query)} | '
            '${card.kind} | ${card.provider} | ${card.status} | '
            '${card.imagePath ?? '—'} |',
          );
        }
        markdown.writeln();
      }
      File('$outDir/live-metrics.md').writeAsStringSync(markdown.toString());

      for (final DeckReport report in reports) {
        // ignore: avoid_print — evidence прогона для отчёта.
        print(report.summary());
        for (final CardReport card in report.cards) {
          // ignore: avoid_print
          print(
            '${report.topic}: «${card.front}» → "${card.query}" '
            '[${card.kind}, ${card.provider}, ${card.status}] '
            '${card.imagePath ?? ''}',
          );
        }
      }
      // ignore: avoid_print
      print('Отчёт: $outDir/live-metrics.md');
      for (final String line in diagnostics.take(40)) {
        // ignore: avoid_print
        print('DIAG $line');
      }
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 25)),
    tags: <String>['live'],
  );
}

String? _env(String name) {
  final String? value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

String _cell(String value) =>
    value.replaceAll('|', '/').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Обёртка поиска с замером времени на карточку.
class _TimedFinder implements CardImageFinder {
  _TimedFinder(this.inner);

  final CardImageFinder inner;
  final List<({String query, Duration elapsed, GeneratedCardImage? image})>
  calls = <({String query, Duration elapsed, GeneratedCardImage? image})>[];

  @override
  Future<GeneratedCardImage?> findImage(
    String query, {
    String? fallbackQuery,
    GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
    Set<String>? excludedSourceUrls,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final GeneratedCardImage? image = await inner.findImage(
      query,
      fallbackQuery: fallbackQuery,
      kind: kind,
      excludedSourceUrls: excludedSourceUrls,
    );
    stopwatch.stop();
    calls.add((query: query, elapsed: stopwatch.elapsed, image: image));
    return image;
  }
}

/// Карточка отчёта.
class CardReport {
  const CardReport({
    required this.front,
    required this.query,
    required this.kind,
    required this.provider,
    required this.status,
    this.imagePath,
  });

  final String front;
  final String query;
  final String kind;
  final String provider;
  final String status;
  final String? imagePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'front': front,
    'query': query,
    'kind': kind,
    'provider': provider,
    'status': status,
    if (imagePath != null) 'imagePath': imagePath,
  };
}

/// Отчёт по одной колоде.
class DeckReport {
  DeckReport({
    required this.topic,
    required this.cards,
    required this.searchTimes,
    required this.runElapsed,
    required this.tokens,
  });

  factory DeckReport.fromRun({
    required String topic,
    required List<GeneratedCard> cards,
    required List<({String query, Duration elapsed, GeneratedCardImage? image})>
    searchCalls,
    required Duration runElapsed,
    required int tokens,
    required Directory imageDirectory,
  }) {
    final List<CardReport> reports = <CardReport>[];
    final List<int> times = <int>[];
    for (var index = 0; index < cards.length; index++) {
      final GeneratedCard card = cards[index];
      final GeneratedCardImage? image = card.image;
      final String status;
      if (image == null) {
        status = 'нет';
      } else if (image.isPlaceholder) {
        status = 'заглушка';
      } else {
        status = 'настоящая';
      }
      if (index < searchCalls.length) {
        times.add(searchCalls[index].elapsed.inMilliseconds);
      }
      String? imagePath;
      if (image != null && !image.isPlaceholder) {
        imageDirectory.createSync(recursive: true);
        final File file = File(
          '${imageDirectory.path}${Platform.pathSeparator}'
          '${(index + 1).toString().padLeft(2, '0')}.${image.fileExtension}',
        );
        file.writeAsBytesSync(image.bytes);
        imagePath = file.path;
      }
      reports.add(
        CardReport(
          front: card.front,
          query: image?.query ?? card.imageQuery ?? '',
          kind: (image?.kind ?? card.imageKind).wireName,
          provider: image?.provider ?? '—',
          status: status,
          imagePath: imagePath,
        ),
      );
    }
    return DeckReport(
      topic: topic,
      cards: reports,
      searchTimes: times,
      runElapsed: runElapsed,
      tokens: tokens,
    );
  }

  final String topic;
  final List<CardReport> cards;
  final List<int> searchTimes;
  final Duration runElapsed;
  final int tokens;

  int get total => cards.length;
  int get real => cards.where((c) => c.status == 'настоящая').length;
  int get placeholders => cards.where((c) => c.status == 'заглушка').length;
  int get missing => cards.where((c) => c.status == 'нет').length;
  double get realShare => total == 0 ? 0 : real * 100 / total;
  double get placeholderShare => total == 0 ? 0 : placeholders * 100 / total;
  double get averageSearchMs => searchTimes.isEmpty
      ? 0
      : searchTimes.reduce((a, b) => a + b) / searchTimes.length;
  Map<String, int> get providers {
    final Map<String, int> result = <String, int>{};
    for (final CardReport card in cards) {
      if (card.status != 'настоящая') continue;
      result[card.provider] = (result[card.provider] ?? 0) + 1;
    }
    return result;
  }

  String summary() =>
      'DECK $topic: cards=$total, real=$real '
      '(${realShare.toStringAsFixed(1)} %), placeholders=$placeholders '
      '(${placeholderShare.toStringAsFixed(1)} %), missing=$missing, '
      'avg=${averageSearchMs.toStringAsFixed(0)} мс, run=${runElapsed.inSeconds} с, '
      'providers=$providers, tokens=$tokens';

  Map<String, Object?> toJson() => <String, Object?>{
    'topic': topic,
    'total': total,
    'real': real,
    'realShare': _round(realShare),
    'placeholders': placeholders,
    'placeholderShare': _round(placeholderShare),
    'missing': missing,
    'averageSearchMs': _round(averageSearchMs),
    'runSeconds': runElapsed.inSeconds,
    'providers': providers,
    'tokens': tokens,
    'cards': <Object?>[for (final CardReport card in cards) card.toJson()],
  };

  static double _round(double value) => double.parse(value.toStringAsFixed(1));
}
