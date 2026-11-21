import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/cards/content/cloze_text.dart';
import 'package:cardflow/ui/cards/content/latex_text.dart';
import 'package:cardflow/ui/cards/content/occlusion_image_view.dart';

/// Единый рендер карточки для классики и ленты (ADR-017).
///
/// Итерация 7.19 (ADR-042): изображения выбираются **по стороне** — до
/// переворота видны только `questionMediaIds`, после — только
/// `answerMediaIds`. Раньше `mediaIds.first` рисовался на обеих сторонах, и
/// изображение с ответом раскрывало его на лицевой стороне.
class CardContentView extends StatelessWidget {
  const CardContentView({
    required this.card,
    required this.side,
    required this.revealed,
    required this.faceKey,
    this.mediaBytes = const <String, Uint8List>{},
    this.mediaMetadata = const <String, MediaMetadata>{},
    this.onRetryMedia,
    this.showAllFormulas = false,
    super.key,
  });

  final Card card;
  final String side;
  final bool revealed;
  final ValueKey<String> faceKey;

  /// Показывать все формулы сразу, без пошагового раскрытия (7.17).
  ///
  /// Вопрос режимов «Тест», «Ввод ответа» и «Верно/Неверно» должен быть виден
  /// целиком: пошаговое раскрытие формул — механика «Классики». Cloze-пропуски
  /// по-прежнему управляются [revealed].
  final bool showAllFormulas;
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстрации по `media.id` (7.14).
  final Map<String, MediaMetadata> mediaMetadata;

  /// Повтор чтения медиа карточки, если файл/байты не нашлись (7.19).
  final VoidCallback? onRetryMedia;

  /// Сторона вопроса (лицевая): `side` — front или неизвестная строка.
  bool get _isQuestionSide => side != card.back || side == card.front;

  /// Идентификаторы изображений выбранной стороны.
  List<String> get _sideMediaIds =>
      _isQuestionSide ? card.questionMediaIds : card.answerMediaIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = side == card.back
        ? theme.textTheme.bodyLarge?.copyWith(height: 1.6)
        : theme.textTheme.headlineMedium;
    final occlusionJson = card.occlusionJson;

    final content = <Widget>[];
    // Occlusion-иллюстрация — общий холст обеих сторон: маски управляются
    // `revealed`, а не выбором стороны (иначе переворот терял бы маски).
    if (occlusionJson != null) {
      final String? imageId = card.questionMediaIds.isEmpty
          ? null
          : card.questionMediaIds.first;
      final image = imageId == null ? null : mediaBytes[imageId];
      if (image == null) {
        content.add(
          _ImageUnavailable(
            imageKey: imageId == null
                ? const ValueKey<String>('occlusion-image-unavailable')
                : ValueKey<String>('card-image-unavailable-$imageId'),
            message: AppLocalizations.of(context).occlusionImageUnavailable,
            onRetry: onRetryMedia,
            retryKey: imageId == null
                ? const ValueKey<String>('occlusion-image-retry')
                : ValueKey<String>('card-image-retry-$imageId'),
          ),
        );
      } else {
        content.add(
          OcclusionImageView(
            bytes: image,
            occlusionJson: occlusionJson,
            revealed: revealed,
          ),
        );
      }
      content.add(const SizedBox(height: 12));
    } else {
      for (final String imageId in _sideMediaIds) {
        final image = mediaBytes[imageId];
        final metadata = mediaMetadata[imageId];
        if (image == null) {
          content.add(
            _ImageUnavailable(
              imageKey: ValueKey<String>('card-image-unavailable-$imageId'),
              message: AppLocalizations.of(context).cardImageUnavailable,
              onRetry: onRetryMedia,
              retryKey: ValueKey<String>('card-image-retry-$imageId'),
            ),
          );
        } else {
          content.add(
            CardImageView(
              key: ValueKey<String>('card-image-$imageId'),
              bytes: image,
              kind: metadata?.kind ?? GeneratedCardImageKind.photo,
              metadata: metadata,
              onRetry: onRetryMedia,
            ),
          );
        }
        content.add(const SizedBox(height: 12));
      }
    }

    final text = _displayText();
    if (text.isNotEmpty) {
      if (card.cardType == CardType.cloze && text.contains('{{')) {
        content.add(
          DefaultTextStyle.merge(
            style: style,
            textAlign: TextAlign.center,
            child: ClozeText(source: text, revealed: revealed),
          ),
        );
      } else {
        content.add(
          LatexText(source: text, revealed: revealed || showAllFormulas),
        );
      }
    }
    if (content.isEmpty) {
      content.add(SizedBox(key: faceKey));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: content,
    );
  }

  String _displayText() {
    if (card.cardType == CardType.cloze && side == card.back) {
      final note = card.back.trim();
      return note.isEmpty ? card.front : '${card.front}\n\n$note';
    }
    var text = side;
    final latex = card.latex;
    if (side == card.back && latex != null && !text.contains(latex)) {
      text = text.isEmpty ? latex : '$text\n\n$latex';
    }
    return text;
  }
}

/// Явное состояние «изображение недоступно»: без подмены и без скелетона.
class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable({
    required this.imageKey,
    required this.message,
    required this.onRetry,
    required this.retryKey,
  });

  final Key imageKey;
  final String message;
  final VoidCallback? onRetry;
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      key: imageKey,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(kCardImageCornerRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.image_not_supported_outlined,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: retryKey,
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
        ],
      ),
    );
  }
}
