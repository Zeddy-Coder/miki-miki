import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/continue_watching.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_store.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import 'hikka_airing_strip.dart';
import 'hikka_banner.dart';
import 'hikka_cards.dart';
import 'hikka_continue_card.dart';
import 'hikka_common.dart';
import 'hikka_notifications_dialog.dart';
import 'hikka_page_kit.dart';
import 'hikka_shelf.dart';

/// «Головна» Miki Miki: пошукова панель зі сповіщеннями, тонка стрічка календаря, банери поточних онґоїнґів і полиці
/// (продовжити перегляд, рекомендації, що виходить, анонси, найпопулярніше, найкраще за оцінкою).
class HikkaHomePage extends StatefulWidget {
  final double scale;
  final double bottomInset;

  /// Змінюється, коли користувач просить оновити дані
  final int refreshToken;

  /// Оновлення потягом вниз
  final Future<void> Function()? onRefresh;

  const HikkaHomePage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0, this.onRefresh});

  /// Скільки поточних онґоїнґів іде в банери (решта — на полицю «Зараз виходить»)
  static const int bannerCount = 6;

  @override
  State<HikkaHomePage> createState() => _HikkaHomePageState();
}

class _HikkaHomePageState extends State<HikkaHomePage> {
  final ScrollController _scroll = AppSmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Підпис недавніх переглядів: зміна означає, що полицю «Продовжити перегляд» треба перечитати
  static String _recentSignature() => ContinueWatching.recent(limit: 12).map((e) => '${e.$1}|${e.$2}|${e.$3.millisecondsSinceEpoch}').join(';');

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final api = HikkaApi.instance;
    final adult = HikkaPrefs.instance.allowAdult;
    final now = DateTime.now();
    final (season, year) = HikkaText.currentSeason(now);
    final token = '${widget.refreshToken}-$adult';
    final pad = HikkaLayout.sidePad(context, scale);

    final ongoing = HikkaSearchFilters(
      statuses: const {'ongoing'},
      seasons: {season},
      yearFrom: year,
      yearTo: year,
      sort: 'scored_by',
    );
    const announced = HikkaSearchFilters(statuses: {'announced'}, sort: 'scored_by');
    const top = HikkaSearchFilters(sort: 'score');
    const popular = HikkaSearchFilters(sort: 'scored_by');
    const community = HikkaSearchFilters(sort: 'native_score');

    Future<List<HikkaAnime>> search(HikkaSearchFilters f, {int size = 16}) async => (await api.searchAnime(f, size: size, allowAdult: adult)).items;

    HikkaShelfAsync<HikkaAnime> shelf(String title, String subtitle, HikkaSearchFilters f) => HikkaShelfAsync<HikkaAnime>(
          scale: scale,
          pad: pad,
          title: title,
          subtitle: subtitle,
          token: token,
          load: () => search(f),
          itemBuilder: (context, a) => HikkaAnimeCard(anime: a, scale: scale),
          onMore: () => HikkaNav.instance.openCatalog(f),
        );

    final recent = ContinueWatching.recent(limit: 1);

    return HikkaCollapsingHeader(
      header: Padding(
        padding: EdgeInsets.only(top: 6 * scale),
        child: _TopBar(scale: scale, pad: pad, onRefresh: widget.onRefresh),
      ),
      body: HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      onRefresh: widget.onRefresh,
      children: [
        HikkaAiringStrip(scale: scale, pad: pad, token: token),
        HikkaAsync<List<HikkaAnime>>(
          key: ValueKey('banners-$token'),
          scale: scale,
          compactError: true,
          load: () => search(ongoing, size: 24),
          loading: (context) => _BannerSkeleton(scale: scale, pad: pad),
          builder: (context, list) => HikkaBannerCarousel(items: list.take(HikkaHomePage.bannerCount).toList(), scale: scale, pad: pad),
        ),
        ListenableBuilder(
          listenable: WatchStore.instance,
          builder: (context, _) => HikkaShelfAsync<ContinueItem>(
            scale: scale,
            pad: pad,
            title: 'Продовжити перегляд',
            subtitle: 'Ваш список «Дивлюсь» і нещодавні перегляди',
            token: '$token-${_recentSignature()}-${ContinueWatching.availabilitySignature()}',
            load: () async {
              final items = await ContinueWatching.load(allowAdult: adult);
              unawaited(ContinueWatching.refreshAvailability(items));
              return items;
            },
            cardWidth: HikkaContinueCard.width(scale),
            cardHeight: HikkaContinueCard.height(scale),
            itemBuilder: (context, it) => HikkaContinueCard(item: it, scale: scale),
          ),
        ),
        HikkaShelfAsync<HikkaAnime>(
          scale: scale,
          pad: pad,
          title: 'Рекомендації',
          subtitle: recent.isEmpty ? 'Найкраще за оцінками спільноти Hikka' : 'За вашими переглядами',
          token: '$token-${recent.isEmpty ? '' : recent.first.$1}',
          load: () async {
            if (recent.isNotEmpty) {
              try {
                final recs = (await api.recommendations(recent.first.$1, size: 16, allowAdult: adult)).items;
                if (recs.isNotEmpty) return recs;
              } catch (_) {
                // нижче — загальна добірка
              }
            }
            return search(community);
          },
          itemBuilder: (context, a) => HikkaAnimeCard(anime: a, scale: scale),
          onMore: () => HikkaNav.instance.openCatalog(community),
        ),
        HikkaShelfAsync<HikkaAnime>(
          scale: scale,
          pad: pad,
          title: 'Зараз виходить',
          subtitle: '${HikkaText.season(season)} $year',
          token: token,
          // Перші з них уже в банерах
          load: () async => (await search(ongoing, size: 24)).skip(HikkaHomePage.bannerCount).toList(),
          itemBuilder: (context, a) => HikkaAnimeCard(anime: a, scale: scale),
          onMore: () => HikkaNav.instance.openCatalog(ongoing),
        ),
        shelf('Анонси', 'Незабаром на Hikka', announced),
        shelf('Найпопулярніші', 'За кількістю оцінок', popular),
        shelf('Найкращі за оцінкою', 'За оцінками MyAnimeList', top),
      ],
      ),
    );
  }
}

/// Верхній рядок: пошукова панель (відкриває каталог із курсором у полі пошуку) і сповіщення
class _TopBar extends StatelessWidget {
  final double scale;
  final double pad;

  /// На ПК потяг вниз не працює: оновлення — кнопка поруч зі сповіщеннями
  final Future<void> Function()? onRefresh;

  const _TopBar({required this.scale, required this.pad, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final mobile = AppPlatform.isMobile;
    final search = _SearchPill(scale: scale);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 2 * scale, mobile ? pad - 8 : pad - 8, 12 * scale),
      child: Row(
        children: [
          mobile
              ? Expanded(child: search)
              : Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 560 * scale), child: search)),
          SizedBox(width: 4 * scale),
          if (!mobile && onRefresh != null) HikkaIconButton(icon: Symbols.refresh_rounded, tooltip: 'Оновити', scale: scale, onTap: () => onRefresh!()),
          HikkaIconButton(
            icon: Symbols.notifications_rounded,
            tooltip: 'Сповіщення',
            scale: scale,
            onTap: () => HikkaNotificationsDialog.show(context, scale: scale),
          ),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final double scale;

  const _SearchPill({required this.scale});

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(16 * scale);
    final height = AppPlatform.isMobile ? AppPlatform.touchTarget : 42 * scale;
    return Semantics(
      button: true,
      label: 'Пошук аніме',
      excludeSemantics: true,
      child: Material(
        color: uiTheme.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: uiTheme.borderSubtle)),
        child: InkWell(
          borderRadius: r,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: HikkaNav.instance.openSearch,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14 * scale),
              child: Row(
                children: [
                  Icon(Symbols.search_rounded, color: uiTheme.textMuted, size: 22 * scale, weight: 300),
                  SizedBox(width: 10 * scale),
                  Expanded(
                    child: Text('Пошук аніме…', maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(14 * scale, color: uiTheme.textMuted)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerSkeleton extends StatelessWidget {
  final double scale;
  final double pad;

  const _BannerSkeleton({required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 20 * scale),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth.clamp(0.0, 640 * (AppPlatform.isMobile ? 1.0 : scale));
          return Container(
            width: w,
            height: HikkaBannerCarouselMetrics.heightFor(w),
            decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(18 * scale)),
          );
        },
      ),
    );
  }
}
