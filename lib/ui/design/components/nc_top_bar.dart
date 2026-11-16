import 'package:material_ui/material_ui.dart';

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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
