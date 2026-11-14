import 'package:flutter/material.dart';

/// UI layers: the mini player sits above pages but under drawers, dialogs and the settings page.
/// Drawers and pages that live inside the tree (not in the Navigator) "claim" a layer via [AppLayerClaim];
/// while there is at least one claim, the mini player hides under them and does not cover buttons.
class AppLayers {
  AppLayers._();

  /// How many overlays currently cover the bottom of the screen
  static final ValueNotifier<int> blockers = ValueNotifier<int>(0);

  static bool get blocked => blockers.value > 0;
}

/// Marks [child] as an overlay (drawer, settings page) that the mini player must not cover while [active].
class AppLayerClaim extends StatefulWidget {
  final bool active;
  final Widget child;

  const AppLayerClaim({super.key, this.active = true, required this.child});

  @override
  State<AppLayerClaim> createState() => _AppLayerClaimState();
}

class _AppLayerClaimState extends State<AppLayerClaim> {
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AppLayerClaim old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active == _held) return;
    _held = widget.active;
    // Do not notify listeners in the middle of building the tree
    final delta = _held ? 1 : -1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLayers.blockers.value = (AppLayers.blockers.value + delta).clamp(0, 1 << 20);
    });
  }

  @override
  void dispose() {
    if (_held) {
      _held = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppLayers.blockers.value = (AppLayers.blockers.value - 1).clamp(0, 1 << 20);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
