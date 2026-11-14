import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/remote_driver.dart';
import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';

/// Стан серії із сайту поверх відео: «Шукаю відео…», «Запускаю плеєр…» або помилка з діями
/// («Спробувати ще», «Інший плеєр», «Озвучки та плеєри», «Наступна серія», «Закрити»).
/// Поки відео йде, нічого не малює й не перехоплює дотики.
class RemoteStatusOverlay extends StatelessWidget {
  final double scale;
  final RemoteDriver driver;

  /// Відкрити бічну панель серій (озвучки, плеєри, якість)
  final VoidCallback onOpenPanel;

  /// Закрити плеєр (повернутись на головну)
  final VoidCallback onClose;

  const RemoteStatusOverlay({
    super.key,
    required this.scale,
    required this.driver,
    required this.onOpenPanel,
    required this.onClose,
  });

  static const Color _errorColor = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) {
    final bool show = driver.showsStatus;
    final bool failed = driver.phase == RemotePhase.failed;
    final offer = driver.offer;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !show,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16 * scale),
            child: AppPresence(
              visible: show,
              slide: const Offset(0, 0.04),
              child: !show
                  ? const SizedBox.shrink()
                  : AppFadeSwitcher(
                      alignment: Alignment.center,
                      child: offer != null
                          ? KeyedSubtree(key: const ValueKey('offer'), child: _offerCard(offer))
                          : failed
                              ? KeyedSubtree(key: const ValueKey('failed'), child: _failedCard())
                              : KeyedSubtree(key: const ValueKey('loading'), child: _loadingCard()),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  String _loadingText() {
    if (driver.phase == RemotePhase.opening) {
      final h = driver.hoster;
      if (h.isEmpty) return 'Запускаю відео…';
      return driver.attempt > 1 ? 'Пробую інший плеєр — $h…' : 'Запускаю $h…';
    }
    return 'Шукаю відео…';
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: uiTheme.bgSurface,
        borderRadius: uiTheme.borderRadius(14 * scale),
        border: Border.all(color: uiTheme.borderSubtle, width: 1.0),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.14 : 0.55), blurRadius: 20 * scale, offset: Offset(0, 6 * scale)),
        ],
      );

  Widget _loadingCard() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 13 * scale),
      decoration: _cardDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18 * scale,
            height: 18 * scale,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: uiTheme.accentColor),
          ),
          SizedBox(width: 12 * scale),
          Flexible(
            child: Text(
              _loadingText(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13.5 * scale, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// Серія скінчилась, а наступної в цій озвучці немає: куди перейти
  Widget _offerCard(NextOffer o) {
    final others = o.full != null;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 420 * scale),
      child: Container(
        padding: EdgeInsets.fromLTRB(18 * scale, 16 * scale, 18 * scale, 16 * scale),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.skip_next_rounded, color: uiTheme.accentColor, size: 30 * scale, fill: 1, weight: 300, opticalSize: 24),
            SizedBox(height: 8 * scale),
            Text(
              'Серії ${o.next} немає в цій озвучці',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 15 * scale, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6 * scale),
            Text(
              o.from.isEmpty ? 'Її можна продовжити в іншій озвучці.' : 'Озвучення «${o.from}» тут закінчується. Продовжити в іншій?',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12.5 * scale, height: 1.35),
            ),
            SizedBox(height: 14 * scale),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                AppAccentButton(
                  scale: scale,
                  label: others ? 'Наступна за пріоритетом: ${o.byPriority.label}' : 'Перейти: ${o.byPriority.label}',
                  icon: Symbols.skip_next_rounded,
                  onTap: () => driver.acceptOffer(o.byPriority),
                ),
                if (o.full != null)
                  AppSecondaryButton(
                    scale: scale,
                    expand: false,
                    label: 'Повна: ${o.full!.label}',
                    icon: Symbols.playlist_play_rounded,
                    onTap: () => driver.acceptOffer(o.full!),
                  ),
                AppSecondaryButton(scale: scale, expand: false, label: 'Закрити', icon: Symbols.close_rounded, onTap: driver.dismissOffer),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _failedCard() {
    final other = driver.alternativeHoster;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 420 * scale),
      child: Container(
        padding: EdgeInsets.fromLTRB(18 * scale, 16 * scale, 18 * scale, 16 * scale),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.error_rounded, color: _errorColor, size: 30 * scale, fill: 1, weight: 300, opticalSize: 24),
            SizedBox(height: 8 * scale),
            Text(
              'Не вдалося запустити серію',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 15 * scale, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6 * scale),
            Text(
              driver.error ?? 'Спробуйте ще раз або оберіть іншу озвучку чи плеєр.',
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12.5 * scale, height: 1.35),
            ),
            SizedBox(height: 14 * scale),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                AppAccentButton(scale: scale, label: 'Спробувати ще', icon: Symbols.refresh_rounded, onTap: driver.retry),
                if (other != null)
                  AppSecondaryButton(
                    scale: scale,
                    expand: false,
                    label: 'Інший плеєр',
                    icon: Symbols.swap_horiz_rounded,
                    onTap: () => driver.switchHoster(other),
                  ),
                AppSecondaryButton(scale: scale, expand: false, label: 'Озвучки та плеєри', icon: Symbols.tune_rounded, onTap: onOpenPanel),
                if (driver.hasNext)
                  AppSecondaryButton(scale: scale, expand: false, label: 'Наступна серія', icon: Symbols.skip_next_rounded, onTap: () => driver.next()),
                AppSecondaryButton(scale: scale, expand: false, label: 'Закрити', icon: Symbols.close_rounded, onTap: onClose),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
