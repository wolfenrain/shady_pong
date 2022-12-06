import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef FrameRenderer = void Function(Canvas, ui.Image);

// Based on the AnimatedSample widget from the flutter_shaders library:
// https://pub.dev/packages/flutter_shaders
class FrameSampler extends StatelessWidget {
  const FrameSampler(
    this.frame, {
    required this.child,
    super.key,
    this.showMemory = false,
    this.paused = true,
  });

  final FrameRenderer frame;

  final bool showMemory;

  final bool paused;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _FrameSampler(
      frame,
      showMemory: showMemory,
      paused: paused,
      child: child,
    );
  }
}

class _FrameSampler extends SingleChildRenderObjectWidget {
  const _FrameSampler(
    this.frame, {
    required this.showMemory,
    required this.paused,
    super.child,
  });

  final FrameRenderer frame;
  final bool showMemory;
  final bool paused;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFrameSamplerBuilderWidget(
      devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
      frame: frame,
      showMemory: showMemory,
      paused: paused,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderFrameSamplerBuilderWidget)
      ..devicePixelRatio = MediaQuery.of(context).devicePixelRatio
      ..frame = frame
      ..showMemory = showMemory
      ..paused = paused;
  }
}

/// A render object that runs a [FrameRenderer] and paints the result.
class _RenderFrameSamplerBuilderWidget extends RenderProxyBox {
  // Create a new [_RenderSnapshotWidget].
  _RenderFrameSamplerBuilderWidget({
    required double devicePixelRatio,
    required FrameRenderer frame,
    required bool showMemory,
    required bool paused,
  })  : _devicePixelRatio = devicePixelRatio,
        _frame = frame,
        _showMemory = showMemory,
        _paused = paused;

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == devicePixelRatio) return;
    _devicePixelRatio = value;
    if (_currentMemory == null) return;
    _currentMemory?.dispose();
    _currentMemory = null;
    markNeedsPaint();
  }

  FrameRenderer get frame => _frame;
  FrameRenderer _frame;
  set frame(FrameRenderer value) {
    if (value == frame) return;
    _frame = value;
    markNeedsPaint();
  }

  bool get showMemory => _showMemory;
  bool _showMemory;
  set showMemory(bool value) {
    if (value == showMemory) return;
    _showMemory = value;
    markNeedsPaint();
  }

  bool get paused => _paused;
  bool _paused;
  set paused(bool value) {
    if (value == paused) return;
    _paused = value;
    markNeedsPaint();
  }

  ui.Image? _currentMemory;

  @override
  void detach() {
    _currentMemory?.dispose();
    _currentMemory = null;
    super.detach();
  }

  @override
  void dispose() {
    _currentMemory?.dispose();
    _currentMemory = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) {
      _currentMemory?.dispose();
      _currentMemory = null;
      return;
    }

    // If we don't have a memory, create one.
    _currentMemory ??= context.toImage(
      (canvas) {},
      devicePixelRatio: devicePixelRatio,
      size: size,
      offset: offset,
    );

    // Render the frame into a new memory.
    final newMemory = context.toImage(
      (canvas) => frame(canvas, _currentMemory!),
      devicePixelRatio: devicePixelRatio,
      size: size,
      offset: offset,
    );

    // If we are not paused, dispose the old memory and use the new one.
    if (!paused) {
      _currentMemory?.dispose();
      _currentMemory = newMemory;
    }

    // If we are not showing the memory, just paint the child which will
    // xor out the memory.
    if (!showMemory) {
      super.paint(context, offset);
    }

    // Paint the new memory image.
    context.canvas.drawImage(newMemory, offset, Paint());
  }
}

extension on PaintingContext {
  ui.Image toImage(
    void Function(Canvas canvas) paint, {
    required double devicePixelRatio,
    required Size size,
    required Offset offset,
  }) {
    final offsetLayer = OffsetLayer();
    final context = PaintingContext(offsetLayer, offset & size);
    paint(context.canvas);

    // ignore: invalid_use_of_protected_member
    context.stopRecordingIfNeeded();
    final image = offsetLayer.toImageSync(
      Offset.zero & size,
      pixelRatio: devicePixelRatio,
    );
    offsetLayer.dispose();
    return image;
  }
}
