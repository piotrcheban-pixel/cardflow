import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Редактор масок Image Occlusion: рисование прямоугольником/эллипсом и удаление.
class OcclusionMaskEditor extends StatefulWidget {
  const OcclusionMaskEditor({
    required this.imageBytes,
    required this.document,
    required this.onChanged,
    super.key,
  });

  final Uint8List imageBytes;
  final OcclusionDocument document;
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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedButton<OcclusionShape>(
          segments: <ButtonSegment<OcclusionShape>>[
            ButtonSegment<OcclusionShape>(
              value: OcclusionShape.rectangle,
              label: Text(l10n.occlusionRectangle),
            ),
            ButtonSegment<OcclusionShape>(
              value: OcclusionShape.ellipse,
              label: Text(l10n.occlusionEllipse),
            ),
          ],
          selected: <OcclusionShape>{_shape},
          onSelectionChanged: (selection) =>
              setState(() => _shape = selection.first),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.occlusionDrawHint,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                // Eager-распознаватель забирает жест у прокрутки формы: иначе
                // вертикальное начало рисования прокручивало бы страницу.
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
                    onPointerDown: (event) =>
                        _startAt(event.localPosition, size),
                    onPointerMove: (event) =>
                        _updateAt(event.localPosition, size),
                    onPointerUp: (_) => _end(size),
                    onPointerCancel: (_) => setState(() => _draft = null),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.fill,
                          errorBuilder: (context, error, stack) => ColoredBox(
                            color: scheme.surfaceContainerHigh,
                            child: Center(
                              child: Text(l10n.occlusionImageUnavailable),
                            ),
                          ),
                        ),
                        for (final mask in widget.document.masks)
                          _outline(mask, scheme),
                        if (_draft case final draft?)
                          _draftOutline(draft, _shape, scheme),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < widget.document.masks.length; index++)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.occlusionMaskNumber(index + 1),
                  key: ValueKey<String>(
                    'occlusion-editor-mask-${widget.document.masks[index].id}',
                  ),
                ),
              ),
              Text(
                widget.document.masks[index].shape == OcclusionShape.ellipse
                    ? l10n.occlusionEllipse
                    : l10n.occlusionRectangle,
              ),
              IconButton(
                tooltip: l10n.occlusionDeleteMaskTooltip,
                key: ValueKey<String>(
                  'occlusion-delete-${widget.document.masks[index].id}',
                ),
                onPressed: () => _remove(widget.document.masks[index].id),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
      ],
    );
  }

  Widget _outline(OcclusionMask mask, ColorScheme scheme) => Positioned.fill(
    child: CustomPaint(
      painter: _MaskPainter(mask: mask, color: scheme.primary),
    ),
  );

  Widget _draftOutline(Rect rect, OcclusionShape shape, ColorScheme scheme) =>
      Positioned.fill(
        child: CustomPaint(
          painter: _RectPainter(
            rect: rect,
            shape: shape,
            color: scheme.primary,
          ),
        ),
      );
}

class _MaskPainter extends CustomPainter {
  const _MaskPainter({required this.mask, required this.color});

  final OcclusionMask mask;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _paintMask(
      canvas,
      size,
      Rect.fromLTWH(mask.x, mask.y, mask.width, mask.height),
      mask.shape,
      color,
    );
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.mask != mask || old.color != color;
}

class _RectPainter extends CustomPainter {
  const _RectPainter({
    required this.rect,
    required this.shape,
    required this.color,
  });

  final Rect rect;
  final OcclusionShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _paintMask(canvas, size, rect, shape, color);
  }

  @override
  bool shouldRepaint(_RectPainter old) =>
      old.rect != rect || old.shape != shape || old.color != color;
}

void _paintMask(
  Canvas canvas,
  Size size,
  Rect normalized,
  OcclusionShape shape,
  Color color,
) {
  final rect = Rect.fromLTWH(
    normalized.left * size.width,
    normalized.top * size.height,
    normalized.width * size.width,
    normalized.height * size.height,
  );
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  if (shape == OcclusionShape.ellipse) {
    canvas.drawOval(rect, paint);
  } else {
    canvas.drawRect(rect, paint);
  }
}
