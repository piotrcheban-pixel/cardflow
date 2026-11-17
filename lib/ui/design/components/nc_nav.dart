import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'internal/nc_spring_builder.dart';
import 'internal/nc_pressable.dart';
import 'nc_glass.dart';

/// Навигация Nocturne (REDESIGN-SPEC §8, §9.1): док на телефоне, рейл на
/// планшете, расширенный сайдбар на ПК.
///
/// Компоненты не знают о `GoRouter`: индексы и обработчик приходят от
/// оболочки (`AppShell`), ключи пунктов — контракт экранных тестов.
/// Смена вкладки даёт тактильный отклик `selectionClick` (§7) — его выдаёт
/// `NcTappable` пункта.

/// Пункт навигации.
@immutable
class NcNavItem {
  /// Создаёт пункт.
  const NcNavItem({
    required this.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// Ключ пункта (`shell-nav-*`, контракт REDESIGN-SPEC §9.1).
  final Key key;

  /// Иконка в покое.
  final IconData icon;

  /// Залитая иконка активного пункта.
  final IconData selectedIcon;

  /// Подпись (ARB).
  final String label;
}

/// Телефонный док (`< 600 px`): парящая pill-капсула со пунктами.
///
/// Активный пункт — капсула `ink4` с rim light, которая **переезжает** между
/// пунктами на пружине `snap`. Подпись видна только у активного пункта:
/// капсула расширяется, неактивные остаются иконками.
class NcNavDock extends StatelessWidget {
  /// Создаёт док.
  const NcNavDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.semanticLabel,
  });

  /// Пункты.
  final List<NcNavItem> items;

  /// Активный пункт.
  final int selectedIndex;

  /// Выбор пункта.
  final ValueChanged<int> onSelected;

  /// Текст семантики панели.
  final String? semanticLabel;

  /// Ключ капсулы активного пункта (для теста переезда).
  static const Key capsuleKey = ValueKey<String>('nc-nav-capsule');

  /// Высота дока (§9.1).
  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    final NcMotion motion = NcMotion.of(context);
    final double slots = items.isEmpty ? 1 : items.length.toDouble();
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: NcGlass(
          tier: NcGlassTier.regular,
          radius: NcRadii.pill,
          showNoise: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: NcSpace.s4),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: NcSpringBuilder(
                    value: selectedIndex.toDouble(),
                    spring: motion.snapSpring(),
                    builder: (BuildContext context, double value) {
                      final double t = slots <= 1
                          ? 0
                          : (value / (slots - 1)).clamp(0.0, 1.0);
                      return Align(
                        key: capsuleKey,
                        alignment: Alignment(t * 2 - 1, 0),
                        child: FractionallySizedBox(
                          widthFactor: 1 / slots,
                          heightFactor: 0.76,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: NcSpace.s8,
                            ),
                            decoration: ShapeDecoration(
                              color: colors.ink4,
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(
                                  NcRadii.pill,
                                ),
                                side: BorderSide(
                                  color: colors.rimLight.withValues(
                                    alpha: 0.28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  children: <Widget>[
                    for (var index = 0; index < items.length; index++)
                      Expanded(
                        child: _DockItem(
                          item: items[index],
                          selected: index == selectedIndex,
                          onTap: () => onSelected(index),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NcNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    final TextStyle labelStyle = theme.typography.labelM.copyWith(
      color: colors.aurum,
    );
    final Widget icon = Icon(
      selected ? item.selectedIcon : item.icon,
      size: 24,
      color: selected ? colors.aurum : colors.textSecondary,
    );
    return NcTappable(
      key: item.key,
      semanticLabel: item.label,
      semanticValue: selected ? '1' : '0',
      scaleOnPress: false,
      onTap: onTap,
      child: Center(
        child: selected
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: NcSpace.s4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    icon,
                    const SizedBox(width: NcSpace.s8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          style: labelStyle,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : icon,
      ),
    );
  }
}

/// Планшетный рейл (`600–1023 px`): 80 px слева на стекле.
///
/// Сверху — плоская монограмма CardFlow (две карточки, `aurum`), пункты —
/// иконка + подпись под ней, активный — капсула `ink4`.
class NcNavRail extends StatelessWidget {
  /// Создаёт рейл.
  const NcNavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.semanticLabel,
  });

  /// Пункты.
  final List<NcNavItem> items;

  /// Активный пункт.
  final int selectedIndex;

  /// Выбор пункта.
  final ValueChanged<int> onSelected;

  /// Текст семантики панели.
  final String? semanticLabel;

  /// Ширина рейла (§9.1).
  static const double width = 80;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        width: width,
        child: NcGlass(
          tier: NcGlassTier.regular,
          borderRadiusGeometry: const BorderRadiusDirectional.horizontal(
            end: Radius.circular(NcRadii.xl),
          ),
          showNoise: false,
          child: SafeArea(
            right: false,
            child: Column(
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: NcSpace.s16),
                  child: NcNavLogo(size: 32),
                ),
                const SizedBox(height: NcSpace.s16),
                for (var index = 0; index < items.length; index++) ...<Widget>[
                  if (index > 0) const SizedBox(height: NcSpace.s8),
                  _RailItem(
                    item: items[index],
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ],
                const SizedBox(height: NcSpace.s8),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 32,
                      height: 1,
                      margin: const EdgeInsets.only(bottom: NcSpace.s16),
                      color: colors.hairline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NcNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    return NcTappable(
      key: item.key,
      semanticLabel: item.label,
      scaleOnPress: false,
      onTap: onTap,
      child: Container(
        width: 64,
        margin: const EdgeInsets.symmetric(horizontal: NcSpace.s8),
        padding: const EdgeInsets.symmetric(
          horizontal: NcSpace.s4,
          vertical: NcSpace.s8,
        ),
        decoration: selected
            ? ShapeDecoration(
                color: colors.ink4,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(NcRadii.l),
                ),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: 24,
              color: selected ? colors.aurum : colors.textSecondary,
            ),
            const SizedBox(height: NcSpace.s4),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.typography.labelM.copyWith(
                    color: selected ? colors.aurum : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ПК-сайдбар (`≥ 1024 px`): 248 px, логотип и название, пункты строками.
class NcNavSidebar extends StatelessWidget {
  /// Создаёт сайдбар.
  const NcNavSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.appName,
    this.semanticLabel,
  });

  /// Пункты.
  final List<NcNavItem> items;

  /// Активный пункт.
  final int selectedIndex;

  /// Выбор пункта.
  final ValueChanged<int> onSelected;

  /// Название приложения (Literata `titleL`).
  final String appName;

  /// Текст семантики панели.
  final String? semanticLabel;

  /// Ширина сайдбара (§9.1).
  static const double width = 248;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: colors.ink1,
          border: BorderDirectional(end: BorderSide(color: colors.hairline)),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NcSpace.s20,
                  NcSpace.s20,
                  NcSpace.s16,
                  NcSpace.s24,
                ),
                child: Row(
                  children: <Widget>[
                    const NcNavLogo(size: 28),
                    const SizedBox(width: NcSpace.s12),
                    Expanded(
                      child: Text(
                        appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.titleL.copyWith(
                          fontFamily: 'Literata',
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (var index = 0; index < items.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(height: NcSpace.s4),
                _SidebarItem(
                  item: items[index],
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NcNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NcSpace.s12),
      child: NcTappable(
        key: item.key,
        semanticLabel: item.label,
        scaleOnPress: false,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: NcSpace.s12),
          decoration: selected
              ? ShapeDecoration(
                  color: colors.ink4,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(NcRadii.m),
                  ),
                )
              : null,
          child: Row(
            children: <Widget>[
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 20,
                color: selected ? colors.aurum : colors.textSecondary,
              ),
              const SizedBox(width: NcSpace.s12),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.labelL.copyWith(
                    color: selected ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плоская монограмма CardFlow: две карточки со сдвигом (§9.1).
class NcNavLogo extends StatelessWidget {
  /// Создаёт логотип.
  const NcNavLogo({super.key, this.size = 28});

  /// Сторона знака.
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>('nc-nav-logo'),
      width: size,
      height: size,
      child: CustomPaint(
        painter: _NcNavLogoPainter(color: NcTheme.of(context).colors.aurum),
      ),
    );
  }
}

class _NcNavLogoPainter extends CustomPainter {
  const _NcNavLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double cardWidth = size.width * 0.52;
    final double cardHeight = size.height * 0.72;
    final Paint back = Paint()..color = color.withValues(alpha: 0.55);
    final Paint front = Paint()..color = color;
    final RRect backCard = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.44, size.height * 0.5),
        width: cardWidth,
        height: cardHeight,
      ),
      Radius.circular(size.width * 0.1),
    );
    final RRect frontCard = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * 0.6, size.height * 0.44),
        width: cardWidth,
        height: cardHeight,
      ),
      Radius.circular(size.width * 0.1),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 18);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawRRect(backCard, back);
    canvas.drawRRect(frontCard, front);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NcNavLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
