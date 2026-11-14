/// Отмена генерации для UI (ADR-015).
///
/// UI не импортирует Dio напрямую: обёртка владеет `CancelToken` и передаёт
/// его в `GenerationCaller`.
library;

import 'package:dio/dio.dart';

/// Управляемая отмена текущей генерации.
class GenerationCancellation {
  /// Создаёт отмену.
  GenerationCancellation();

  final CancelToken _token = CancelToken();

  /// Токен для передачи в транспорт.
  CancelToken get token => _token;

  /// Отменена ли генерация.
  bool get isCancelled => _token.isCancelled;

  /// Отменяет текущий запрос (идемпотентно).
  void cancel() {
    if (!_token.isCancelled) {
      _token.cancel();
    }
  }
}
