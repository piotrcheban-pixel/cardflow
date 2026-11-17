import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';

/// Редактор масок Image Occlusion (REDESIGN-SPEC §9.4): холст на `ink3`,
/// выбор формы `NcSegmented` (прямоугольник / эллипс), готовая маска —
/// `ink5` 92 % с номером, рисуемая — рамка `aurum` 1,5 px + заливка 18 %.
/// Eager-распознаватель внутри прокрутки сохранён (ретроспектива 5).
class OcclusionMaskEditor extends StatefulWidget {
  /// Создаёт редактор.
  const OcclusionMaskEditor({
    required this.imageBytes,
    required this.document,
    required this.onChanged,
    super.key,
  });

  /// Байты изображения.
  final Uint8List imageBytes;

  /// Текущие маски.
  final OcclusionDocument document;

  /// Изменение документа.
  final ValueChanged<OcclusionDocument> onChanged;

  @override
  State<OcclusionMaskEditor> createState() => _OcclusionMaskEditorState();
}

class _OcclusionMaskEditorState extends State<OcclusionMaskEditor> {
  OcclusionShape _shape = OcclusionShape.rectangle;
  Rect? _draft;
  double _aspectRatio = 4 / 3;

  @override
  void initState() {
    super.initState();
    _readAspect();
  }

  @override
  void didUpdateWidget(OcclusionMaskEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) _readAspect();
  }

  Future<void> _readAspect() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted && ratio.isFinite && ratio > 0) {
        setState(() => _aspectRatio = ratio);
      }
    } on Object {
      // Некорректный файл отобразит Image.memory.errorBuilder.
    }
  }

  void _startAt(Offset position, Size size) {
    _draft = _rect(position, position, size);
  }

  void _updateAt(Offset position, Size size) {
    final start = _draft;
    if (start == null) return;
    setState(() {
      _draft = _rect(
        Offset(start.left * size.width, start.top * size.height),
        position,
        size,
      );
    });
  }

  void _end(Size size) {
    final draft = _draft;
    setState(() => _draft = null);
    if (draft == null || draft.width < 0.02 || draft.height < 0.02) return;
    final id = _nextId();
    widget.onChanged(
      OcclusionDocument(
        masks: List<OcclusionMask>.unmodifiable(<OcclusionMask>[
          ...widget.document.masks,
          OcclusionMask(
            id: id,
            shape: _shape,
            x: draft.left,
            y: draft.top,
            width: draft.width,
            height: draft.height,
          ),
        ]),
      ),
    );
  }

  Rect _rect(Offset start, Offset end, Size size) {
    if (size.width <= 0 || size.height <= 0) return Rect.zero;
    final a = Offset(
      (start.dx / size.width).clamp(0.0, 1.0),
      (start.dy / size.height).clamp(0.0, 1.0),
    );
    final b = Offset(
      (end.dx / size.width).clamp(0.0, 1.0),
      (end.dy / size.height).clamp(0.0, 1.0),
    );
    return Rect.fromLTRB(
      a.dx < b.dx ? a.dx : b.dx,
      a.dy < b.dy ? a.dy : b.dy,
      a.dx < b.dx ? b.dx : a.dx,
      a.dy < b.dy ? b.dy : a.dy,
    );
  }

  String _nextId() {
    final used = <String>{for (final mask in widget.document.masks) mask.id};
    var index = 1;
    while (used.contains('mask-$index')) {
      index++;
    }
    return 'mask-$index';
  }

  void _remove(String id) {
    widget.onChanged(
      OcclusionDocument(
        masks: List<OcclusionMask>.unmodifiable(
          widget.document.masks.where((mask) => mask.id != id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NcSegmented<OcclusionShape>(
          value: _shape,
          onChanged: (OcclusionShape shape) => setState(() => _shape = shape),
          segments: <NcSegment<OcclusionShape>>[
            NcSegment<OcclusionShape>(
              value: OcclusionShape.rectangle,
              label: l10n.occlusionRectangle,
            ),
            NcSegment<OcclusionShape>(
              value: OcclusionShape.ellipse,
              label: l10n.occlusionEllipse,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.occlusionDrawHint,
          style: theme.typography.bodyS.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(NcRadii.l),
              child: ColoredBox(
                color: colors.ink3,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Size size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    // Eager-распознаватель забирает жест у прокрутки формы:
                    // иначе вертикальное начало рисования прокручивало бы
                    // страницу (ретроспектива 5).
                    return RawGestureDetector(
                      gestures: <Type, GestureRecognizerFactory>{
                        EagerGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              EagerGestureRecognizer
                            >(EagerGestureRecognizer.new, (_) {}),
                      },
                      child: Listener(
                        key: const ValueKey<String>('occlusion-editor-canvas'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (PointerDownEvent event) =>
                            _startAt(event.localPosition, size),
                        onPointerMove: (PointerMoveEvent event) =>
                            _updateAt(event.localPosition, size),
                        onPointerUp: (PointerUpEvent event) => _end(size),
                        onPointerCancel: (PointerCancelEvent event) =>
                            setState(() => _draft = null),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Image.memory(
                              widget.imageBytes,
                              fit: BoxFit.fill,
                              errorBuilder:
                                  (
                                    BuildContext context,
                                    Object error,
                                    StackTrace? stack,
                                  ) => ColoredBox(
                                    color: colors.ink3,
                                    child: Center(
                                      child: Text(
                                        l10n.occlusionImageUnavailable,
                                      ),
                                    ),
                                  ),
                            ),
                            for (
                              var index = 0;
                              index < widget.document.masks.length;
                              index++
                            )
                              _MaskCover(
                                mask: widget.document.masks[index],
                                number: index + 1,
                                canvasSize: size,
                              ),
                            if (_draft case final Rect draft)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _DraftPainter(
                                    rect: draft,
                                    shape: _shape,
                                    color: colors.aurum,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < widget.document.masks.length; index++)
          NcListRow(
            title: Text(
              l10n.occlusionMaskNumber(index + 1),
              key: ValueKey<String>(
                'occlusion-editor-mask-${widget.document.masks[index].id}',
              ),
            ),
            subtitle: Text(
              widget.document.masks[index].shape == OcclusionShape.ellipse
                  ? l10n.occlusionEllipse
                  : l10n.occlusionRectangle,
            ),
            showDivider: index < widget.document.masks.length - 1,
            trailing: NcIconButton(
              key: ValueKey<String>(
                'occlusion-delete-${widget.document.masks[index].id}',
              ),
              icon: Icons.close_rounded,
              tooltip: l10n.occlusionDeleteMaskTooltip,
              size: 28,
              iconColor: colors.ember,
              onPressed: () => _remove(widget.document.masks[index].id),
            ),
          ),
      ],
    );
  }
}

/// Готовая маска: `ink5` 92 %, рамка `aurumSoft` и номер.
class _MaskCover extends StatelessWidget {
  const _MaskCover({
    required this.mask,
    required this.number,
    required this.canvasSize,
  });

  final OcclusionMask mask;
  final int number;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final NcColors colors = theme.colors;
    final Rect rect = Rect.fromLTWH(
      mask.x * canvasSize.width,
      mask.y * canvasSize.height,
      mask.width * canvasSize.width,
      mask.height * canvasSize.height,
    );
    final String numberText = '$number';
    final ShapeBorder shape = mask.shape == OcclusionShape.ellipse
        ? OvalBorder(side: BorderSide(color: colors.aurumSoft))
        : RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: colors.aurumSoft),
          );
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        label: AppLocalizations.of(context).occlusionMaskNumber(number),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.ink5.withValues(alpha: 0.92),
            shape: shape,
          ),
          child: Center(
            child: Text(
              numberText,
              style: theme.typography.labelM.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Рамка рисуемой маски: `aurum` 1,5 px + заливка 18 %.
class _DraftPainter extends CustomPainter {
  const _DraftPainter({
    required this.rect,
    required this.shape,
    required this.color,
  });

  final Rect rect;
  final OcclusionShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect pixels = Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );
    final Paint fill = Paint()..color = color.withValues(alpha: 0.18);
    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    if (shape == OcclusionShape.ellipse) {
      canvas.drawOval(pixels, fill);
      canvas.drawOval(pixels, border);
    } else {
      canvas.drawRect(pixels, fill);
      canvas.drawRect(pixels, border);
    }
  }

  @override
  bool shouldRepaint(_DraftPainter old) =>
      old.rect != rect || old.shape != shape || old.color != color;
}
