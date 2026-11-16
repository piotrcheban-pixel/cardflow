import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../haptics.dart';
import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'nc_glass.dart';

/// Тон тоста Nocturne (REDESIGN-SPEC §8).
enum NcToastTone {
  /// Нейтральное сообщение.
  neutral,

  /// Информация (glacier).
  info,

  /// Успех (jade).
  success,

  /// Ошибка (ember): тактильный `heavyImpact` (§7).
  error,
}

/// Тост `glass.thin`, pill, внизу над доком: иконка статуса, действие
/// («Отменить» — текст `aurum`), полоса оставшегося времени 2 px (§8).
///
/// Заменяет `SnackBar`/`M3ESnackbar` через `showAppMessage` и
/// `showArchivedUndoSnackbar` (сигнатуры прежние). Тост не перехватывает
/// указатель, кроме кнопки действия, поэтому не блокирует экран.
class NcToast extends StatefulWidget {
  /// Создаёт тост.
  const NcToast({
    super.key,
    required this.message,
    this.tone = NcToastTone.neutral,
    this.actionLabel,
    this.onAction,
    this.onClosed,
    this.duration = const Duration(seconds: 4),
    this.semanticLabel,
  });

  /// Текст сообщения (ARB).
  final String message;

  /// Тон и иконка статуса.
  final NcToastTone tone;

  /// Подпись действия (ARB, например «Отменить»).
  final String? actionLabel;

  /// Действие по нажатию на подпись.
  final VoidCallback? onAction;

  /// Тост скрыт (таймер или действие).
  final VoidCallback? onClosed;

  /// Время показа.
  final Duration duration;

  /// Текст семантики (по умолчанию [message]).
  final String? semanticLabel;

  /// Высота полосы оставшегося времени.
  static const double progressHeight = 2;

  /// Период обновления полосы.
  static const Duration tick = Duration(milliseconds: 200);

  @override
  State<NcToast> createState() => _NcToastState();
}

class _NcToastState extends State<NcToast> {
  final ValueNotifier<double> _remaining = ValueNotifier<double>(1);
  Timer? _ticker;
  Timer? _closer;

  @override
  void initState() {
    super.initState();
    final int ticks =
        (widget.duration.inMilliseconds / NcToast.tick.inMilliseconds).ceil();
    var elapsed = 0;
    _ticker = Timer.periodic(NcToast.tick, (Timer timer) {
      elapsed++;
      _remaining.value = (1 - elapsed / (ticks == 0 ? 1 : ticks)).clamp(
        0.0,
        1.0,
      );
    });
    _closer = Timer(widget.duration, _close);
  }

  void _close() {
    if (!mounted) return;
    widget.onClosed?.call();
  }

  void _action() {
    widget.onAction?.call();
    _close();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _closer?.cancel();
    _remaining.dispose();
    super.dispose();
  }

  (IconData?, Color) _toneVisual(NcTheme theme) => switch (widget.tone) {
    NcToastTone.neutral => (null, theme.colors.textPrimary),
    NcToastTone.info => (Icons.info_outline_rounded, theme.colors.glacier),
    NcToastTone.success => (
      Icons.check_circle_outline_rounded,
      theme.colors.jade,
    ),
    NcToastTone.error => (Icons.error_outline_rounded, theme.colors.ember),
  };

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final (IconData? icon, Color toneColor) = _toneVisual(theme);
    final bool hasAction = widget.actionLabel != null;
    final Widget body = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 20, color: toneColor),
          const SizedBox(width: NcSpace.s8),
        ],
        Flexible(
          child: Text(
            widget.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.bodyM.copyWith(
              color: theme.colors.textPrimary,
            ),
          ),
        ),
        if (hasAction)
          const SizedBox(width: _actionReserve, height: NcSpace.s24),
      ],
    );

    final Widget pill = NcGlass(
      tier: NcGlassTier.thin,
      radius: NcRadii.pill,
      showNoise: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NcSpace.s16,
              NcSpace.s8,
              NcSpace.s16,
              NcSpace.s8,
            ),
            child: body,
          ),
          SizedBox(
            height: NcToast.progressHeight,
            child: ValueListenableBuilder<double>(
              valueListenable: _remaining,
              builder: (BuildContext context, double value, Widget? child) =>
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value,
                      child: ColoredBox(color: toneColor),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );

    // Всё оформление тоста пропускает указатель (тост не блокирует экран);
    // интерактивна только кнопка действия.
    final Widget content = Stack(
      children: <Widget>[
        IgnorePointer(child: pill),
        if (hasAction)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: NcSpace.s4),
                child: NcTappable(
                  onTap: _action,
                  semanticLabel: widget.actionLabel,
                  focusRadius: NcRadii.s,
                  haptic: null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NcSpace.s12,
                      vertical: NcSpace.s8,
                    ),
                    child: Text(
                      widget.actionLabel!,
                      style: theme.typography.labelL.copyWith(
                        color: theme.colors.aurum,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      liveRegion: true,
      label: widget.semanticLabel ?? widget.message,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        curve: const Cubic(0.2, 0, 0, 1),
        builder: (BuildContext context, double value, Widget? child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        ),
        child: content,
      ),
    );
  }

  /// Место под кнопку действия, чтобы текст не заезжал под неё.
  static const double _actionReserve = 84;
}

OverlayEntry? _activeToast;

/// Показывает тост поверх приложения (ровно один на экран).
///
/// [bottomMargin] — отступ от нижней безопасной зоны (по умолчанию 24; экраны
/// с доком передают больше).
void showNcToast(
  BuildContext context, {
  required String message,
  NcToastTone tone = NcToastTone.neutral,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
  double bottomMargin = 24,
  String? semanticLabel,
}) {
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final MediaQueryData media = MediaQuery.of(context);
  if (tone == NcToastTone.error) NcHaptics.of(context).error();
  _activeToast?.remove();
  late final OverlayEntry entry;
  void close() {
    if (identical(_activeToast, entry)) _activeToast = null;
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (BuildContext overlayContext) => Positioned(
      left: NcSpace.s16 + media.padding.left,
      right: NcSpace.s16 + media.padding.right,
      bottom: bottomMargin + media.padding.bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: NcSpace.maxListWidth),
          child: NcToast(
            message: message,
            tone: tone,
            actionLabel: actionLabel,
            onAction: onAction,
            onClosed: close,
            duration: duration,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

/// Скрывает активный тост (например, при уходе с экрана).
void dismissNcToast() {
  _activeToast?.remove();
  _activeToast = null;
}
