import 'package:material_ui/material_ui.dart';

/// Типографическая шкала Nocturne (REDESIGN-SPEC §2, ADR-035).
///
/// Три семейства, все с кириллицей и OFL, в `assets/fonts/`:
/// **Onest** (интерфейс), **Literata** (вопрос/ответ карточки, крупные цифры),
/// **JetBrains Mono** (интервалы, таймер, счётчики). Шрифт для дислексии
/// заменяет **все три** ([asDyslexic]): межстрочный интервал +10 %, трекинг 0
/// (ADR-019 §6).
///
/// Переменные шрифты: стандартные веса задаются `FontWeight` (в Flutter
/// `FontWeight` проецируется в ось `wght`), нестандартные — `FontVariation`
/// (`wght 450` у `question`, `wght 650` у `overline`), оптический размер
/// Literata — `FontVariation('opsz')`. Спайк 1.0, `journal/redesign-1/spikes.md`.
@immutable
class NcTypography {
  const NcTypography({
    required this.displayXL,
    required this.displayL,
    required this.headline,
    required this.question,
    required this.answer,
    required this.titleL,
    required this.titleM,
    required this.titleS,
    required this.bodyL,
    required this.bodyM,
    required this.bodyS,
    required this.labelL,
    required this.labelM,
    required this.overline,
    required this.monoM,
    required this.monoL,
  });

  /// Семейство интерфейса.
  static const String sansFamily = 'Onest';

  /// Семейство текста карточки и крупных цифр.
  static const String serifFamily = 'Literata';

  /// Семейство интервалов/таймеров/счётчиков.
  static const String monoFamily = 'JetBrainsMono';

  /// Семейство шрифта для дислексии (`AppTheme.dyslexiaFontFamily`).
  static const String dyslexicFamily = 'OpenDyslexic';

  /// Шкала по таблице §2.2.
  static const NcTypography standard = NcTypography(
    displayXL: TextStyle(
      fontFamily: serifFamily,
      fontSize: 64,
      height: 1,
      fontWeight: FontWeight.w500,
      letterSpacing: -1.28,
      fontVariations: <FontVariation>[FontVariation('opsz', 72)],
    ),
    displayL: TextStyle(
      fontFamily: serifFamily,
      fontSize: 44,
      height: 48 / 44,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.66,
      fontVariations: <FontVariation>[FontVariation('opsz', 48)],
    ),
    headline: TextStyle(
      fontFamily: serifFamily,
      fontSize: 30,
      height: 36 / 30,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.3,
      fontVariations: <FontVariation>[FontVariation('opsz', 32)],
    ),
    question: TextStyle(
      fontFamily: serifFamily,
      fontSize: 28,
      height: 36 / 28,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.14,
      fontVariations: <FontVariation>[
        FontVariation('wght', 450),
        FontVariation('opsz', 28),
      ],
    ),
    answer: TextStyle(
      fontFamily: serifFamily,
      fontSize: 19,
      height: 30 / 19,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      fontVariations: <FontVariation>[FontVariation('opsz', 18)],
    ),
    titleL: TextStyle(
      fontFamily: sansFamily,
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    titleM: TextStyle(
      fontFamily: sansFamily,
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.034,
    ),
    titleS: TextStyle(
      fontFamily: sansFamily,
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    bodyL: TextStyle(
      fontFamily: sansFamily,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    bodyM: TextStyle(
      fontFamily: sansFamily,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    bodyS: TextStyle(
      fontFamily: sansFamily,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.013,
    ),
    labelL: TextStyle(
      fontFamily: sansFamily,
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.03,
    ),
    labelM: TextStyle(
      fontFamily: sansFamily,
      fontSize: 13,
      height: 16 / 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.039,
    ),
    overline: TextStyle(
      fontFamily: sansFamily,
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.88,
      fontVariations: <FontVariation>[FontVariation('wght', 650)],
    ),
    monoM: TextStyle(
      fontFamily: monoFamily,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    ),
    monoL: TextStyle(
      fontFamily: monoFamily,
      fontSize: 22,
      height: 26 / 22,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.22,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    ),
  );

  /// `displayXL` — процент удержания, точность в итогах (Literata 64/64).
  final TextStyle displayXL;

  /// `displayL` — «Мои колоды», «Статистика» (Literata 44/48).
  final TextStyle displayL;

  /// `headline` — название колоды, заголовки итогов (Literata 30/36).
  final TextStyle headline;

  /// `question` — лицевая сторона карточки (Literata 28/36, wght 450).
  final TextStyle question;

  /// `answer` — обратная сторона карточки (Literata 19/30).
  final TextStyle answer;

  /// `titleL` — заголовок листа, диалога.
  final TextStyle titleL;

  /// `titleM` — название в плитке колоды.
  final TextStyle titleM;

  /// `titleS` — строки настроек.
  final TextStyle titleS;

  /// `bodyL` — обычный текст, поля.
  final TextStyle bodyL;

  /// `bodyM` — подзаголовки, описания.
  final TextStyle bodyM;

  /// `bodyS` — пояснения под полями.
  final TextStyle bodyS;

  /// `labelL` — текст кнопок.
  final TextStyle labelL;

  /// `labelM` — чипы, бейджи, вкладки.
  final TextStyle labelM;

  /// `overline` — заголовки секций (текст пишется заглавными в ARB).
  final TextStyle overline;

  /// `monoM` — интервал над кнопкой оценки, размер файла.
  final TextStyle monoM;

  /// `monoL` — таймер, счётчик токенов.
  final TextStyle monoL;

  /// Все роли шкалы (для тестов применения и проекции).
  List<TextStyle> get roles => <TextStyle>[
    displayXL,
    displayL,
    headline,
    question,
    answer,
    titleL,
    titleM,
    titleS,
    bodyL,
    bodyM,
    bodyS,
    labelL,
    labelM,
    overline,
    monoM,
    monoL,
  ];

  /// Копия шкалы для режима «Шрифт для дислексии».
  ///
  /// Все роли (включая Literata и моноширинные) переводятся на OpenDyslexic,
  /// интерлиньяж +10 %, трекинг 0, вариации снимаются: у OpenDyslexic нет осей.
  NcTypography asDyslexic() {
    TextStyle map(TextStyle style) {
      final double? height = style.height;
      return style.copyWith(
        fontFamily: dyslexicFamily,
        fontFamilyFallback: const <String>[],
        height: height == null ? null : height * 1.1,
        letterSpacing: 0,
        fontVariations: const <FontVariation>[],
      );
    }

    return NcTypography(
      displayXL: map(displayXL),
      displayL: map(displayL),
      headline: map(headline),
      question: map(question),
      answer: map(answer),
      titleL: map(titleL),
      titleM: map(titleM),
      titleS: map(titleS),
      bodyL: map(bodyL),
      bodyM: map(bodyM),
      bodyS: map(bodyS),
      labelL: map(labelL),
      labelM: map(labelM),
      overline: map(overline),
      monoM: map(monoM),
      monoL: map(monoL),
    );
  }

  /// Проекция в `TextTheme` (Material-виджеты получают шрифты Nocturne).
  ///
  /// Роль `answer` и моноширинные роли в `TextTheme` не проецируются: они
  /// используются компонентами карточки напрямую через `NcTheme.typography`.
  /// `bodyLarge` — роль `bodyL` (Onest 16/24), как требует §2.2.
  TextTheme toTextTheme() => TextTheme(
    displayLarge: displayXL,
    displayMedium: displayL,
    displaySmall: headline,
    headlineLarge: displayL,
    headlineMedium: headline,
    headlineSmall: question,
    titleLarge: titleL,
    titleMedium: titleM,
    titleSmall: titleS,
    bodyLarge: bodyL,
    bodyMedium: bodyM,
    bodySmall: bodyS,
    labelLarge: labelL,
    labelMedium: labelM,
    labelSmall: overline,
  );
}
