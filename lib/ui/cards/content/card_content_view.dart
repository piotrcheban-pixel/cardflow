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
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Единый рендер карточки для классики и ленты (ADR-017).
///
/// Итерация 7.19 (ADR-042): изображения выбираются **по стороне** — до
/// переворота видны только `questionMediaIds`, после — только
/// `answerMediaIds`. Раньше `mediaIds.first` рисовался на обеих сторонах, и
/// изображение с ответом раскрывало его на лицевой стороне.
///
/// Аудит 1.0 (находки D1–D3): раскрытая карточка показывает **обе** стороны —
/// вопрос приглушённо сверху и ответ ниже. Размер изображения и сетка
/// нескольких картинок стали параметрами, чтобы экран сессии мог отдать
/// картинке долю высоты карточки и не ломать пропорции.
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
    this.questionStyle,
    this.answerStyle,
    this.showMedia = true,
    this.includeClozeFront = true,
    this.imageMaxHeight = kCardImageMaxHeight,
    this.imageMaxWidth = kCardImageMaxWidth,
    this.sideBySide = false,
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

  /// Базовый стиль вопроса; `null` — `headlineMedium` темы.
  final TextStyle? questionStyle;

  /// Базовый стиль ответа; `null` — `bodyLarge` темы.
  final TextStyle? answerStyle;

  /// Рисовать ли изображения стороны (в раскрытой карточке ответ для
  /// occlusion-карточки уже нарисован холстом вопроса).
  final bool showMedia;

  /// Для cloze-ответа: добавлять ли текст вопроса перед примечанием ответа.
  ///
  /// В раскрытой карточке вопрос уже показан выше, поэтому повтор не нужен.
  final bool includeClozeFront;

  /// Максимальная высота изображения стороны.
  final double imageMaxHeight;

  /// Максимальная ширина изображения стороны.
  final double imageMaxWidth;

  /// На широкой карточке изображение и текст стоят рядом (F08/V7).
  ///
  /// На 2K/FullHD текстовая колонка занимает 5 частей, изображение — 4; так
  /// картинка получает полную высоту контента, не срезается и занимает
  /// ≥35 % контентной площади, а строки остаются в 45–75 знаках.
  final bool sideBySide;

  /// Сторона вопроса (лицевая): `side` — front или неизвестная строка.
  bool get _isQuestionSide => side != card.back || side == card.front;

  /// Идентификаторы изображений выбранной стороны.
  List<String> get _sideMediaIds =>
      _isQuestionSide ? card.questionMediaIds : card.answerMediaIds;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle resolvedQuestionStyle =
        questionStyle ??
        theme.textTheme.headlineMedium ??
        const TextStyle(fontSize: 28, height: 1.35);
    final TextStyle resolvedAnswerStyle =
        answerStyle ??
        theme.textTheme.bodyLarge?.copyWith(height: 1.6) ??
        const TextStyle(fontSize: 19, height: 1.6);
    final TextStyle style = side == card.back
        ? resolvedAnswerStyle
        : resolvedQuestionStyle;
    final String? occlusionJson = card.occlusionJson;

    final List<Widget> content = <Widget>[];
    final List<Widget> mediaContent = <Widget>[];
    // Occlusion-иллюстрация — общий холст обеих сторон: маски управляются
    // `revealed`, а не выбором стороны (иначе переворот терял бы маски).
    if (occlusionJson != null) {
      if (showMedia) {
        final String? imageId = card.questionMediaIds.isEmpty
            ? null
            : card.questionMediaIds.first;
        final Uint8List? image = imageId == null ? null : mediaBytes[imageId];
        if (image == null) {
          mediaContent.add(
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
          mediaContent.add(
            OcclusionImageView(
              bytes: image,
              occlusionJson: occlusionJson,
              revealed: revealed,
            ),
          );
        }
      }
    } else if (showMedia) {
      mediaContent.addAll(_buildMedia(context));
    }

    final String text = _displayText();
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
        // Стиль карточки передаётся через DefaultTextStyle: LatexText/Text
        // наследуют его, поэтому вопрос и ответ имеют кегль сессии, а не
        // ambient bodyMedium (находки D1/A2 аудита).
        content.add(
          DefaultTextStyle.merge(
            style: style,
            textAlign: TextAlign.center,
            child: LatexText(
              source: text,
              revealed: revealed || showAllFormulas,
            ),
          ),
        );
      }
    }
    if (content.isEmpty) {
      content.add(SizedBox(key: faceKey));
    }
    // F08/V7: на широкой карточке с изображением — «текст + картинка» рядом.
    // Изображение получает полную высоту тела карточки (minHeight), поэтому
    // не срезается и занимает заметную долю контентной площади; текст — в
    // читаемой колонке 5:4.
    if (sideBySide &&
        mediaContent.isNotEmpty &&
        content.isNotEmpty &&
        occlusionJson == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: imageMaxHeight.isFinite && imageMaxHeight > 0
              ? imageMaxHeight
              : 0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 5,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: mediaContent,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[...mediaContent, ...content],
    );
  }

  /// Изображения стороны: одно — во всю ширину, несколько — сеткой по два.
  ///
  /// Находка D1 аудита: картинка должна занимать заметную долю карточки и не
  /// искажаться; несколько изображений — сетка, а не бесконечная колонка.
  List<Widget> _buildMedia(BuildContext context) {
    final List<String> ids = _sideMediaIds;
    if (ids.isEmpty) return const <Widget>[];
    final List<Widget> tiles = <Widget>[
      for (final String imageId in ids)
        _sideImageTile(context, imageId, ids.length),
    ];
    if (ids.length == 1) {
      return <Widget>[tiles.single, const SizedBox(height: 12)];
    }
    return <Widget>[
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double cell = width.isFinite && width > 0
              ? (width - 8) / 2
              : imageMaxWidth / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final Widget tile in tiles)
                SizedBox(width: cell, child: tile),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _sideImageTile(BuildContext context, String imageId, int count) {
    final Uint8List? image = mediaBytes[imageId];
    if (image == null) {
      return _ImageUnavailable(
        imageKey: ValueKey<String>('card-image-unavailable-$imageId'),
        message: AppLocalizations.of(context).cardImageUnavailable,
        onRetry: onRetryMedia,
        retryKey: ValueKey<String>('card-image-retry-$imageId'),
      );
    }
    final MediaMetadata? metadata = mediaMetadata[imageId];
    return CardImageView(
      key: ValueKey<String>('card-image-$imageId'),
      bytes: image,
      kind: metadata?.kind ?? GeneratedCardImageKind.photo,
      metadata: metadata,
      onRetry: onRetryMedia,
      maxWidth: imageMaxWidth,
      // F08: в сетке плитка получает большую высоту (75 % бюджета), чтобы
      // изображение занимало заметную площадь, а пустых полей не было видно.
      maxHeight: count > 1 ? imageMaxHeight * 0.75 : imageMaxHeight,
    );
  }

  String _displayText() {
    if (card.cardType == CardType.cloze && side == card.back) {
      final String note = card.back.trim();
      if (note.isEmpty || !includeClozeFront) return note;
      return '${card.front}\n\n$note';
    }
    String text = side;
    final String? latex = card.latex;
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
