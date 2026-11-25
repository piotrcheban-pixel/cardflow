/// Debug-диагностика записи пользовательских настроек (owner-note 1.0.1).
///
/// Владелец после установки релиза видел «Не удалось сохранить настройки.
/// Попробуйте ещё раз» без причины: экран настроек показывал только строку из
/// ARB и проглатывал исключение. Чтобы точная причина (JSON, блокировка БД,
/// закрытый исполнитель drift) была видна в `flutter run`, контроллер пишет её
/// в этот приёмник.
///
/// Контракт безопасности: наружу (в UI) по-прежнему попадает только строка из
/// ARB; диагностика работает только в debug/профиле (`enabled = false` в
/// release), секреты не пишутся — в настройках их нет.
library;

import 'dart:developer' as developer;

/// Включена ли диагностика по умолчанию (в release — нет).
const bool kSettingsDiagnosticsEnabled = !bool.fromEnvironment(
  'dart.vm.product',
);

/// Максимальная длина одного диагностического сообщения.
const int kSettingsDiagnosticsMaxLength = 2000;

/// Приёмник диагностических строк.
typedef SettingsDiagnosticsSink = void Function(String message);

/// Редактирует и обрезает диагностический текст.
///
/// Управляющие символы и переводы строк схлопываются в пробелы, чтобы запись
/// оставалась одной строкой лога; длина ограничена.
String settingsDiagnosticText(
  String text, {
  int maxLength = kSettingsDiagnosticsMaxLength,
}) {
  final String value = text
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}…';
}

/// Диагностика записи настроек (debug-only).
class SettingsDiagnostics {
  /// Создаёт диагностику.
  const SettingsDiagnostics({
    this.enabled = kSettingsDiagnosticsEnabled,
    this.sink,
  });

  /// Включена ли запись (в release всегда `false`).
  final bool enabled;

  /// Приёмник сообщений; `null` — `dart:developer.log`.
  final SettingsDiagnosticsSink? sink;

  /// Причина и стек падения записи `app.settings`.
  void saveFailed(Object error, StackTrace stackTrace) {
    if (!enabled) return;
    final String message =
        'Настройки не записаны: ${error.runtimeType}: '
        '${settingsDiagnosticText(error.toString())}';
    _emit(message);
    // Первые кадры стека дают слой-первопричину (drift/isolate/БД), не только
    // место вызова save().
    final List<String> frames = stackTrace
        .toString()
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .take(8)
        .toList(growable: false);
    if (frames.isEmpty) return;
    _emit('Стек (${frames.length}): ${frames.join(' | ')}');
  }

  void _emit(String message) {
    final SettingsDiagnosticsSink? target = sink;
    if (target != null) {
      target(settingsDiagnosticText(message));
      return;
    }
    developer.log(settingsDiagnosticText(message), name: 'cardflow.settings');
  }
}
