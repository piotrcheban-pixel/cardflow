import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Угол скругления картинки карточки: токен формы M3 «large» (16).
///
/// В проекте нет отдельного расширения темы с радиусами; M3-токен large
/// (16) используется здесь и в полноэкранном просмотре.
const double kCardImageCornerRadius = 16;

/// Ограничение высоты картинки в карточке: текст и LaTeX не вытесняются.
const double kCardImageMaxHeight = 220;

/// Картинка карточки: пропорции 16:9, скругление, fade-in и скелетон.
///
/// `photo`/`illustration` показываются `BoxFit.cover`, `diagram` — `contain`
/// на нейтральном фоне (схемы нельзя обрезать). Тап открывает полноэкранный
/// просмотр с зумом и атрибуцией. Картинка ограничена по высоте и ширине,
/// поэтому длинный вопрос/формула сохраняют место, а прокрутка не ломается.
class CardImageView extends StatelessWidget {
  /// Создаёт изображение.
  const CardImageView({
    required this.bytes,
    this.kind = GeneratedCardImageKind.photo,
    this.metadata,
    this.onTap,
    this.maxHeight = kCardImageMaxHeight,
    this.semanticsLabel,
    super.key,
  });

  /// Байты изображения.
  final Uint8List bytes;

  /// Вид иллюстрации (от него зависят пропорции и fit).
  final GeneratedCardImageKind kind;

  /// Метаданные атрибуции (провайдер, автор, лицензия, заглушка).
  final MediaMetadata? metadata;

  /// Тап по картинке; `null` — открыть стандартный полноэкранный просмотр.
  final VoidCallback? onTap;

  /// Максимальная высота на экране.
  final double maxHeight;

  /// Подпись для screen reader; `null` — стандартная из ARB.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final MediaMetadata? meta = metadata;
    final bool isDiagram = kind == GeneratedCardImageKind.diagram;
    final String label =
        semanticsLabel ??
        (meta?.isPlaceholder ?? false
            ? l10n.cardImagePlaceholderSemantics
            : l10n.cardImageSemantics);
    return Semantics(
      image: true,
      label: label,
      button: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
        child: AspectRatio(
          // Схемы — 4:3 (допустимо правилом), остальное — 16:9.
          aspectRatio: isDiagram ? 4 / 3 : 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kCardImageCornerRadius),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap:
                    onTap ??
                    () => showCardImageFullscreen(
                      context,
                      bytes: bytes,
                      kind: kind,
                      metadata: meta,
                    ),
                child: Image.memory(
                  bytes,
                  key: const ValueKey<String>('card-image'),
                  fit: isDiagram ? BoxFit.contain : BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder:
                      (
                        BuildContext context,
                        Widget child,
                        int? frame,
                        bool wasSynchronouslyLoaded,
                      ) {
                        if (wasSynchronouslyLoaded) return child;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: frame == null
                              ? const _ImageSkeleton()
                              : SizedBox.expand(child: child),
                        );
                      },
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stack,
                  ) => const _ImageSkeleton(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Скелетон загрузки/декодирования картинки.
class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 40,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// Полноэкранный просмотр картинки: зум и атрибуция (автор, лицензия).
Future<void> showCardImageFullscreen(
  BuildContext context, {
  required Uint8List bytes,
  GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
  MediaMetadata? metadata,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final MediaMetadata? meta = metadata;
  final String? attribution = meta?.attributionLine;
  final String? sourceUrl = meta?.sourceUrl;
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (BuildContext dialogContext) => Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: InteractiveViewer(
                key: const ValueKey<String>('card-image-fullscreen'),
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stack,
                    ) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                key: const ValueKey<String>('card-image-fullscreen-close'),
                tooltip: l10n.cardImageFullscreenClose,
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            if (attribution != null || sourceUrl != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          l10n.cardImageFullscreenTitle,
                          style: Theme.of(dialogContext).textTheme.labelLarge
                              ?.copyWith(color: Colors.white70),
                        ),
                        if (attribution != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            l10n.cardImageAttribution(attribution),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                        if (sourceUrl != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            l10n.cardImageSourceUrl(sourceUrl),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
