import 'dart:io';

import 'package:flutter/material.dart';

/// Opens [images] in a large, zoomable dialog starting at [initialIndex].
/// Pinch or double-tap to zoom, swipe between photos, tap ✕ or the dimmed
/// edge to close. Each entry is a network URL (`http…`) or a local file path,
/// so freshly picked photos and saved ones open the same way.
Future<void> showZoomableImages(
  BuildContext context, {
  required List<String> images,
  int initialIndex = 0,
}) {
  if (images.isEmpty) return Future.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withOpacity(0.88),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _ZoomableImageViewer(
      images: images,
      initialIndex: initialIndex.clamp(0, images.length - 1),
    ),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

class _ZoomableImageViewer extends StatefulWidget {
  const _ZoomableImageViewer({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_ZoomableImageViewer> createState() => _ZoomableImageViewerState();
}

class _ZoomableImageViewerState extends State<_ZoomableImageViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Zoomed in → page swipes are disabled so panning the photo doesn't flip
  /// to the next one.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: count,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (_, i) => _ZoomablePage(
                source: widget.images[i],
                onZoomChanged: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (count > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _index ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.source, required this.onZoomChanged});

  final String source;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() {
      final a = _animation;
      if (a != null) _transform.value = a.value;
    });
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTap;

  @override
  void dispose() {
    _anim.dispose();
    _transform.dispose();
    super.dispose();
  }

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  void _animateTo(Matrix4 target) {
    _animation = Matrix4Tween(begin: _transform.value, end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  /// Double-tap: zoom 2.5× into the tapped point, or back out.
  void _onDoubleTap() {
    if (_isZoomed) {
      _animateTo(Matrix4.identity());
      widget.onZoomChanged(false);
      return;
    }
    final p = _doubleTap?.localPosition ?? Offset.zero;
    const scale = 2.5;
    _animateTo(Matrix4.identity()
      ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1));
    widget.onZoomChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final isNetwork = widget.source.startsWith('http');
    final Widget image = isNetwork
        ? Image.network(
            widget.source,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  size: 48, color: Colors.white54),
            ),
          )
        : Image.file(
            File(widget.source),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  size: 48, color: Colors.white54),
            ),
          );

    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTap = d,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoomChanged(_isZoomed),
        child: Center(child: image),
      ),
    );
  }
}
