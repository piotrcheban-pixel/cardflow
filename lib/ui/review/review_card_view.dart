import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/card.dart' as domain;
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Длительность переворота карточки (SPEC A7.2, аудит D1: 250–350 мс).
const Duration kReviewCardFlipDuration = Duration(milliseconds: 300);

/// Карточка классического режима и тренировки (SPEC A7.2, аудит D1–D3).
///
/// Композиция (находки D1–D3 аудита):
/// * карточка занимает основную часть области экрана — высоту, которую дал
///   родитель, и ширину до `AppSizes.studyCardMaxWidth`; длинный текст
///   прокручивается **внутри** карточки с индикатором, а не обрезается;
/// * до раскрытия виден вопрос крупным кеглем (24–32 px);
/// * после раскрытия видны **обе** стороны: вопрос приглушённо сверху, ответ
///   акцентом ниже (18–22 px) — проверить, на что отвечал, можно, не
///   возвращаясь назад;
/// * переворот — 300 мс с 3D-поворотом вокруг вертикальной оси;
/// * изображения занимают долю высоты карточки, несколько — сеткой.
///
/// Виджет без бизнес-логики: показывает строки и сообщает о тапе; раскрытие
/// ответа — состояние движка сессии.
class ReviewCardView extends StatefulWidget {
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

  /// Полная карточка для разметки итерации 5; optional для прежних вызовов.
  final domain.Card? card;

  /// Байты изображений по `media.id`.
  final Map<String, Uint8List> mediaBytes;

  /// Атрибуция и вид иллюстраций по `media.id` (7.14).
  final Map<String, MediaMetadata> mediaMetadata;

  /// Повтор чтения медиа карточки, если файл/байты не нашлись (7.19).
  final VoidCallback? onRetryMedia;

  /// Контроллер прокрутки содержимого карточки (клавиатура сессии).
  ///
  /// Аудит v2 (D1): на низком окне длинный вопрос не влезает в карточку —
  /// колесо мыши прокручивает, но клавиатура не могла. Сессия передаёт свой
  /// контроллер, чтобы PageUp/PageDown/↑/↓/Home/End прокручивали карточку.
  final ScrollController? scrollController;

  @override
  State<ReviewCardView> createState() => _ReviewCardViewState();
}

class _ReviewCardViewState extends State<ReviewCardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kReviewCardFlipDuration,
    value: widget.revealed ? 1 : 0,
  );

  ScrollController? _internalScroll;

  ScrollController get _scroll =>
      widget.scrollController ?? (_internalScroll ??= ScrollController());

  @override
  void didUpdateWidget(ReviewCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealed == widget.revealed) return;
    if (widget.revealed) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _internalScroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : AppSizes.studyCardMaxWidth;
        final double height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420;
        final bool narrow = width < 560;
        // Аудит v2 (D1): на низком окне (800×600 при 150 % = 533×400) карточка
        // получает 130–220 лог. px — уменьшаем кегль и отступы, чтобы вопрос
        // читался целиком, а не обрезался краем.
        final bool tight = height < 320;
        final double questionSize = tight
            ? (narrow ? 20 : 22)
            : (narrow ? 24 : 28);
        final double answerSize = tight ? 16 : (narrow ? 18 : 19);
        final double imageMaxHeight = math.max(120, height * 0.45);
        final EdgeInsets padding = EdgeInsets.symmetric(
          horizontal: tight
              ? AppSpacing.md
              : (narrow ? AppSpacing.lg : AppSpacing.xxl),
          vertical: tight
              ? AppSpacing.xs
              : (narrow ? AppSpacing.lg : AppSpacing.xl),
        );
        return AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double value = _controller.value.clamp(0.0, 1.0);
            final bool showBack = value >= 0.5;
            final Matrix4 transform = Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(math.pi * value);
            final Widget face = showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _buildRevealed(
                      context,
                      theme,
                      questionSize: questionSize,
                      answerSize: answerSize,
                      imageMaxHeight: imageMaxHeight,
                      padding: padding,
                    ),
                  )
                : _buildQuestion(
                    context,
                    theme,
                    questionSize: questionSize,
                    imageMaxHeight: imageMaxHeight,
                    padding: padding,
                  );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Transform(
                alignment: Alignment.center,
                transform: transform,
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: showBack
                      ? '${widget.front}\n${widget.back}'
                      : widget.front,
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: AppRadii.cardRadius,
                      border: Border.all(
                        color: scheme.outlineVariant,
                        width: AppSizes.borderWidth,
                      ),
                      boxShadow: AppShadows.card(theme.brightness),
                    ),
                    child: face,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Лицевая сторона: вопрос крупным кеглем по центру области.
  Widget _buildQuestion(
    BuildContext context,
    ThemeData theme, {
    required double questionSize,
    required double imageMaxHeight,
    required EdgeInsets padding,
  }) {
    return _ScrollableCardBody(
      scroll: _scroll,
      padding: padding,
      key: const ValueKey<String>('review-card-question-body'),
      children: <Widget>[
        _SideLabel(label: AppLocalizations.of(context).reviewQuestionLabel),
        const SizedBox(height: AppSpacing.sm),
        _content(
          theme,
          context,
          side: widget.front,
          revealed: false,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: questionSize,
            height: 1.4,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
          media: true,
          imageMaxHeight: imageMaxHeight,
        ),
      ],
    );
  }

  /// Обратная сторона: вопрос приглушённо + ответ акцентом (находка D3).
  Widget _buildRevealed(
    BuildContext context,
    ThemeData theme, {
    required double questionSize,
    required double answerSize,
    required double imageMaxHeight,
    required EdgeInsets padding,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle mutedQuestion = theme.textTheme.titleLarge!.copyWith(
      fontSize: math.max(18, questionSize * 0.72),
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    );
    final TextStyle answerStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: answerSize,
      height: 1.65,
      color: scheme.onSurface,
    );
    final bool occlusion = widget.card?.occlusionJson != null;
    return _ScrollableCardBody(
      scroll: _scroll,
      padding: padding,
      key: const ValueKey<String>('review-card-answer-body'),
      children: <Widget>[
        _SideLabel(label: l10n.reviewQuestionLabel),
        const SizedBox(height: AppSpacing.xs),
        _content(
          theme,
          context,
          side: widget.front,
          revealed: true,
          style: mutedQuestion,
          // Холст occlusion-карточки рисуется на стороне вопроса с уже
          // раскрытыми масками (revealed: true).
          media: true,
          imageMaxHeight: imageMaxHeight * 0.55,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Divider(height: 1, color: scheme.outlineVariant),
        ),
        _SideLabel(label: l10n.reviewAnswerLabel, accent: true),
        const SizedBox(height: AppSpacing.xs),
        _content(
          theme,
          context,
          side: widget.back,
          revealed: true,
          style: answerStyle,
          // Для occlusion холст уже нарисован выше — второй раз не рисуем;
          // для cloze вопрос показан выше, повторять его в ответе не нужно.
          media: !occlusion,
          includeClozeFront: false,
          imageMaxHeight: imageMaxHeight * 0.55,
        ),
      ],
    );
  }

  Widget _content(
    ThemeData theme,
    BuildContext context, {
    required String side,
    required bool revealed,
    required TextStyle? style,
    required bool media,
    required double imageMaxHeight,
    bool includeClozeFront = true,
  }) {
    final domain.Card? card = widget.card;
    if (card == null) {
      return Text(
        side,
        key: const ValueKey<String>('review-card-face'),
        textAlign: TextAlign.center,
        style: style,
      );
    }
    return CardContentView(
      card: card,
      side: side,
      revealed: revealed,
      faceKey: const ValueKey<String>('review-card-face'),
      questionStyle: style,
      answerStyle: style,
      mediaBytes: widget.mediaBytes,
      mediaMetadata: widget.mediaMetadata,
      onRetryMedia: widget.onRetryMedia,
      showMedia: media,
      includeClozeFront: includeClozeFront,
      imageMaxHeight: imageMaxHeight,
      imageMaxWidth: AppSizes.studyCardMaxWidth,
    );
  }
}

/// Подпись стороны карточки («Вопрос»/«Ответ»).
class _SideLabel extends StatelessWidget {
  const _SideLabel({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        label.toUpperCase(),
        style: AppTypography.overline(
          context,
          color: accent
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Тело карточки: короткий текст центрируется, длинный — прокручивается
/// внутри карточки с видимым индикатором (находки D2/D1: ничего не обрезается
/// молча, наличие прокрутки очевидно).
class _ScrollableCardBody extends StatefulWidget {
  const _ScrollableCardBody({
    required this.scroll,
    required this.padding,
    required this.children,
    super.key,
  });

  final ScrollController scroll;
  final EdgeInsets padding;
  final List<Widget> children;

  @override
  State<_ScrollableCardBody> createState() => _ScrollableCardBodyState();
}

class _ScrollableCardBodyState extends State<_ScrollableCardBody> {
  /// Показывать ли постоянно индикатор прокрутки (контент не влезает).
  bool _canScroll = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (ScrollMetricsNotification notification) {
            final bool canScroll = notification.metrics.maxScrollExtent > 0.5;
            if (canScroll != _canScroll) {
              // Уведомление приходит во время layout — setState только после
              // кадра, иначе Flutter остановит сборку.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && canScroll != _canScroll) {
                  setState(() => _canScroll = canScroll);
                }
              });
            }
            return false;
          },
          child: Scrollbar(
            controller: widget.scroll,
            thumbVisibility: _canScroll,
            child: SingleChildScrollView(
              controller: widget.scroll,
              padding: widget.padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0,
                    constraints.maxHeight - widget.padding.vertical,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
