import 'package:flutter/material.dart';

/// Шари інтерфейсу: мініплеєр стоїть над сторінками, але під шторками, діалогами й сторінкою налаштувань.
/// Шторки та сторінки, що живуть усередині дерева (а не в Navigator), «займають» шар через [AppLayerClaim];
/// поки є хоч одне заняття, мініплеєр ховається під них і не перекриває кнопок.
class AppLayers {
  AppLayers._();

  /// Скільки накладок зараз закривають нижню частину екрана
  static final ValueNotifier<int> blockers = ValueNotifier<int>(0);

  static bool get blocked => blockers.value > 0;
}

/// Позначає, що [child] — накладка (шторка, сторінка налаштувань), яку мініплеєр не має перекривати, поки [active].
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
    // Не сповіщаємо слухачів посеред побудови дерева
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
