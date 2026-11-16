import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../motion.dart';
import '../nc_theme.dart';
import '../motion_scope.dart';
import '../tokens/nc_colors.dart';

/// Тон фона Aurora: золотой (каталог) или Iris (генерация, §4.5).
enum NcAmbientTone {
  /// Тёплый фон каталога: золото + Iris + glacier.
  aurum,

  /// Фон «AI-студии»: доминирует Iris.
  iris,
}

/// Фон приложения «Aurora» с зерном (REDESIGN-SPEC §4.5, ADR-035).
///
/// Нижний слой оболочки и сессий: `ink0` + три больших радиальных градиента
/// (`aurum` 9 %, `iris` 8 %, `glacier` 5 %). Рисуется `CustomPainter` (не
/// `BackdropFilter`), лежит в `RepaintBoundary`, не перехватывает указатель и
/// не участвует в семантике.
///
/// Дрейф пятен по Лиссажу включён только в выразительном режиме: фон статичен
/// при «Стандартной анимации», `MediaQuery.disableAnimations`, повышенном
/// контрасте и **в `flutter test`** (иначе ни один `pumpAndSettle` не
/// завершится — спайк 1.0 §S6). Дрейф в тесте включается
/// [debugAnimateInTests].
class NcAmbientBackground extends StatefulWidget {
  /// Создаёт фон Aurora.
  const NcAmbientBackground({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.tone = NcAmbientTone.aurum,
  });

  /// Контент приложения поверх фона.
  final Widget child;

  /// Яркость пятен: 1.0 — каталог, 0.45 — сессии (§4.5).
  final double intensity;

  /// Тон: `aurum` (каталог) или `iris` (генерация).
  final NcAmbientTone tone;

  /// Разрешает дрейф под `flutter test` (для отдельного widget-теста).
  static bool debugAnimateInTests = false;

  @override
  State<NcAmbientBackground> createState() => NcAmbientBackgroundState();
}

/// Состояние фона Aurora (публично для тестов).
class NcAmbientBackgroundState extends State<NcAmbientBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.ambient,
  );

  ui.Image? _grain;
  bool _grainRequested = false;
  bool _animate = false;
  bool _auroraEnabled = true;
  double _lastProgress = 0.35;

  /// Дрейфует ли фон прямо сейчас.
  bool get isAnimating => _animate && _controller.isAnimating;

  /// Включены ли пятна Aurora (выключены при повышенном контрасте).
  bool get auroraEnabled => _auroraEnabled;

  /// Загружено ли зерно (иначе фон рисуется без него).
  bool get hasGrain => _grain != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final NcTheme theme = NcTheme.of(context);
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _auroraEnabled = !theme.highContrast && widget.intensity > 0;
    final bool shouldAnimate =
        _auroraEnabled &&
        NcMotion.of(context).ambientDrift &&
        !reduceMotion &&
        (!_runningInFlutterTest || NcAmbientBackground.debugAnimateInTests);
    if (shouldAnimate != _animate) {
      _animate = shouldAnimate;
      if (shouldAnimate) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
    _requestGrain();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_animate) return;
    if (state == AppLifecycleState.resumed) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _grain?.dispose();
    super.dispose();
  }

  Future<void> _requestGrain() async {
    if (_grainRequested) return;
    _grainRequested = true;
    try {
      final ByteData data = await rootBundle.load('assets/textures/grain.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _grain = frame.image);
    } catch (_) {
      // Бандл без текстуры — фон остаётся без зерна (не ошибка старта).
    }
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final double grainOpacity = theme.highContrast ? 0 : 0.9;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        RepaintBoundary(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  final double progress = _animate
                      ? _controller.value
                      : _lastProgress;
                  _lastProgress = progress;
                  return CustomPaint(
                    painter: NcAmbientPainter(
                      colors: theme.colors,
                      progress: progress,
                      auroraEnabled: _auroraEnabled,
                      intensity: widget.intensity,
                      tone: widget.tone,
                      grain: _grain,
                      grainOpacity: grainOpacity,
                    ),
                    isComplex: true,
                    willChange: _animate,
                  );
                },
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Painter фона Aurora + зерна (REDESIGN-SPEC §4.5).
class NcAmbientPainter extends CustomPainter {
  /// Создаёт painter.
  const NcAmbientPainter({
    required this.colors,
    required this.progress,
    required this.auroraEnabled,
    required this.intensity,
    required this.tone,
    required this.grain,
    required this.grainOpacity,
  });

  /// Палитра темы.
  final NcColors colors;

  /// Фаза дрейфа 0…1 (постоянна, если анимация выключена).
  final double progress;

  /// Рисовать ли пятна (ложно при повышенном контрасте).
  final bool auroraEnabled;

  /// Яркость пятен.
  final double intensity;

  /// Тон пятен.
  final NcAmbientTone tone;

  /// Тайл зерна (может быть null до загрузки).
  final ui.Image? grain;

  /// Непрозрачность зерна (0 при повышенном контрасте).
  final double grainOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = colors.ink0);
    if (auroraEnabled) {
      _paintAurora(canvas, size);
    }
    final ui.Image? grainImage = grain;
    if (grainImage != null && grainOpacity > 0) {
      final Paint paint = Paint()
        ..shader = ui.ImageShader(
          grainImage,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..color = NcColors.white.withValues(alpha: grainOpacity);
      canvas.drawRect(rect, paint);
    }
  }

  void _paintAurora(Canvas canvas, Size size) {
    final bool irisTone = tone == NcAmbientTone.iris;
    final List<(Color, double, double, double)> spots =
        <(Color, double, double, double)>[
          (colors.auroraAurum, irisTone ? 0.55 : 1.0, 0.0, 0.78),
          (colors.auroraIris, irisTone ? 1.9 : 1.0, 2.1, 0.72),
          (colors.auroraGlacier, 1.0, 4.3, 0.62),
        ];
    for (final (Color color, double weight, double phase, double scale)
        in spots) {
      final Offset center = _driftCenter(size, phase);
      final double radius = size.width * scale;
      final double alpha = (color.a * weight * intensity).clamp(0.0, 1.0);
      if (alpha <= 0) continue;
      final Paint paint = Paint()
        ..shader = ui.Gradient.radial(center, radius, <Color>[
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ]);
      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  /// Позиция пятна по Лиссажу: медленный дрейф вокруг центра.
  Offset _driftCenter(Size size, double phase) {
    final double t = progress * 2 * math.pi;
    return Offset(
      size.width * (0.5 + 0.20 * math.sin(t + phase)),
      size.height * (0.5 + 0.16 * math.cos(t * 1.3 + phase)),
    );
  }

  @override
  bool shouldRepaint(NcAmbientPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.colors != colors ||
      oldDelegate.auroraEnabled != auroraEnabled ||
      oldDelegate.intensity != intensity ||
      oldDelegate.tone != tone ||
      oldDelegate.grain != grain ||
      oldDelegate.grainOpacity != grainOpacity;
}

/// true, если код исполняется под `flutter test` (`flutter_tester` выставляет
/// `FLUTTER_TEST=true`) — тогда глобальная повторяющаяся анимация выключена.
final bool _runningInFlutterTest =
    Platform.environment['FLUTTER_TEST'] == 'true';
