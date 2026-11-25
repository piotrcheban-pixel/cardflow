import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/answer_type.dart';
import 'package:cardflow/domain/study/distractor_generator.dart';
import 'package:cardflow/domain/study/true_false_question.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Режим сессии, который выбирают в листе режимов (SPEC A6.3).
enum DeckSessionMode {
  /// Классическое повторение по расписанию.
  classic,

  /// Повторение «лентой» (ADR-016).
  feed,

  /// Тренировка без влияния на FSRS (ADR-025).
  practice,

  /// Тест с вариантами ответа.
  test,

  /// Ввод ответа с клавиатуры.
  typing,

  /// Подбор пар.
  match,

  /// Верно/Неверно.
  trueFalse,

  /// Конструктор сессии (ADR-018).
  constructor,
}

/// Сколько карточек подходит для каждого проверочного режима.
///
/// Считается один раз до открытия листа: недоступный режим показывает причину,
/// а не «мёртвую» строку без объяснения.
class DeckModeAvailability {
  /// Создаёт счётчики доступности.
  const DeckModeAvailability({
    required this.testCount,
    required this.typingCount,
    required this.matchableCount,
    required this.trueFalseCount,
  });

  /// Считает доступность по карточкам колоды.
  factory DeckModeAvailability.fromCards(List<Card> cards) {
    final DistractorGenerator distractorGenerator = DistractorGenerator();
    return DeckModeAvailability(
      testCount: cards
          .where(
            (Card card) =>
                AnswerTypes.isChoice(card) &&
                distractorGenerator.buildQuestion(card, cards) != null,
          )
          .length,
      typingCount: cards
          .where((Card card) => AnswerTypes.isTypable(card))
          .length,
      matchableCount: cards
          .where(
            (Card card) =>
                card.cardType != CardType.cloze &&
                card.front.trim().isNotEmpty &&
                card.back.trim().isNotEmpty,
          )
          .length,
      trueFalseCount: cards
          .where((Card card) => hasTrueFalseAlternative(card, cards))
          .length,
    );
  }

  /// «Тест» доступен при хотя бы одной карточке с вариантами.
  final int testCount;

  /// «Ввод ответа» доступен при хотя бы одной карточке с коротким ответом.
  final int typingCount;

  /// «Подбор пар» требует минимум 6 карточек.
  final int matchableCount;

  /// «Верно/Неверно» требует альтернативный ответ в колоде.
  final int trueFalseCount;
}

/// Открывает лист выбора режима сессии и возвращает выбранный режим.
///
/// Аудит v4 (V3): лист больше не «не помещается» — на широком экране это
/// сетка 2×, на узком — прокручиваемый список с индикатором; у каждой группы
/// есть заголовок, недоступный режим объясняет причину. Аудит v4 (V5): лист
/// используют оба входа — кнопка «Учить» на карточке колоды и панель
/// «Начать сессию» на экране колоды, поэтому действие одно и то же.
Future<DeckSessionMode?> showDeckModesSheet(
  BuildContext context, {
  required DeckModeAvailability availability,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final Size size = MediaQuery.sizeOf(context);
  final double maxWidth = math.min(size.width - AppSpacing.xl, 760);
  Widget available(
    DeckSessionMode mode,
    IconData icon,
    String title,
    String subtitle, {
    bool enabled = true,
    Key? key,
  }) {
    return _ModeTile(
      tileKey: key,
      mode: mode,
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
    );
  }

  final bool availableTest = availability.testCount > 0;
  final bool availableTyping = availability.typingCount > 0;
  final bool availableMatch = availability.matchableCount >= 6;
  final bool availableTrueFalse = availability.trueFalseCount > 0;
  final List<Widget> review = <Widget>[
    available(
      DeckSessionMode.classic,
      Icons.style_outlined,
      l10n.reviewModeClassic,
      l10n.reviewModeClassicSubtitle,
      key: const ValueKey<String>('review-mode-classic'),
    ),
    available(
      DeckSessionMode.feed,
      Icons.view_agenda_outlined,
      l10n.reviewModeFeed,
      l10n.reviewModeFeedSubtitle,
      key: const ValueKey<String>('review-mode-feed'),
    ),
    available(
      DeckSessionMode.practice,
      Icons.sports_esports_outlined,
      l10n.reviewModePractice,
      l10n.practiceSubtitle,
      key: const ValueKey<String>('review-mode-practice'),
    ),
  ];
  final List<Widget> check = <Widget>[
    available(
      DeckSessionMode.test,
      Icons.quiz_outlined,
      l10n.reviewModeTest,
      availableTest
          ? '${l10n.studyModeTestSubtitle} · '
                '${l10n.studyModeAvailableCount(availability.testCount)}'
          : l10n.studyModeTestNotEnough(availability.testCount),
      enabled: availableTest,
      key: const ValueKey<String>('review-mode-test'),
    ),
    available(
      DeckSessionMode.typing,
      Icons.keyboard_outlined,
      l10n.reviewModeTyping,
      availableTyping
          ? '${l10n.studyModeTypingSubtitle} · '
                '${l10n.studyModeAvailableCount(availability.typingCount)}'
          : l10n.studyModeTypingNotEnough(availability.typingCount),
      enabled: availableTyping,
      key: const ValueKey<String>('review-mode-typing'),
    ),
    available(
      DeckSessionMode.match,
      Icons.grid_view_outlined,
      l10n.reviewModeMatch,
      availableMatch
          ? '${l10n.studyModeMatchSubtitle} · '
                '${l10n.studyModeAvailableCount(availability.matchableCount)}'
          : '${l10n.studyModeMatchNotEnough} · '
                '${l10n.studyModeAvailableCount(availability.matchableCount)}',
      enabled: availableMatch,
      key: const ValueKey<String>('review-mode-match'),
    ),
    available(
      DeckSessionMode.trueFalse,
      Icons.check_circle_outline,
      l10n.reviewModeTrueFalse,
      availableTrueFalse
          ? '${l10n.studyModeTrueFalseSubtitle} · '
                '${l10n.studyModeAvailableCount(availability.trueFalseCount)}'
          : '${l10n.studyModeTrueFalseNotEnough} · '
                '${l10n.studyModeAvailableCount(availability.trueFalseCount)}',
      enabled: availableTrueFalse,
      key: const ValueKey<String>('review-mode-true-false'),
    ),
  ];
  final List<Widget> setup = <Widget>[
    available(
      DeckSessionMode.constructor,
      Icons.tune,
      l10n.constructorAction,
      l10n.constructorSubtitle,
      key: const ValueKey<String>('review-mode-constructor'),
    ),
  ];

  // TASK 04 (M-03): лист открывается на 72 % высоты, а не на 98 %; тянется
  // вниз из любого места списка и закрывается, дойдя до минимума. Раньше
  // `SingleChildScrollView` перехватывал жест и закрыть лист свайпом по
  // содержимому было невозможно.
  return showAppDetentSheet<DeckSessionMode>(
    context: context,
    maxWidth: maxWidth,
    builder: (BuildContext sheetContext, ScrollController controller) {
      // TASK 04: SingleChildScrollView + Column (а не ListView) — все плитки
      // построены сразу: клавиатурный/экранный поиск и тесты видят весь список,
      // а контроллер прокрутки всё равно принадлежит DraggableScrollableSheet,
      // поэтому свайп вниз закрывает лист.
      return SingleChildScrollView(
        key: const ValueKey<String>('deck-modes-list'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSheetHeader(
              title: l10n.reviewSessionModeTitle,
              subtitle: l10n.deckStudyModesTitle,
              // Аудит v5 (V5-12): видимый способ закрыть лист.
              trailing: IconButton(
                key: const ValueKey<String>('review-modes-close'),
                tooltip: l10n.cancel,
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ModeGroup(title: l10n.deckModesGroupReview, tiles: review),
            _ModeGroup(title: l10n.deckModesGroupCheck, tiles: check),
            _ModeGroup(title: l10n.deckModesGroupCustom, tiles: setup),
          ],
        ),
      );
    },
  );
}

/// Группа режимов: подпись и сетка плиток (2 колонки на широком листе).
class _ModeGroup extends StatelessWidget {
  const _ModeGroup({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xs,
            bottom: AppSpacing.xxs,
          ),
          child: Text(
            title.toUpperCase(),
            style: AppTypography.overline(context),
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool twoColumns = constraints.maxWidth >= 560;
            if (!twoColumns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final Widget tile in tiles) ...<Widget>[
                    tile,
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              );
            }
            final double gap = AppSpacing.xs;
            final double width = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final Widget tile in tiles)
                  SizedBox(width: width, height: 80, child: tile),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Плитка режима: иконка, название и пояснение; недоступная — приглушена и
/// объясняет причину в подписи.
///
/// Внутри — `ListTile`: он сохраняет доступность (semantics, enabled) и
/// привычное поведение клавиатуры/ховера, а плитка задаёт рамку и размер.
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.tileKey,
  });

  final DeckSessionMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;

  /// Ключ плитки (`review-mode-*`) на самом интерактивном элементе.
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foreground = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: tileKey,
        enabled: enabled,
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 4,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        onTap: enabled ? () => Navigator.of(context).pop(mode) : null,
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled
                ? scheme.primary.withValues(alpha: 0.10)
                : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: AppSizes.navIcon,
            color: enabled ? scheme.primary : scheme.outline,
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(color: foreground),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: enabled ? scheme.onSurfaceVariant : scheme.outline,
          ),
        ),
      ),
    );
  }
}
