import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Compensates for a newly inserted API page during layout, before painting.
/// Uses actual inserted content height minus any space it replaces, not the
/// estimated extent of a lazy list. Use a new key for each insertion.
class PrependSliver extends SingleChildRenderObjectWidget {
  const PrependSliver({
    super.key,
    required Widget sliver,
    required this.compensate,
    required this.onAdjusted,
    this.replacedExtent = 0,
  }) : super(child: sliver);
  final bool compensate;
  final VoidCallback onAdjusted;
  // Space already occupied before insertion (e.g. the previous-page control).
  final double replacedExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPrependSliver(compensate, onAdjusted, replacedExtent);
}

class _RenderPrependSliver extends RenderProxySliver {
  _RenderPrependSliver(this._pending, this.onAdjusted, this.replacedExtent);
  bool _pending;
  final VoidCallback onAdjusted;
  final double replacedExtent;

  @override
  void performLayout() {
    super.performLayout();
    if (_pending && geometry!.scrollOffsetCorrection == null) {
      _pending = false;
      onAdjusted();
      final extent = geometry!.scrollExtent - replacedExtent;
      if (extent != 0) {
        geometry = SliverGeometry(scrollOffsetCorrection: extent);
      }
    }
  }
}
