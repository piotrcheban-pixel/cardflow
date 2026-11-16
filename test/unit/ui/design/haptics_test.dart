import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/haptics.dart';

/// `NcHaptics` — единая точка тактильного отклика (REDESIGN-SPEC §7).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> vibrations;

  setUp(() {
    vibrations = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') {
            vibrations.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('NcHaptics: события §7', () {
    test('flip/reveal — selectionClick', () async {
      final NcHaptics haptics = NcHaptics();
      haptics.flip();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations, <String>['HapticFeedbackType.selectionClick']);
    });

    test(
      'rating по оценке: Again — heavy, Hard/Good — light, Easy — select',
      () async {
        final NcHaptics haptics = NcHaptics(clock: _StepClock().call);
        haptics.rating(NcHapticKind.heavyImpact);
        await Future<void>.delayed(Duration.zero);
        expect(vibrations, <String>['HapticFeedbackType.heavyImpact']);
      },
    );

    test(
      'error — heavyImpact, menu — mediumImpact, threshold — light',
      () async {
        final _StepClock clock = _StepClock();
        final NcHaptics haptics = NcHaptics(clock: clock.call);
        haptics.error();
        clock.advance(const Duration(milliseconds: 50));
        haptics.menu();
        clock.advance(const Duration(milliseconds: 50));
        haptics.threshold();
        await Future<void>.delayed(Duration.zero);
        expect(vibrations, <String>[
          'HapticFeedbackType.heavyImpact',
          'HapticFeedbackType.mediumImpact',
          'HapticFeedbackType.lightImpact',
        ]);
      },
    );
  });

  group('NcHaptics: ограничение частоты 40 мс', () {
    test('второй вызов в пределах 40 мс не вибрирует', () async {
      final _StepClock clock = _StepClock();
      final NcHaptics haptics = NcHaptics(clock: clock.call);
      // Разные события: одинаковые гасятся окном повтора (§7).
      haptics.selectionClick();
      clock.advance(const Duration(milliseconds: 20));
      haptics.lightImpact();
      clock.advance(const Duration(milliseconds: 21));
      haptics.mediumImpact();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations, hasLength(2));
    });

    test('одинаковое событие гасится в окне повтора', () async {
      final _StepClock clock = _StepClock();
      final NcHaptics haptics = NcHaptics(clock: clock.call);
      haptics.lightImpact();
      clock.advance(const Duration(milliseconds: 60));
      haptics.lightImpact();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations, hasLength(1));

      clock.advance(const Duration(milliseconds: 250));
      haptics.lightImpact();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations, hasLength(2));
    });

    test('разные события в пределах 40 мс — только первое', () async {
      final _StepClock clock = _StepClock();
      final NcHaptics haptics = NcHaptics(clock: clock.call);
      haptics.lightImpact();
      clock.advance(const Duration(milliseconds: 5));
      haptics.mediumImpact();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations, <String>['HapticFeedbackType.lightImpact']);
    });
  });

  group('NcHaptics: настройка и завершение сессии', () {
    test('enabled = false — вибраций нет', () async {
      final NcHaptics haptics = NcHaptics(enabled: false);
      haptics.flip();
      haptics.error();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations, isEmpty);
    });

    test('выключение на лету', () async {
      final NcHaptics haptics = NcHaptics(clock: _StepClock().call);
      haptics.enabled = false;
      haptics.flip();
      await Future<void>.delayed(Duration.zero);
      expect(vibrations, isEmpty);
    });

    testWidgets('success: mediumImpact → 110 мс → lightImpact', (tester) async {
      final _StepClock clock = _StepClock();
      final NcHaptics haptics = NcHaptics(clock: clock.call);
      haptics.success();
      await tester.pump();
      expect(vibrations, <String>['HapticFeedbackType.mediumImpact']);
      clock.advance(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 110));
      expect(vibrations, <String>[
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    });
  });

  group('NcHapticsScope: доступ из дерева', () {
    testWidgets('of() возвращает scope, без scope — выключенное', (
      tester,
    ) async {
      final NcHaptics scoped = NcHaptics();
      late NcHaptics resolved;
      await tester.pumpWidget(
        NcHapticsScope(
          haptics: scoped,
          child: Builder(
            builder: (BuildContext context) {
              resolved = NcHaptics.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, same(scoped));

      late NcHaptics withoutScope;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            withoutScope = NcHaptics.of(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(withoutScope.enabled, isFalse);
      withoutScope.flip();
      await tester.pump();
      expect(vibrations, isEmpty);
    });
  });
}

/// Часы, которые двигаются только по команде теста.
class _StepClock {
  DateTime _now = DateTime.utc(2026, 11, 17, 12);

  DateTime call() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}
