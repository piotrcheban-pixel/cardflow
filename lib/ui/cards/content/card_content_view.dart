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
class CardContentView extends StatelessWidget {
  const CardContentView({
    required this.card,
    required this.side,
    required this.revealed,
    required this.faceKey,
    this.mediaBytes = const <String, Uint8List>{},
    this.mediaMetadata = const <String, MediaMetadata>{},
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = side == card.back
        ? theme.textTheme.bodyLarge?.copyWith(height: 1.6)
        : theme.textTheme.headlineMedium;
    final imageId = card.mediaIds.isEmpty ? null : card.mediaIds.first;
    final image = imageId == null ? null : mediaBytes[imageId];
    final metadata = imageId == null ? null : mediaMetadata[imageId];
    final occlusionJson = card.occlusionJson;

    final content = <Widget>[];
    if (occlusionJson != null) {
      if (image == null) {
        content.add(
          Text(
            AppLocalizations.of(context).occlusionImageUnavailable,
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
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
      if (content.isNotEmpty) content.add(const SizedBox(height: 12));
    } else if (image != null) {
      // Иллюстрация карточки (7.9/7.14): 16:9 (схема 4:3), ограничение высоты,
      // тап — полноэкранный просмотр с зумом и атрибуцией.
      content.add(
        CardImageView(
          bytes: image,
          kind: metadata?.kind ?? GeneratedCardImageKind.photo,
          metadata: metadata,
        ),
      );
      content.add(const SizedBox(height: 12));
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
