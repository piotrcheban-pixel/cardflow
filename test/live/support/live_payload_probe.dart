/// Наблюдатель формы запроса в живом замере среза 17B (TASK часть 1, п. 3).
///
/// Пишет **только числа**: размер тела в байтах и наличие/число маркеров
/// контекста `<already_created>`. Тексты материалов, карточек и промптов в
/// отчёт не попадают (протокол §10), заголовки и ключи не читаются.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';

/// Форма одного HTTP-запроса: размер и маркеры контекста.
class LiveRequestShape {
  /// Создаёт запись формы.
  const LiveRequestShape({
    required this.bytes,
    required this.alreadyCreated,
    required this.statements,
    required this.takenUnits,
    required this.alreadyAccepted,
  });

  /// Байты тела запроса (UTF-8 JSON).
  final int bytes;

  /// Сколько раз в теле встречается маркер `<already_created>`.
  final int alreadyCreated;

  /// Сколько строк `<statement unit_id="…">` в теле.
  final int statements;

  /// Есть ли перечень занятых единиц `<taken units="…"/>`.
  final bool takenUnits;

  /// Сколько блоков `<already_accepted>` в теле.
  final int alreadyAccepted;

  /// Запись в `run.json` (без текстов).
  Map<String, Object?> toJson() => <String, Object?>{
    'bytes': bytes,
    'already_created': alreadyCreated,
    'statements': statements,
    'taken_units': takenUnits,
    'already_accepted': alreadyAccepted,
  };
}

/// Транспорт-обёртка: считает форму запроса и передаёт его дальше.
class LivePayloadProbe implements GenerationTransport {
  /// Оборачивает [inner].
  LivePayloadProbe({required this.inner});

  /// Настоящий транспорт.
  final GenerationTransport inner;

  /// Все запросы в порядке отправки.
  final List<LiveRequestShape> requests = <LiveRequestShape>[];

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    final String body = jsonEncode(request.body);
    requests.add(
      LiveRequestShape(
        bytes: utf8.encode(body).length,
        alreadyCreated: '<already_created>'.allMatches(body).length,
        statements: '<statement unit_id='.allMatches(body).length,
        takenUnits: body.contains('<taken units='),
        alreadyAccepted: '<already_accepted>'.allMatches(body).length,
      ),
    );
    return inner.postJson(request, cancelToken: cancelToken);
  }
}
