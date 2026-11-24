import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart' as domain;
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/session_card.dart';
import 'package:cardflow/ui/state/platform_info.dart';

/// Длительность переворота карточки (SPEC A7.2, аудит v4: 280–350 мс).
const Duration kReviewCardFlipDuration = Duration(milliseconds: 300);

/// Карточка «Классики»/«Тренировки» (SPEC A7.2).
///
/// Тонкая обёртка над единым [SessionCard] (V1): вся геометрия, типографика,
/// нижняя полоса, переворот и прокрутка живут в одном виджете, а этот класс
/// задаёт только ключи «Классики» и отключает свайпы. Публичный API сохранён,
/// поэтому экраны и тесты не меняются.
class ReviewCardView extends StatelessWidget {
  /// Создаёт карточку.
  const ReviewCardView({
    required this.front,
    required this.back,
    required this.revealed,
    required this.onTap,
    this.card,
    this.mediaBytes = const <String, Uint8List>{},
    this.mediaMetadata = const <String, MediaMetadata>{},
    this.onRetryMedia,
    this.scrollController,
    this.questionFooter,
    this.answerFooter,
    this.showUndoHint = false,
    super.key,
  });

  /// Текст вопроса.
  final String front;

  /// Текст ответа.
  final String back;

  /// Показан ли ответ.
  final bool revealed;

  /// Тап по карточке (раскрыть ответ).
  final VoidCallback onTap;

  /// Полная карточка для разметки; optional для прежних вызовов.
  final domain.Card? card;

  /// Байты изображений по `media.id`.
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстраций по `media.id`.
  final Map<String, MediaMetadata> mediaMetadata;

  /// Повтор чтения медиа карточки, если файл/байты не нашлись.
  final VoidCallback? onRetryMedia;

  /// Контроллер прокрутки содержимого (клавиатура сессии).
  final ScrollController? scrollController;

  /// Действие лицевой стороны («Показать ответ»); `null` — нет.
  final Widget? questionFooter;

  /// Действие оборотной стороны (панель оценок); `null` — нет.
  final Widget? answerFooter;

  /// Есть ли что отменять: подсказка «← — отменить» появляется только тогда,
  /// когда откат действительно доступен (аудит 2.0, P1-05/§5.1).
  final bool showUndoHint;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TextStyle? hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Аудит 2.0 (P3-08): на телефоне нет клавиатуры — «Пробел» и «1–4» там
    // невыполнимые инструкции. Подсказки показываются только при физической
    // клавиатуре.
    final bool keyboard = PlatformInfo.hasPhysicalKeyboard;
    return SessionCard(
      front: front,
      back: back,
      revealed: revealed,
      onTap: onTap,
      card: card,
      mediaBytes: mediaBytes,
      mediaMetadata: mediaMetadata,
      onRetryMedia: onRetryMedia,
      scrollController: scrollController,
      questionFooter: questionFooter,
      answerFooter: answerFooter,
      questionHint: keyboard
          ? Text(
              l10n.reviewKeyboardHintsFront,
              key: const ValueKey<String>('review-keyboard-hint-front'),
              textAlign: TextAlign.center,
              style: hintStyle,
            )
          : null,
      answerHint: keyboard
          ? Text(
              showUndoHint
                  ? l10n.reviewKeyboardHints
                  : l10n.reviewKeyboardHintsRating,
              key: const ValueKey<String>('review-keyboard-hint-back'),
              textAlign: TextAlign.center,
              style: hintStyle,
            )
          : null,
      faceKey: const ValueKey<String>('review-card-face'),
      ratingPanelKey: const ValueKey<String>('review-rating-panel'),
      questionActionsKey: const ValueKey<String>('review-card-actions'),
      flipDuration: kReviewCardFlipDuration,
    );
  }
}
