import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import 'internal/nc_spring_builder.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_spacing.dart';
import 'nc_glass.dart';

/// Прозрачная панель в покое; при прокрутке > 8 px — `glass.thin` + hairline
/// снизу (effects-пружина). Large title (`displayL`) схлопывается в `titleM`
/// по центру (REDESIGN-SPEC §8, как в iOS).
class NcTopBar extends StatefulWidget {
  /// Создаёт верхнюю панель.
  const NcTopBar({
    super.key,
    this.title,
    this.largeTitle,
    this.leading,
    this.actions = const <Widget>[],
    this.scrollController,
    this.scrolledOffset = 8,
    this.semanticLabel,
  });

  /// Заголовок в строке (`titleM`).
  final String? title;

  /// Большой заголовок (`displayL`); схлопывается при прокрутке.
  final String? largeTitle;

  /// Кнопка слева (назад, меню).
  final Widget? leading;

  /// Действия справа.
  final List<Widget> actions;

  /// Контроллер прокрутки экрана (панель слушает смещение).
  final ScrollController? scrollController;

  /// Порог, после которого появляется стекло.
  final double scrolledOffset;

  /// Текст семантики заголовка.
  final String? semanticLabel;

  /// Высота панели без large title.
  static const double compactHeight = 56;

  /// Высота панели с large title.
  static const double largeHeight = 104;

  @override
  State<NcTopBar> createState() => _NcTopBarState();
}

class _NcTopBarState extends State<NcTopBar> {
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(NcTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
      _onScroll();
    }
  }

  void _onScroll() {
    final ScrollController? controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;
    final bool next = controller.offset > widget.scrolledOffset;
    if (next != _scrolled) setState(() => _scrolled = next);
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool hasLargeTitle = widget.largeTitle != null;
    final bool scrolled = _scrolled || !hasLargeTitle;
    final String? largeTitle = widget.largeTitle;
    final String? title = widget.title ?? largeTitle;

    return NcSpringBuilder(
      value: scrolled ? 1 : 0,
      spring: NcMotion.of(context).effectsSpring(),
      builder: (BuildContext context, double progress) {
        final double t = progress.clamp(0.0, 1.0);
        final double height = hasLargeTitle
            ? lerpDouble(NcTopBar.largeHeight, NcTopBar.compactHeight, t)!
            : NcTopBar.compactHeight;
        final Widget row = Row(
          children: <Widget>[
            if (widget.leading != null)
              Padding(
                padding: const EdgeInsets.only(left: NcSpace.s4),
                child: widget.leading,
              )
            else
              const SizedBox(width: NcSpace.s20),
            Expanded(
              child: title == null
                  ? const SizedBox.shrink()
                  : Opacity(
                      opacity: hasLargeTitle ? t : 1,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: hasLargeTitle
                            ? TextAlign.center
                            : TextAlign.start,
                        style: theme.typography.titleM.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
            ),
            ...widget.actions,
            const SizedBox(width: NcSpace.s16),
          ],
        );
        return SizedBox(
          height: height,
          child: Stack(
            children: <Widget>[
              if (t > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: t,
                    child: NcGlass(
                      tier: NcGlassTier.thin,
                      radius: 0,
                      showNoise: false,
                      showRimLight: false,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          height: 1,
                          width: double.infinity,
                          child: ColoredBox(color: theme.colors.hairline),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: NcTopBar.compactHeight,
                child: row,
              ),
              if (hasLargeTitle)
                Positioned(
                  left: NcSpace.s20,
                  right: NcSpace.s20,
                  bottom: NcSpace.s12,
                  child: Opacity(
                    opacity: 1 - t,
                    child: Transform.translate(
                      offset: Offset(0, -12 * t),
                      child: Text(
                        largeTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.displayL.copyWith(
                          color: theme.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
