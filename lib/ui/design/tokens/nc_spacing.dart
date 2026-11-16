/// Пространство, сетка и максимальные ширины Nocturne (REDESIGN-SPEC §3.1).
///
/// Сетка 4 pt: `0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 56, 72, 96`. Поля страницы
/// зависят от ширины окна: телефон 20 · планшет (≥ 600) 32 · ПК (≥ 1024) 40.
abstract final class NcSpace {
  /// 0 px.
  static const double s0 = 0;

  /// 2 px.
  static const double s2 = 2;

  /// 4 px.
  static const double s4 = 4;

  /// 8 px.
  static const double s8 = 8;

  /// 12 px.
  static const double s12 = 12;

  /// 16 px.
  static const double s16 = 16;

  /// 20 px.
  static const double s20 = 20;

  /// 24 px.
  static const double s24 = 24;

  /// 32 px.
  static const double s32 = 32;

  /// 40 px.
  static const double s40 = 40;

  /// 56 px.
  static const double s56 = 56;

  /// 72 px.
  static const double s72 = 72;

  /// 96 px.
  static const double s96 = 96;

  /// Полная шкала отступов (для тестов и каскадов).
  static const List<double> scale = <double>[
    s0,
    s2,
    s4,
    s8,
    s12,
    s16,
    s20,
    s24,
    s32,
    s40,
    s56,
    s72,
    s96,
  ];

  /// Максимальная ширина списков (колоды, настройки).
  static const double maxListWidth = 760;

  /// Максимальная ширина карточки сессии.
  static const double maxSessionWidth = 640;

  /// Максимальная ширина формы карточки/настроек.
  static const double maxFormWidth = 680;

  /// Максимальная ширина сетки статистики.
  static const double maxStatsWidth = 1120;

  /// Горизонтальный внутренний отступ плитки.
  static const double tilePaddingH = 16;

  /// Вертикальный внутренний отступ плитки.
  static const double tilePaddingV = 14;

  /// Минимальная касаемая зона (§3.1: ≥ 48 × 48).
  static const double minTouchTarget = 48;

  /// Высота кнопки оценки в доке сессии.
  static const double ratingButtonHeight = 64;

  /// Нижний запас списка под парящим доком (без `safeArea.bottom`).
  static const double dockClearance = 120;

  /// Поля страницы по ширине окна: 20 / 32 / 40.
  static double pagePadding(double width) {
    if (width >= 1024) return s40;
    if (width >= 600) return s32;
    return s20;
  }

  /// Расстояние между секциями: 32 (телефон) / 40 (ПК).
  static double sectionGap(double width) => width >= 1024 ? s40 : s32;
}
