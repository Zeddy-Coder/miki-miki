import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/hikka_models.dart';
import '../../services/continue_watching.dart';
import '../../services/hikka_api.dart';
import '../../services/episode_alerts.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/network_status.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_store.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../downloads/downloads_page.dart' show DownloadsHomeShelf;
import '../line_icons.dart';
import 'hikka_airing_strip.dart';
import 'hikka_banner.dart';
import 'hikka_cards.dart';
import 'hikka_continue_card.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_shelf.dart';
import '../../utils/app_clock.dart';

/// Miki Miki "Головна": a search bar with notifications, a thin calendar ticker, banners of current ongoing titles and shelves
/// (continue watching, recommendations, airing now, announcements, most popular, best by score).
class HikkaHomePage extends StatefulWidget {
  final double scale;
  final double bottomInset;

  /// Changes when the user asks to refresh the data
  final int refreshToken;

  /// Pull-down refresh
  final Future<void> Function()? onRefresh;

  const HikkaHomePage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0, this.onRefresh});

  /// How many current ongoing titles go into the banners (the rest go to the "Зараз виходить" shelf)
  static const int bannerCount = 6;

  @override
  State<HikkaHomePage> createState() => _HikkaHomePageState();
}

class _HikkaHomePageState extends State<HikkaHomePage> {
  final ScrollController _scroll = AppSmoothScrollController();
  bool _online = NetworkStatus.instance.online;

  @override
  void initState() {
    super.initState();
    NetworkStatus.instance.addListener(_network);
  }

  /// Offline the downloaded titles move to the top (and back when the internet returns)
  void _network() {
    final online = NetworkStatus.instance.online;
    if (online != _online && mounted) setState(() => _online = online);
  }

  @override
  void dispose() {
    NetworkStatus.instance.removeListener(_network);
    _scroll.dispose();
    super.dispose();
  }

  /// Label of recent views: a change means the "Продовжити перегляд" shelf must be reread
  static String _recentSignature() => ContinueWatching.recent(limit: 12).map((e) => '${e.$1}|${e.$2}|${e.$3.millisecondsSinceEpoch}').join(';');

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final api = HikkaApi.instance;
    final adult = HikkaPrefs.instance.allowAdult;
    final now = AppClock.now();
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
      header: _TopBar(scale: scale, pad: pad, onRefresh: widget.onRefresh),
      body: HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      onRefresh: widget.onRefresh,
      children: [
        // No internet: what is on the device comes first
        if (!_online) DownloadsHomeShelf(scale: scale, pad: pad),
        HikkaAsync<List<HikkaAnime>>(
          key: ValueKey('banners-$token'),
          scale: scale,
          compactError: true,
          load: () => search(ongoing, size: 24),
          loading: (context) => _BannerSkeleton(scale: scale, pad: pad),
          builder: (context, list) => HikkaBannerCarousel(items: list.take(HikkaHomePage.bannerCount).toList(), scale: scale, pad: pad),
        ),
        HikkaAiringStrip(scale: scale, pad: pad, token: token),
        ListenableBuilder(
          listenable: WatchStore.instance,
          builder: (context, _) => HikkaShelfAsync<ContinueItem>(
            scale: scale,
            pad: pad,
            title: 'Продовжити перегляд',
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
        if (_online) DownloadsHomeShelf(scale: scale, pad: pad),
        HikkaShelfAsync<HikkaAnime>(
          scale: scale,
          pad: pad,
          title: 'Рекомендації',
          subtitle: recent.isEmpty ? 'Найкраще за оцінками спільноти' : 'За вашими переглядами',
          token: '$token-${recent.isEmpty ? '' : recent.first.$1}',
          load: () async {
            if (recent.isNotEmpty) {
              try {
                final recs = (await api.recommendations(recent.first.$1, size: 16, allowAdult: adult)).items;
                if (recs.isNotEmpty) return recs;
              } catch (_) {
                // below is the general selection
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
          // The first of them are already in the banners
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

/// Top row: the search bar (opens the catalog with the cursor in the search field) and the bell with an accent dot
/// when there are unread new episodes
class _TopBar extends StatelessWidget {
  final double scale;
  final double pad;

  /// On PC pull-down does not work: refresh is a button next to notifications
  final Future<void> Function()? onRefresh;

  const _TopBar({required this.scale, required this.pad, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final mobile = AppPlatform.isMobile;
    final search = HikkaSearchPill(scale: scale, hint: 'Пошук аніме…', label: 'Пошук аніме', onTap: HikkaNav.instance.openSearch);
    return Padding(
      // The page frame adds 6 more under it: 14 to the banner, as in the design
      padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad - 6 * scale, 8 * scale),
      child: Row(
        children: [
          mobile
              ? Expanded(child: search)
              : Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 560 * scale), child: search)),
          SizedBox(width: 6 * scale),
          if (!mobile && onRefresh != null) HikkaLineButton(scale: scale, icon: LineIcon.refresh, tooltip: 'Оновити', onTap: () => onRefresh!()),
          ListenableBuilder(
            listenable: EpisodeAlerts.instance,
            builder: (context, _) {
              final unread = EpisodeAlerts.instance.unread;
              return HikkaLineButton(
                scale: scale,
                icon: LineIcon.bell,
                iconSize: 24,
                tooltip: unread > 0 ? 'Сповіщення: $unread нових' : 'Сповіщення',
                onTap: HikkaNav.instance.openNotifications,
                dot: unread > 0,
                dotKey: const ValueKey('bell-badge'),
              );
            },
          ),
        ],
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
          final maxCard = 640 * (AppPlatform.isMobile ? 1.0 : scale);
          final phone = box.maxWidth <= maxCard;
          final w = phone ? box.maxWidth : maxCard;
          return Container(
            width: w,
            height: phone ? HikkaBannerCarouselMetrics.phoneHeight(scale) : HikkaBannerCarouselMetrics.heightFor(w),
            decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(18 * scale)),
          );
        },
      ),
    );
  }
}
