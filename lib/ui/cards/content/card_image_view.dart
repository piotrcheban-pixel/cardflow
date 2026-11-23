import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/images/image_dimensions.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Угол скругления картинки карточки: токен формы M3 «large» (16).
///
/// В проекте нет отдельного расширения темы с радиусами; M3-токен large
/// (16) используется здесь и в полноэкранном просмотре.
const double kCardImageCornerRadius = 16;

/// Ограничение высоты картинки в карточке: текст и LaTeX не вытесняются.
const double kCardImageMaxHeight = 220;

/// Ограничение ширины картинки по умолчанию (прежнее поведение карточки).
const double kCardImageMaxWidth = 640;

/// Ключ явного состояния ошибки декодирования.
const ValueKey<String> kCardImageErrorKey = ValueKey<String>(
  'card-image-error',
);

/// Ключ кнопки повтора загрузки/декодирования.
const ValueKey<String> kCardImageRetryKey = ValueKey<String>(
  'card-image-retry',
);

/// Картинка карточки: пропорции по факту файла, скругление, fade-in.
///
/// Аудит v7 (G4/V7-04/G11): раньше рамка была жёстко 16:9 (4:3 для схем), а
/// `photo`/`illustration` рисовались `BoxFit.cover` — фото 960×720 теряло 25 %
/// высоты, 960×1371 — 60 %. Теперь:
///
/// * **все** виды изображений вписываются целиком (`BoxFit.contain`) —
///   пользовательскую иллюстрацию нельзя обрезать;
/// * размер коробки считается из фактических пропорций файла
///   ([ImageDimensions.read]) и бюджета `maxWidth × maxHeight`, поэтому рамка
///   не добавляет пустых полей и маленькая картинка не выглядит «маркой»;
/// * вид изображения (`kind`) больше не меняет геометрию — он остаётся в
///   метаданных для атрибуции (и в полноэкранном просмотре).
///
/// Тап открывает полноэкранный просмотр с зумом и атрибуцией.
///
/// Итерация 7.19 (ADR-041): ошибка декодирования — **явное** состояние с
/// кнопкой повтора, а не скелетон загрузки и не подмена другой картинкой.
class CardImageView extends StatefulWidget {
  /// Создаёт изображение.
  const CardImageView({
    required this.bytes,
    this.kind = GeneratedCardImageKind.photo,
    this.metadata,
    this.onTap,
    this.onRetry,
    this.maxHeight = kCardImageMaxHeight,
    this.maxWidth = kCardImageMaxWidth,
    this.semanticsLabel,
    super.key,
  });

  /// Байты изображения.
  final Uint8List bytes;

  /// Вид иллюстрации (от него зависят пропорции и fit).
  final GeneratedCardImageKind kind;

  /// Метаданные атрибуции (провайдер, автор, лицензия).
  final MediaMetadata? metadata;

  /// Тап по картинке; `null` — открыть стандартный полноэкранный просмотр.
  final VoidCallback? onTap;

  /// Повтор декодирования после ошибки; `null` — кнопки повтора нет.
  final VoidCallback? onRetry;

  /// Максимальная высота на экране.
  final double maxHeight;

  /// Максимальная ширина на экране.
  final double maxWidth;

  /// Подпись для screen reader; `null` — стандартная из ARB.
  final String? semanticsLabel;

  @override
  State<CardImageView> createState() => _CardImageViewState();
}

class _CardImageViewState extends State<CardImageView> {
  /// Номер попытки: новый ключ `Image` заставляет декодировать байты заново.
  int _attempt = 0;

  void _retry() {
    final VoidCallback? onRetry = widget.onRetry;
    setState(() => _attempt++);
    onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final MediaMetadata? meta = widget.metadata;
    final String label = widget.semanticsLabel ?? l10n.cardImageSemantics;
    // Аудит v7 (G4): никакой cover-обрезки и рамки 16:9 «на всякий случай».
    // Пропорции берутся из заголовка файла ([ImageDimensions]), а размер
    // коробки подбирается так, чтобы изображение целиком влезло в бюджет
    // `maxWidth × maxHeight` и при этом было крупным (маленький файл
    // масштабируется до бюджета, а не рисуется «почтовой маркой»).
    final ImageDimensions? dimensions = widget.bytes.isEmpty
        ? null
        : ImageDimensions.read(widget.bytes);
    final double aspect =
        dimensions == null || dimensions.width <= 0 || dimensions.height <= 0
        ? 16 / 9
        : dimensions.width / dimensions.height;
    final double maxWidth = widget.maxWidth > 0
        ? widget.maxWidth
        : kCardImageMaxWidth;
    final double maxHeight = widget.maxHeight > 0
        ? widget.maxHeight
        : kCardImageMaxHeight;
    final double width = math.min(maxWidth, maxHeight * aspect);
    final double height = width / aspect;
    // Появление картинки — из общей шкалы и с учётом reduced motion (G9).
    final Duration fadeDuration = AppMotion.duration(
      context,
      AppDurations.base,
    );
    return Semantics(
      image: true,
      label: label,
      button: true,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kCardImageCornerRadius),
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            child: widget.bytes.isEmpty
                ? _ImageErrorState(onRetry: _retry)
                : InkWell(
                    onTap:
                        widget.onTap ??
                        () => showCardImageFullscreen(
                          context,
                          bytes: widget.bytes,
                          kind: widget.kind,
                          metadata: meta,
                        ),
                    child: Image.memory(
                      widget.bytes,
                      key: ValueKey<String>('card-image-attempt-$_attempt'),
                      // G4: пользовательское изображение никогда не обрезается.
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      frameBuilder:
                          (
                            BuildContext context,
                            Widget child,
                            int? frame,
                            bool wasSynchronouslyLoaded,
                          ) {
                            if (wasSynchronouslyLoaded ||
                                fadeDuration == Duration.zero) {
                              return child;
                            }
                            return AnimatedSwitcher(
                              duration: fadeDuration,
                              child: frame == null
                                  ? const _ImageSkeleton()
                                  : SizedBox.expand(child: child),
                            );
                          },
                      errorBuilder: (
                        BuildContext context,
                        Object error,
                        StackTrace? stack,
                      ) => _ImageErrorState(onRetry: _retry),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Явное состояние ошибки: иконка, сообщение и повтор.
class _ImageErrorState extends StatelessWidget {
  const _ImageErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      key: kCardImageErrorKey,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.cardImageLoadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            TextButton(
              key: kCardImageRetryKey,
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
          ],
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
  final ThemeData theme = Theme.of(context);
  final ColorScheme scheme = theme.colorScheme;
  final MediaMetadata? meta = metadata;
  final String? attribution = meta?.attributionLine;
  final String? sourceUrl = meta?.sourceUrl;
  // Аудит v4 (V26/A18): фон — роли темы вместо литерального чёрного, кнопка
  // закрытия — контрастная (surface/onSurface вместо зелёной 1,92:1),
  // переход — fade + scale 0,98 (180 мс, учитывает reduced motion).
  final Duration duration = AppMotion.reduce(context)
      ? Duration.zero
      : AppDurations.base;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.cardImageFullscreenClose,
    barrierColor: scheme.inverseSurface.withValues(alpha: 0.94),
    transitionDuration: duration,
    pageBuilder: (BuildContext dialogContext, _, _) => const SizedBox.shrink(),
    transitionBuilder:
        (
          BuildContext dialogContext,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final CurvedAnimation curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.enter,
            reverseCurve: AppMotion.enter,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
              child: Dialog(
                insetPadding: EdgeInsets.zero,
                backgroundColor: scheme.inverseSurface,
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
                              errorBuilder:
                                  (
                                    BuildContext context,
                                    Object error,
                                    StackTrace? stack,
                                  ) => Text(
                                    l10n.cardImageLoadFailed,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: scheme.onInverseSurface,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: IconButton.filledTonal(
                          key: const ValueKey<String>(
                            'card-image-fullscreen-close',
                          ),
                          tooltip: l10n.cardImageFullscreenClose,
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.surface,
                            foregroundColor: scheme.onSurface,
                            minimumSize: const Size(
                              AppSizes.minTouchTarget,
                              AppSizes.minTouchTarget,
                            ),
                          ),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                      if (attribution != null || sourceUrl != null)
                        Positioned(
                          left: AppSpacing.md,
                          right: AppSpacing.md,
                          bottom: AppSpacing.md,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.inverseSurface.withValues(
                                alpha: 0.88,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppRadii.input,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    l10n.cardImageFullscreenTitle,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: scheme.onInverseSurface.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                  if (attribution != null) ...<Widget>[
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      l10n.cardImageAttribution(attribution),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onInverseSurface,
                                          ),
                                    ),
                                  ],
                                  if (sourceUrl != null) ...<Widget>[
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      l10n.cardImageSourceUrl(sourceUrl),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onInverseSurface
                                                .withValues(alpha: 0.75),
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
            ),
          );
        },
  );
}
