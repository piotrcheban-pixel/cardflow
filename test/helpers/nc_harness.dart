import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Стенд для тестов компонентов Nocturne (REDESIGN-SPEC §8, §10).
///
/// Даёт всё, от чего зависит компонент: `ThemeData` из `AppTheme` (обе темы и
/// повышенный контраст), `NcMotionScope` с выбранным режимом движения,
/// `NcHapticsScope` с записывающим откликом, локаль `ru` и `textScaler`.
/// Компонент не читает Riverpod/настройки — значения приходят сверху
/// (ADR-035), поэтому стенд не поднимает ни провайдеров, ни БД.

/// Локализация для проверок текста из ARB — без накачки дерева.
AppLocalizations get ncL10n => lookupAppLocalizations(const Locale('ru'));

/// Записывает вызовы `HapticFeedback` (канал `SystemChannels.platform`).
///
/// Компоненты обязаны идти через `NcHaptics` (§7), поэтому её отклик виден
/// здесь как `HapticFeedback.vibrate` с аргументом `HapticFeedbackType.*`.
class NcHapticRecorder {
  /// Создаёт рекордер; [install] подменяет обработчик платформенного канала.
  NcHapticRecorder();

  /// Записанные вызовы `HapticFeedback.vibrate`.
  final List<String> vibrations = <String>[];

  TestDefaultBinaryMessenger? _messenger;
  DateTime _now = DateTime.utc(2026, 11, 17, 12);

  /// Часы для `NcHaptics`: каждый вызов двигает время на секунду, чтобы
  /// ограничение частоты (40 мс) и окно повтора (200 мс) не гасили отклики
  /// в тесте, где действия идут друг за другом.
  DateTime clock() {
    _now = _now.add(const Duration(seconds: 1));
    return _now;
  }

  /// Подменяет обработчик канала на время теста.
  void install() {
    _messenger = TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger;
    _messenger!.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'HapticFeedback.vibrate') {
        vibrations.add('${call.arguments}');
      }
      return null;
    });
  }

  /// Снимает обработчик канала.
  void uninstall() {
    _messenger?.setMockMethodCallHandler(SystemChannels.platform, null);
    _messenger = null;
  }

  /// Сколько откликов записано.
  int get count => vibrations.length;
}

/// Оформление и режимы одного прогона компонента.
@immutable
class NcTestConfig {
  /// Создаёт конфигурацию стенда.
  const NcTestConfig({
    this.brightness = Brightness.dark,
    this.highContrast = false,
    this.textScale = 1,
    this.motion = NcMotionPreference.expressive,
    this.reduceMotion = false,
    this.size = const Size(420, 720),
    this.hapticsEnabled = true,
  });

  /// Светлая тема Porcelain либо тёмная Nocturne.
  final Brightness brightness;

  /// Повышенный контраст (§1.4).
  final bool highContrast;

  /// Пользовательский масштаб текста (§10: до 2,0).
  final double textScale;

  /// Режим движения (§6.4).
  final NcMotionPreference motion;

  /// Системное «уменьшить движение».
  final bool reduceMotion;

  /// Размер окна теста (логические px).
  final Size size;

  /// Включён ли тактильный отклик (настройка пользователя).
  final bool hapticsEnabled;

  /// Копия с заменой полей.
  NcTestConfig copyWith({
    Brightness? brightness,
    bool? highContrast,
    double? textScale,
    NcMotionPreference? motion,
    bool? reduceMotion,
    Size? size,
    bool? hapticsEnabled,
  }) => NcTestConfig(
    brightness: brightness ?? this.brightness,
    highContrast: highContrast ?? this.highContrast,
    textScale: textScale ?? this.textScale,
    motion: motion ?? this.motion,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    size: size ?? this.size,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
  );
}

/// Приложение-стенд вокруг одного компонента.
Widget ncApp({
  required Widget child,
  NcTestConfig config = const NcTestConfig(),
  NcHaptics? haptics,
}) {
  final ThemeData theme = config.brightness == Brightness.dark
      ? AppTheme.dark(highContrast: config.highContrast)
      : AppTheme.light(highContrast: config.highContrast);
  final NcHaptics actualHaptics =
      haptics ?? NcHaptics(enabled: config.hapticsEnabled);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: theme,
    builder: (BuildContext context, Widget? appChild) {
      return NcHapticsScope(
        haptics: actualHaptics,
        child: NcMotionScope(
          motion: NcMotion.resolve(
            preference: config.motion,
            disableAnimations: config.reduceMotion,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(config.textScale),
            ),
            child: appChild!,
          ),
        ),
      );
    },
    home: Builder(
      builder: (BuildContext context) => ColoredBox(
        color: NcTheme.of(context).colors.ink0,
        child: Center(child: child),
      ),
    ),
  );
}

/// Монтирует [child] на стенде и (по умолчанию) ждёт завершения анимаций.
Future<void> pumpNc(
  WidgetTester tester,
  Widget child, {
  NcTestConfig config = const NcTestConfig(),
  NcHaptics? haptics,
  bool settle = false,
}) async {
  tester.view.physicalSize = config.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ncApp(child: child, config: config, haptics: haptics));
  if (settle) await tester.pumpAndSettle();
}

/// Монтирует компонент при `textScale` 2,0 и проверяет отсутствие overflow.
Future<void> pumpNcAtTextScale2(
  WidgetTester tester,
  Widget child, {
  NcTestConfig config = const NcTestConfig(),
}) async {
  await pumpNc(
    tester,
    child,
    config: config.copyWith(textScale: 2, size: config.size),
    settle: true,
  );
  expect(
    tester.takeException(),
    isNull,
    reason: 'textScale 2,0 не должен давать overflow (REDESIGN-SPEC §10)',
  );
}

/// Масштаб `NcPressScale` (первый `Transform` под [root]).
double pressScaleOf(WidgetTester tester, Finder root) {
  final Finder transform = find
      .descendant(of: root, matching: find.byType(Transform))
      .first;
  final Transform widget = tester.widget<Transform>(transform);
  return widget.transform.storage[0];
}

/// Проверяет, что значения анимации не выходят за пределы отрезка
/// `[min, max]` — «Standard motion без overshoot» (§6.4).
///
/// Допуск [tolerance] — доля диапазона: пружина `standard` (ratio 0,9)
/// теоретически перелетает на 0,15 %, визуально это ноль.
void expectNoOvershoot(
  Iterable<double> samples, {
  required double min,
  required double max,
  double tolerance = 0.01,
}) {
  final List<double> values = samples.toList();
  expect(values, isNotEmpty, reason: 'Нет сэмплов анимации');
  final double range = (max - min).abs();
  final double slack = range == 0 ? 0 : range * tolerance;
  for (final double value in values) {
    expect(
      value,
      inInclusiveRange(min - slack, max + slack),
      reason:
          'Overshoot: $value вне [$min, $max] (допуск $slack): '
          '${values.map((double v) => v.toStringAsFixed(4)).join(', ')}',
    );
  }
}
