import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/ui/state/settings_diagnostics.dart';

/// Owner-note 1.0.1 (ADR-047): экран настроек показывал только строку ARB, и
/// причину отказа записи нельзя было увидеть. Диагностика пишет её в debug-лог.
void main() {
  late List<String> messages;

  setUp(() => messages = <String>[]);

  SettingsDiagnostics diagnostics({bool enabled = true}) {
    return SettingsDiagnostics(enabled: enabled, sink: messages.add);
  }

  test('пишет тип исключения и текст причины', () {
    diagnostics().saveFailed(
      StateError('drift: attempt to write a readonly database'),
      StackTrace.current,
    );

    expect(messages, isNotEmpty);
    expect(messages.first, contains('StateError'));
    expect(messages.first, contains('readonly'));
    expect(messages.first, startsWith('Настройки не записаны'));
  });

  test('добавляет первые кадры стека (слой-первопричина)', () {
    final StackTrace stack = StackTrace.fromString(
      List<String>.generate(
        20,
        (int index) => '#$index frame $index',
      ).join('\n'),
    );

    diagnostics().saveFailed(Exception('boom'), stack);

    expect(messages.length, 2, reason: 'Причина и стек — отдельные строки');
    expect(messages.last, contains('Стек (8)'));
    expect(messages.last, contains('frame 0'));
    expect(messages.last, isNot(contains('frame 8')));
  });

  test('release (enabled: false) ничего не пишет', () {
    diagnostics(enabled: false).saveFailed(Exception('boom'), StackTrace.empty);

    expect(messages, isEmpty);
  });

  test('одна строка без переводов строк и без обрезки адресов', () {
    diagnostics().saveFailed(
      Exception('line1\nline2\tline3'),
      StackTrace.empty,
    );

    expect(messages, hasLength(1));
    expect(messages.single, isNot(contains('\n')));
    expect(messages.single, contains('line1'));
  });

  test('длинный текст обрезается по лимиту', () {
    final String long = 'x' * (kSettingsDiagnosticsMaxLength * 2);

    final String message = settingsDiagnosticText(long);

    expect(message.length, kSettingsDiagnosticsMaxLength + 1);
    expect(message, endsWith('…'));
  });

  test('settingsDiagnosticText схлопывает управляющие символы', () {
    expect(settingsDiagnosticText('a\u0000b\n c\r\nd   e'), 'a b c d e');
  });
}
