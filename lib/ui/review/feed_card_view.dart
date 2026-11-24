import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/session_card.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Карточка «Ленты» (SPEC A7.3).
///
/// Тонкая обёртка над единым [SessionCard] (V1): включает свайпы-оценки,
/// пружину, морфинг формы, бейдж «оценено», подсказку о свайпах и семантику
/// жестов. Вся отрисовка — в общем компоненте, поэтому «Классика» и «Лента»
/// больше не расходятся геометрией, типографикой и нижней полосой.
class FeedCardView extends StatelessWidget {
  /// Создаёт карточку ленты.
  const FeedCardView({
    required this.front,
    required this.back,
    required this.revealed,
    required this.rated,
    required this.rating,
    required this.enabled,
    required this.resetToken,
    required this.onTap,
    required this.onRate,
    this.card,
    this.mediaBytes = const <String, Uint8List>{},
    this.mediaMetadata = const <String, MediaMetadata>{},
    this.onRetryMedia,
    this.answerFooter,
    this.spring,
    super.key,
  });

  /// Текст вопроса.
  final String front;

  /// Текст ответа.
  final String back;

  /// Показан ли ответ.
  final bool revealed;

  /// Оценена ли карточка.
  final bool rated;

  /// Оценка карточки, если она оценена.
  final Rating? rating;

  /// Доступны ли жесты/тап (не идёт запись, карточка не оценена).
  final bool enabled;

  /// Счётчик сброса анимации после ошибки записи.
  final int resetToken;

  /// Тап по карточке (раскрыть/скрыть ответ).
  final VoidCallback onTap;

  /// Оценка свайпом.
  final ValueChanged<Rating> onRate;

  /// Полная карточка для разметки; optional для прежних вызовов.
  final Card? card;

  /// Байты изображений по `media.id`.
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстраций по `media.id`.
  final Map<String, MediaMetadata> mediaMetadata;

  /// Повтор чтения медиа карточки, если файл/байты не нашлись.
  final VoidCallback? onRetryMedia;

  /// Полоса оценок внутри карточки (после ответа).
  final Widget? answerFooter;

  /// Пружина переворота/возврата карточки (A6.6, ADR-019 §2).
  final SpringDescription? spring;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TextStyle? hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SessionCard(
      front: front,
      back: back,
      revealed: revealed,
      onTap: onTap,
      card: card,
      mediaBytes: mediaBytes,
      mediaMetadata: mediaMetadata,
      onRetryMedia: onRetryMedia,
      answerFooter: answerFooter,
      questionHint: Text(
        l10n.reviewKeyboardHintsFront,
        textAlign: TextAlign.center,
        style: hintStyle,
      ),
      answerHint: Text(
        l10n.feedRateHint,
        key: const ValueKey<String>('feed-rate-hint'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      ratedOverlay: rated ? const _RatedBadge() : null,
      semanticLabel: revealed ? back : front,
      semanticHint: l10n.feedSwipeHint,
      enableSwipe: true,
      swipeEnabled: enabled,
      rated: rated,
      rating: rating,
      resetToken: resetToken,
      spring: spring,
      onRate: onRate,
      faceKey: const ValueKey<String>('feed-card-face'),
      echoFaceKey: const ValueKey<String>('feed-card-echo'),
      flipTransformKey: const ValueKey<String>('feed-card-flip-transform'),
      swipeTransformKey: const ValueKey<String>('feed-swipe-transform'),
    );
  }
}

class _RatedBadge extends StatelessWidget {
  const _RatedBadge();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('feed-rated-label'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.check_circle,
            size: AppSizes.iconSmall,
            color: scheme.primary,
          ),
          const SizedBox(width: AppSpacing.xxs + 2),
          Text(
            l10n.feedRatedLabel,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
