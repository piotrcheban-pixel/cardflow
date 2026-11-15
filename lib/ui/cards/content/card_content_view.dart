import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';
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
    super.key,
  });

  final Card card;
  final String side;
  final bool revealed;
  final ValueKey<String> faceKey;
  final Map<String, Uint8List> mediaBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = side == card.back
        ? theme.textTheme.bodyLarge?.copyWith(height: 1.6)
        : theme.textTheme.headlineMedium;
    final imageId = card.mediaIds.isEmpty ? null : card.mediaIds.first;
    final image = imageId == null ? null : mediaBytes[imageId];
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
      // Обычная карточка с иллюстрацией из поиска (итерация 7.9).
      content.add(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 240),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              image,
              key: const ValueKey<String>('card-content-image'),
              fit: BoxFit.contain,
              errorBuilder: (BuildContext context, Object error, _) =>
                  const SizedBox.shrink(),
            ),
          ),
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
        content.add(LatexText(source: text, revealed: revealed));
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
