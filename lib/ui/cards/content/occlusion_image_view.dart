import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/motion.dart';

/// Изображение и интерактивные маски Occlusion (REDESIGN-SPEC §9.20).
///
/// Маска — `ink5` 94 % с тонкой рамкой `aurumSoft` и номером; раскрытие —
/// fade + scale 1,04 на `effects` и ✋ `selectionClick`. Кнопки
/// «Показать все» / «Скрыть все» — ghost `s` под изображением, невалидная
/// разметка — бейдж `amber`.
class OcclusionImageView extends StatefulWidget {
  /// Создаёт вид изображения с масками.
  const OcclusionImageView({
    required this.bytes,
    required this.occlusionJson,
    required this.revealed,
    super.key,
  });

  /// Байты изображения.
  final Uint8List bytes;

  /// JSON документа масок (v1).
  final String occlusionJson;

  /// Раскрыты ли все маски снаружи (ответ показан).
  final bool revealed;

  @override
  State<OcclusionImageView> createState() => _OcclusionImageViewState();
}

class _OcclusionImageViewState extends State<OcclusionImageView> {
  Set<String> _shown = <String>{};
  double _aspectRatio = 1;

  @override
  void initState() {
    super.initState();
    _shown = widget.revealed ? _allMaskIds() : <String>{};
    _readImageSize();
  }

  @override
  void didUpdateWidget(OcclusionImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) _readImageSize();
    if (oldWidget.occlusionJson != widget.occlusionJson) {
      _shown = <String>{};
    } else if (oldWidget.revealed != widget.revealed) {
      _shown = widget.revealed ? _allMaskIds() : <String>{};
    }
  }

  Set<String> _allMaskIds() {
    final OcclusionDocument? document = OcclusionDocument.tryParse(
      widget.occlusionJson,
    );
    return document == null
        ? <String>{}
        : <String>{for (final OcclusionMask mask in document.masks) mask.id};
  }

  Future<void> _readImageSize() async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(widget.bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final double ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted && ratio.isFinite && ratio > 0) {
        setState(() => _aspectRatio = ratio);
      }
    } on Object {
      // Image.memory displays the localized fallback below if decoding fails.
    }
  }

  void _toggleMask(String id) {
    NcHaptics.of(context).selectionClick();
    setState(() {
      if (!_shown.add(id)) _shown.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final OcclusionDocument? document = OcclusionDocument.tryParse(
      widget.occlusionJson,
    );
    if (document == null || document.masks.isEmpty) {
      return NcBadge(
        key: const ValueKey<String>('occlusion-invalid'),
        label: l10n.occlusionInvalid,
        tone: NcBadgeTone.amber,
      );
    }
    final Set<String> shown = _shown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 360),
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(NcRadii.m),
              child: ColoredBox(
                color: theme.colors.ink3,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) =>
                      Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Image.memory(
                            widget.bytes,
                            fit: BoxFit.fill,
                            errorBuilder:
                                (
                                  BuildContext context,
                                  Object error,
                                  StackTrace? stack,
                                ) => Center(
                                  child: Text(l10n.occlusionImageUnavailable),
                                ),
                          ),
                          for (
                            var index = 0;
                            index < document.masks.length;
                            index++
                          )
                            if (!shown.contains(document.masks[index].id))
                              _PositionedMask(
                                mask: document.masks[index],
                                number: index + 1,
                                canvas: constraints.biggest,
                                onTap: () =>
                                    _toggleMask(document.masks[index].id),
                              ),
                        ],
                      ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            NcButton(
              key: const ValueKey<String>('occlusion-show-all'),
              label: l10n.occlusionShowAll,
              variant: NcButtonVariant.ghost,
              size: NcButtonSize.s,
              onPressed: () => setState(
                () => _shown = <String>{
                  for (final OcclusionMask mask in document.masks) mask.id,
                },
              ),
            ),
            NcButton(
              key: const ValueKey<String>('occlusion-hide-all'),
              label: l10n.occlusionHideAll,
              variant: NcButtonVariant.ghost,
              size: NcButtonSize.s,
              onPressed: () => setState(() => _shown = <String>{}),
            ),
          ],
        ),
      ],
    );
  }
}

/// Одна маска: `ink5` 94 %, рамка `aurumSoft`, номер; раскрытие — fade+scale.
class _PositionedMask extends StatelessWidget {
  const _PositionedMask({
    required this.mask,
    required this.number,
    required this.canvas,
    required this.onTap,
  });

  final OcclusionMask mask;
  final int number;
  final Size canvas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool ellipse = mask.shape == OcclusionShape.ellipse;
    final String numberLabel = '$number';
    return Positioned(
      left: canvas.width * mask.x,
      top: canvas.height * mask.y,
      width: canvas.width * mask.width,
      height: canvas.height * mask.height,
      child: GestureDetector(
        key: ValueKey<String>('occlusion-cover-${mask.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.96, end: 1),
          duration: AppMotion.base,
          curve: AppMotion.baseCurve,
          builder: (BuildContext context, double scale, Widget? child) =>
              Transform.scale(scale: scale, child: child),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: theme.colors.ink5.withValues(alpha: 0.94),
              shape: ellipse
                  ? OvalBorder(side: BorderSide(color: theme.colors.aurumSoft))
                  : RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: theme.colors.aurumSoft),
                    ),
            ),
            child: Center(
              child: Text(
                numberLabel,
                style: theme.typography.labelM.copyWith(
                  color: theme.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
