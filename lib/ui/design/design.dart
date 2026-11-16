/// Дизайн-система CardFlow «Nocturne» (единая точка экспорта).
///
/// Слои: токены (`tokens/`), тема-расширение (`nc_theme.dart`), движение и
/// отклик (`motion_scope.dart`, `haptics.dart`), лицензии шрифтов
/// (`font_licenses.dart`), фон (`ambient/`) и переходы (`transitions/`).
/// См. `redesign/REDESIGN-SPEC.md` и ADR-035.
library;

export 'font_licenses.dart';
export 'haptics.dart';
export 'motion_scope.dart';
export 'nc_theme.dart';
export 'tokens/nc_colors.dart';
export 'tokens/nc_depth.dart';
export 'tokens/nc_glass.dart';
export 'tokens/nc_radii.dart';
export 'tokens/nc_spacing.dart';
export 'tokens/nc_typography.dart';
