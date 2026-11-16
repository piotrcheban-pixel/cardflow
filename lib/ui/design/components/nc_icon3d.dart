import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_depth.dart';

/// 3D-иконка Nocturne (REDESIGN-SPEC §5): ассет WebP из `assets/icons3d/`,
/// а пока его нет — резерв: стеклянная сфера `glass.thin` с плоским
/// Rounded-глифом внутри (§5.5). Иконка декоративная: смысл передаёт подпись
/// рядом, поэтому узел исключён из семантики.
class NcIcon3D extends StatelessWidget {
  /// Создаёт 3D-иконку по имени из инвентаря §5.3.
  const NcIcon3D({
    super.key,
    required this.name,
    this.size = 56,
    this.tone,
    this.showShadow = true,
    this.excludeFromSemantics = true,
  }) : assert(size >= 40, '3D-иконки используются только от 40 px (§5.1)');

  /// Имя ассета (`mode_classic`, `empty_decks`, `target`, …).
  final String name;

  /// Сторона квадрата, логические px (3D — только от 40).
  final double size;

  /// Тон аватара колоды (§5.4) — тонирует глиф резерва.
  final Color? tone;

  /// Рисовать ли тень `depth2`.
  final bool showShadow;

  /// Исключить из семантики (по умолчанию да, §5.1).
  final bool excludeFromSemantics;

  /// Доступные ассеты (заполняется на этапе 5 при импорте ComfyUI-набора).
  static const Map<String, String> assets = <String, String>{};

  /// Есть ли ассет для [name].
  static bool hasAsset(String name) => assets.containsKey(name);

  /// Плоский Rounded-глиф резерва для имени из инвентаря §5.3.
  static IconData glyphFor(String name) {
    if (name.startsWith('deck_gem')) return Icons.diamond_rounded;
    return _glyphs[name] ?? Icons.auto_awesome_rounded;
  }

  static const Map<String, IconData> _glyphs = <String, IconData>{
    'mode_classic': Icons.style_rounded,
    'mode_feed': Icons.view_agenda_rounded,
    'mode_practice': Icons.fitness_center_rounded,
    'mode_test': Icons.grid_view_rounded,
    'mode_typing': Icons.keyboard_rounded,
    'mode_match': Icons.extension_rounded,
    'mode_true_false': Icons.toll_rounded,
    'mode_constructor': Icons.tune_rounded,
    'ai_orb': Icons.auto_awesome_rounded,
    'file_stack': Icons.description_rounded,
    'empty_decks': Icons.inventory_2_rounded,
    'empty_cards': Icons.style_rounded,
    'empty_stats': Icons.hourglass_empty_rounded,
    'trophy': Icons.emoji_events_rounded,
    'streak_flame': Icons.local_fire_department_rounded,
    'target': Icons.track_changes_rounded,
    'key': Icons.key_rounded,
    'shield_error': Icons.gpp_bad_rounded,
    'hourglass_time': Icons.hourglass_bottom_rounded,
    'moon_done': Icons.nightlight_round,
  };

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Color toneColor = tone ?? theme.colors.aurum;
    final String? asset = assets[name];
    final Widget icon = asset != null
        ? Image.asset(
            asset,
            width: size,
            height: size,
            filterQuality: FilterQuality.medium,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
            excludeFromSemantics: true,
            gaplessPlayback: true,
          )
        : _reserve(context, toneColor);
    final Widget sized = SizedBox.square(dimension: size, child: icon);
    if (showShadow) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: NcDepth.level(2, dark: theme.isDark),
        ),
        child: sized,
      );
    }
    return sized;
  }

  Widget _reserve(BuildContext context, Color toneColor) {
    final NcTheme theme = NcTheme.of(context);
    final Widget sphere = DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(size / 2),
          side: BorderSide(color: theme.colors.hairlineStrong),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.alphaBlend(
              toneColor.withValues(alpha: 0.18),
              theme.colors.ink4,
            ),
            Color.alphaBlend(
              toneColor.withValues(alpha: 0.06),
              theme.colors.ink2,
            ),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size * 0.42,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(size / 2),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      theme.colors.rimLight.withValues(alpha: 0.55),
                      theme.colors.rimLight.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Icon(glyphFor(name), size: size * 0.44, color: toneColor),
          ),
        ],
      ),
    );
    final Widget clipped = ClipRSuperellipse(
      borderRadius: BorderRadius.circular(size / 2),
      child: sphere,
    );
    if (!excludeFromSemantics) return clipped;
    return ExcludeSemantics(child: clipped);
  }
}
