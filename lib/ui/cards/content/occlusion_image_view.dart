import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Изображение и интерактивные маски Occlusion.
class OcclusionImageView extends StatefulWidget {
  const OcclusionImageView({
    required this.bytes,
    required this.occlusionJson,
    required this.revealed,
    super.key,
  });

  final Uint8List bytes;
  final String occlusionJson;
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
    final document = OcclusionDocument.tryParse(widget.occlusionJson);
    return document == null
        ? <String>{}
        : <String>{for (final mask in document.masks) mask.id};
  }

  Future<void> _readImageSize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
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
    setState(() {
      if (!_shown.add(id)) _shown.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final document = OcclusionDocument.tryParse(widget.occlusionJson);
    if (document == null || document.masks.isEmpty) {
      return Text(
        l10n.occlusionInvalid,
        key: const ValueKey<String>('occlusion-invalid'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    final shown = _shown;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 360),
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.memory(
                      widget.bytes,
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stack) =>
                          Center(child: Text(l10n.occlusionImageUnavailable)),
                    ),
                    for (final mask in document.masks)
                      if (!shown.contains(mask.id))
                        Positioned(
                          left: constraints.maxWidth * mask.x,
                          top: constraints.maxHeight * mask.y,
                          width: constraints.maxWidth * mask.width,
                          height: constraints.maxHeight * mask.height,
                          child: _MaskCover(
                            mask: mask,
                            color: scheme.surfaceContainerHighest,
                            onTap: () => _toggleMask(mask.id),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            TextButton(
              key: const ValueKey<String>('occlusion-show-all'),
              onPressed: () => setState(
                () => _shown = <String>{
                  for (final mask in document.masks) mask.id,
                },
              ),
              child: Text(l10n.occlusionShowAll),
            ),
            TextButton(
              key: const ValueKey<String>('occlusion-hide-all'),
              onPressed: () => setState(() => _shown = <String>{}),
              child: Text(l10n.occlusionHideAll),
            ),
          ],
        ),
      ],
    );
  }
}

class _MaskCover extends StatelessWidget {
  const _MaskCover({
    required this.mask,
    required this.color,
    required this.onTap,
  });

  final OcclusionMask mask;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: ValueKey<String>('occlusion-cover-${mask.id}'),
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.96),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
        borderRadius: mask.shape == OcclusionShape.ellipse
            ? BorderRadius.circular(999)
            : BorderRadius.circular(2),
      ),
    ),
  );
}
