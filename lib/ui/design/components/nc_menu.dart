import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../motion.dart';

import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'nc_glass.dart';

/// Пункт меню Nocturne (REDESIGN-SPEC §8).
@immutable
class NcMenuItem<T> {
  /// Создаёт пункт меню.
  const NcMenuItem({
    required this.label,
    this.icon,
    this.value,
    this.onSelected,
    this.destructive = false,
    this.enabled = true,
    this.key,
    this.trailing,
    this.dividerBefore = false,
  });

  /// Текст пункта (из ARB).
  final String label;

  /// Иконка слева.
  final IconData? icon;

  /// Значение, возвращаемое [showNcMenu].
  final T? value;

  /// Действие пункта (альтернатива [value]).
  final VoidCallback? onSelected;

  /// Деструктивный пункт — `ember` (§8).
  final bool destructive;

  /// Доступен ли пункт.
  final bool enabled;

  /// Ключ пункта (контракт §9).
  final Key? key;

  /// Хвостовая подпись (значение настройки).
  final String? trailing;

  /// Нарисовать разделитель над пунктом.
  final bool dividerBefore;
}

/// Меню Nocturne: `glass.thick`, `r.l`, строки 48 px, иконка + текст,
/// деструктивный пункт — `ember`, разделители (§8). Появление — scale
/// 0,94→1 от точки вызова.
class NcMenu<T> extends StatefulWidget {
  /// Создаёт меню.
  const NcMenu({
    super.key,
    required this.items,
    this.minWidth = 200,
    this.maxWidth = 320,
    this.onDismiss,
    this.onItemSelected,
    this.autofocusFirst = true,
  });

  /// Пункты.
  final List<NcMenuItem<T>> items;

  /// Минимальная ширина.
  final double minWidth;

  /// Максимальная ширина.
  final double maxWidth;

  /// Закрыть меню (Escape, выбор).
  final VoidCallback? onDismiss;

  /// Выбор пункта (меню-хост использует для возврата значения).
  final ValueChanged<NcMenuItem<T>>? onItemSelected;

  /// Поставить фокус на первый пункт при открытии.
  final bool autofocusFirst;

  @override
  State<NcMenu<T>> createState() => _NcMenuState<T>();
}

class _NcMenuState<T> extends State<NcMenu<T>> {
  void _select(NcMenuItem<T> item) {
    item.onSelected?.call();
    widget.onItemSelected?.call(item);
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final List<Widget> rows = <Widget>[];
    for (var index = 0; index < widget.items.length; index++) {
      final NcMenuItem<T> item = widget.items[index];
      if (item.dividerBefore && index > 0) {
        rows.add(
          Divider(height: 1, thickness: 1, color: theme.colors.hairline),
        );
      }
      final Color color = !item.enabled
          ? theme.colors.textDisabled
          : item.destructive
          ? theme.colors.ember
          : theme.colors.textPrimary;
      rows.add(
        SizedBox(
          key: item.key,
          height: 48,
          child: NcTappable(
            enabled: item.enabled,
            onTap: item.enabled ? () => _select(item) : null,
            semanticLabel: item.label,
            focusRadius: NcRadii.m,
            autofocus: widget.autofocusFirst && index == 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NcSpace.s12),
              child: Row(
                children: <Widget>[
                  if (item.icon != null) ...<Widget>[
                    Icon(item.icon, size: 20, color: color),
                    const SizedBox(width: NcSpace.s12),
                  ],
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.bodyL.copyWith(color: color),
                    ),
                  ),
                  if (item.trailing != null) ...<Widget>[
                    const SizedBox(width: NcSpace.s8),
                    Text(
                      item.trailing!,
                      style: theme.typography.monoM.copyWith(
                        color: theme.colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return FocusScope(
      autofocus: widget.autofocusFirst,
      child: FocusTraversalGroup(
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                widget.onDismiss?.call(),
          },
          child: NcGlass(
            tier: NcGlassTier.thick,
            radius: NcRadii.l,
            padding: const EdgeInsets.all(NcSpace.s4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.minWidth,
                maxWidth: widget.maxWidth,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: rows),
            ),
          ),
        ),
      ),
    );
  }
}

/// Показывает меню, привязанное к [anchorKey], и возвращает выбранное значение.
///
/// Реализовано через `OverlayEntry` (а не `PopupMenuRoute`): нужен собственный
/// материал `NcGlass` и появление scale 0,94→1 от точки вызова (§8).
Future<T?> showNcMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<NcMenuItem<T>> items,
  double minWidth = 200,
  double maxWidth = 320,
  double gap = 4,
}) {
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  final RenderObject? renderObject = anchorKey.currentContext
      ?.findRenderObject();
  if (overlay == null || renderObject is! RenderBox) {
    return Future<T?>.value(null);
  }
  final Offset anchorTopLeft = renderObject.localToGlobal(Offset.zero);
  final MediaQueryData media = MediaQuery.of(context);
  final double screenWidth = media.size.width;
  final double right =
      (screenWidth - anchorTopLeft.dx - renderObject.size.width).clamp(
        NcSpace.s8,
        screenWidth - NcSpace.s8,
      );
  final double top = anchorTopLeft.dy + renderObject.size.height + gap;
  final Completer<T?> completer = Completer<T?>();
  late final OverlayEntry entry;
  var closed = false;

  void close([T? value]) {
    if (closed) return;
    closed = true;
    entry.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  entry = OverlayEntry(
    builder: (BuildContext overlayContext) => Stack(
      children: <Widget>[
        Positioned.fill(
          child: ModalBarrier(
            color: NcColors.transparent,
            dismissible: true,
            onDismiss: close,
          ),
        ),
        Positioned(
          right: right,
          top: top.clamp(NcSpace.s8, media.size.height - NcSpace.s96),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: AppMotion.fast,
            curve: AppMotion.baseCurve,
            builder: (BuildContext context, double value, Widget? child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.94 + 0.06 * value,
                  alignment: Alignment.topRight,
                  child: child,
                ),
              );
            },
            child: NcMenu<T>(
              items: items,
              minWidth: minWidth,
              maxWidth: maxWidth,
              onDismiss: close,
              onItemSelected: (NcMenuItem<T> item) => close(item.value),
            ),
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return completer.future;
}
