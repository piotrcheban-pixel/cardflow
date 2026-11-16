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
export 'components/nc_button.dart';
export 'components/nc_animated_number.dart';
export 'components/nc_card_tile.dart';
export 'components/nc_chip.dart';
export 'components/nc_dialog.dart';
export 'components/nc_dropdown.dart';
export 'components/nc_empty_state.dart';
export 'components/nc_flip.dart';
export 'components/nc_error_state.dart';
export 'components/nc_fab.dart';
export 'components/nc_glass.dart';
export 'components/nc_icon3d.dart';
export 'components/nc_icon_button.dart';
export 'components/nc_key_hint.dart';
export 'components/nc_list_row.dart';
export 'components/nc_monolith.dart';
export 'components/nc_menu.dart';
export 'components/nc_search_field.dart';
export 'components/nc_progress_line.dart';
export 'components/nc_rating_button.dart';
export 'components/nc_rating_dock.dart';
export 'components/nc_ring.dart';
export 'components/nc_section.dart';
export 'components/nc_segmented_progress.dart';
export 'components/nc_sheet.dart';
export 'components/nc_segmented.dart';
export 'components/nc_slider.dart';
export 'components/nc_skeleton.dart';
export 'components/nc_split_button.dart';
export 'components/nc_stepper.dart';
export 'components/nc_switch.dart';
export 'components/nc_text_field.dart';
export 'components/nc_toast.dart';
export 'components/nc_top_bar.dart';
export 'components/nc_spinner.dart';
export 'components/nc_surface.dart';
export 'components/internal/nc_scroll_collapse.dart'
    show NcScrollCollapse, NcScrollCollapseScope;
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
