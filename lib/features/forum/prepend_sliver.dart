import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Compensates for a newly inserted API page during layout, before painting.
/// Uses the actual page height, not the estimated extent of a lazy list.
class PrependSliver extends SingleChildRenderObjectWidget {
  const PrependSliver({
    super.key,
    required Widget sliver,
    required this.compensate,
    required this.onAdjusted,
  }) : super(child: sliver);
  final bool compensate;
  final VoidCallback onAdjusted;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPrependSliver(compensate, onAdjusted);
}

class _RenderPrependSliver extends RenderProxySliver {
  _RenderPrependSliver(this._pending, this.onAdjusted);
  bool _pending;
  final VoidCallback onAdjusted;

  @override
  void performLayout() {
    super.performLayout();
    if (_pending && geometry!.scrollOffsetCorrection == null) {
      _pending = false;
      onAdjusted();
      final extent = geometry!.scrollExtent;
      if (extent > 0) geometry = SliverGeometry(scrollOffsetCorrection: extent);
    }
  }
}
