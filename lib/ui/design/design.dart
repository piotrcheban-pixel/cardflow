/// Дизайн-система CardFlow «Nocturne» (единая точка экспорта).
///
/// Слои: токены (`tokens/`), тема-расширение (`nc_theme.dart`), движение и
/// отклик (`motion_scope.dart`, `haptics.dart`), лицензии шрифтов
/// (`font_licenses.dart`), фон (`ambient/`), переходы (`transitions/`) и
/// библиотека компонентов (`components/`).
/// См. `redesign/redesign-spec.md` и ADR-035.
library;

export 'ambient/ambient_background.dart';
export 'components/nc_badge.dart';
export 'components/nc_glass.dart';
export 'components/nc_icon3d.dart';
export 'components/nc_key_hint.dart';
export 'components/nc_skeleton.dart';
export 'components/nc_spinner.dart';
export 'components/nc_surface.dart';
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
export 'transitions/nc_page_transitions.dart';
