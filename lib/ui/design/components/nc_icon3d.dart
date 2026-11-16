import 'package:material_ui/material_ui.dart';

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
  });

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

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
