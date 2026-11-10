import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';

/// Рамка для меню на телефоні: у портреті — нижня панель (до ~68 % висоти екрана),
/// в альбомній — бічна панель справа. Під нею затемнення: тап по ньому закриває панель.
///
/// Рамка малює лише поверхню (фон, рамку, тінь, «ручку»). Вміст ([child]) — це шапка й список,
/// які самі подбають про прокручування. Поки панель закривається, вміст ще лишається на екрані.
class MobileSheetFrame extends StatelessWidget {
  final bool open;
  final VoidCallback onDismiss;
  final Widget child;

  const MobileSheetFrame({
    super.key,
    required this.open,
    required this.onDismiss,
    required this.child,
  });

  /// Частка висоти екрана, яку може зайняти нижня панель у портреті
  static const double portraitHeightFactor = 0.68;

  /// Ширина бічної панелі в альбомній (dp): не вужча за 340 і не ширша за 440
  static double sideWidth(double screenWidth) => math.min(440.0, math.max(340.0, screenWidth * 0.40));

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final pad = mq.padding;
    final bool landscape = size.width > size.height;

    final Widget panel;
    if (landscape) {
      panel = Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: sideWidth(size.width) + pad.right,
        child: AppPresence(
          expand: true,
          visible: open,
          duration: AppAnim.medium,
          slide: const Offset(0.18, 0),
          child: _surface(landscape: true, pad: pad, child: child),
        ),
      );
    } else {
      panel = Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * portraitHeightFactor),
          child: AppPresence(
            visible: open,
            duration: AppAnim.medium,
            slide: const Offset(0, 0.22),
            child: _surface(landscape: false, pad: pad, child: child),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(
          children: [
            Positioned.fill(
              child: AppFade(
                opacity: open ? 1.0 : 0.0,
                duration: AppAnim.medium,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: const ColoredBox(color: Color(0x8C000000)),
                ),
              ),
            ),
            panel,
          ],
        ),
      ),
    );
  }

  Widget _surface({required bool landscape, required EdgeInsets pad, required Widget child}) {
    final r = Radius.circular(uiTheme.radius(22));
    final BorderRadius radius = landscape ? BorderRadius.horizontal(left: r) : BorderRadius.vertical(top: r);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: uiTheme.colors.drawerBg,
        borderRadius: radius,
        border: Border.all(color: uiTheme.colors.drawerBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.14 : 0.55),
            blurRadius: 24,
            offset: landscape ? const Offset(-6, 0) : const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: EdgeInsets.only(
            top: landscape ? pad.top : 0,
            right: landscape ? pad.right : 0,
            bottom: landscape ? pad.bottom : math.max(pad.bottom, 8.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!landscape) _GrabHandle(onDismiss: onDismiss),
              if (landscape) Expanded(child: child) else Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Ручка» нижньої панелі: потягнути вниз — закрити
class _GrabHandle extends StatelessWidget {
  final VoidCallback onDismiss;
  const _GrabHandle({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 150) onDismiss();
      },
      onTap: onDismiss,
      child: SizedBox(
        height: 22,
        child: Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: uiTheme.colors.textDarkMuted.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
