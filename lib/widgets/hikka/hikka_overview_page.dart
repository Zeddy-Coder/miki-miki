import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../app_animation_kit.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/app_clock.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import 'hikka_airing_strip.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_page_kit.dart';
import 'hikka_shelf.dart';

/// The "Усе" section in "Огляд": today's episodes, collections as fans of posters, articles as rows, then the catalog
/// and characters. Each block has a calm "Усі ›" that opens the matching section in full.
class HikkaOverviewPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaOverviewPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  /// How many collections and articles to show in a selection
  static const int previewCount = 3;

  @override
  State<HikkaOverviewPage> createState() => _HikkaOverviewPageState();
}

class _HikkaOverviewPageState extends State<HikkaOverviewPage> {
  final ScrollController _scroll = AppSmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A heading of a block with a calm "Усі ›" on the right
  Widget _head(String title, {String? subtitle, String more = 'Усі', VoidCallback? onMore, required double pad}) {
    final scale = widget.scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad - 8 * scale, 0),
      child: AppSectionHeader(
        scale: scale,
        title: title,
        subtitle: subtitle,
        titleSize: 15,
        calm: true,
        trailing: onMore == null ? null : HikkaLinkButton(label: more, scale: scale, onTap: onMore, calm: true),
      ),
    );
  }

  /// "Сьогодні в ефірі": three episodes (the current hour first) with the time, a small poster and the episode number
  Widget _today(double pad, Object token) {
    final scale = widget.scale;
    final adult = HikkaPrefs.instance.allowAdult;
    return HikkaAsync<List<HikkaScheduleEntry>>(
      key: ValueKey('overview-today-$token'),
      scale: scale,
      compactError: true,
      load: () async => (await HikkaApi.instance.schedule(size: HikkaAiringStrip.limit, allowAdult: adult)).items,
      loading: (context) => SizedBox(height: 200 * scale),
      builder: (context, list) {
        final now = AppClock.now();
        final entries = [...list]..sort((a, b) => a.airingAt.compareTo(b.airingAt));
        final from = HikkaTodayRow.pick(entries, now);
        if (from < 0) return const SizedBox.shrink();
        final shown = entries.skip(from).take(3).toList();
        final t = shown.first.time;
        final today = t.year == now.year && t.month == now.month && t.day == now.day;
        return Padding(
          padding: EdgeInsets.only(bottom: 14 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(today ? 'Сьогодні в ефірі' : 'Незабаром в ефірі', more: 'Розклад', onMore: () => HikkaNav.instance.setTab(HikkaTab.schedule), pad: pad),
              SizedBox(height: 4 * scale),
              for (final e in shown) _AiringRow(entry: e, scale: scale, pad: pad),
            ],
          ),
        );
      },
    );
  }

  /// "Статті": three rows with a cover on the right
  Widget _articles(double pad, Object token) {
    final scale = widget.scale;
    return HikkaAsync<List<HikkaArticle>>(
      key: ValueKey('overview-articles-$token'),
      scale: scale,
      compactError: true,
      load: () async => (await HikkaApi.instance.articles(size: 6)).items,
      loading: (context) => HikkaShelfSkeleton(scale: scale, pad: pad),
      builder: (context, list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: 14 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head('Статті', subtitle: 'Новини, огляди й авторські тексти', onMore: () => HikkaNav.instance.setTab(HikkaTab.articles), pad: pad),
              SizedBox(height: 4 * scale),
              for (final a in list.take(HikkaOverviewPage.previewCount)) HikkaArticleRow(article: a, scale: scale, pad: pad),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final api = HikkaApi.instance;
    final adult = HikkaPrefs.instance.allowAdult;
    final token = '${widget.refreshToken}-$adult';
    final pad = HikkaLayout.sidePad(context, scale);
    const popular = HikkaSearchFilters(sort: 'scored_by');

    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        SizedBox(height: 8 * scale),
        _today(pad, token),
        HikkaShelfAsync<HikkaCollection>(
          scale: scale,
          pad: pad,
          title: 'Колекції',
          subtitle: 'Добірки від спільноти',
          token: token,
          cardWidth: HikkaCollectionFanCard.width(scale),
          cardHeight: HikkaCollectionFanCard.height(scale),
          load: () async => (await api.collections(size: 8, allowAdult: adult)).items,
          itemBuilder: (context, c) => HikkaCollectionFanCard(collection: c, scale: scale),
          onMore: () => HikkaNav.instance.setTab(HikkaTab.collections),
        ),
        _articles(pad, token),
        HikkaShelfAsync<HikkaAnime>(
          scale: scale,
          pad: pad,
          title: 'Каталог',
          subtitle: 'Найпопулярніше за кількістю оцінок',
          token: token,
          load: () async => (await api.searchAnime(popular, size: 16, allowAdult: adult)).items,
          itemBuilder: (context, a) => HikkaAnimeCard(anime: a, scale: scale),
          onMore: () => HikkaNav.instance.setTab(HikkaTab.anime),
        ),
        HikkaShelfAsync<HikkaCharacter>(
          scale: scale,
          pad: pad,
          title: 'Персонажі',
          subtitle: 'Із бази Hikka',
          token: token,
          load: () async => (await api.searchCharacters('', size: 16)).items,
          itemBuilder: (context, c) => HikkaCharacterCard(character: c, scale: scale),
          onMore: () => HikkaNav.instance.setTab(HikkaTab.characters),
        ),
      ],
    );
  }
}

/// One episode of "Сьогодні в ефірі": the time in grey, a small poster, the title and "Серія N"
class _AiringRow extends StatelessWidget {
  final HikkaScheduleEntry entry;
  final double scale;
  final double pad;

  const _AiringRow({required this.entry, required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    final a = entry.anime;
    final title = a.title(HikkaPrefs.instance.titleLang);
    final episode = entry.episode > 0 ? 'Серія ${entry.episode}' : 'Нова серія';
    final time = HikkaText.hhmm(entry.time);
    return Semantics(
      button: true,
      label: '$time. $title. $episode',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 7 * scale),
          child: Row(
            children: [
              SizedBox(width: 40 * scale, child: Text(time, style: hikkaStyle(13 * scale, color: uiTheme.textMuted))),
              SizedBox(width: 12 * scale),
              SizedBox(
                width: 38 * scale,
                height: 54 * scale,
                child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, aspect: 38 / 54, radius: 8, border: false, icon: Symbols.movie_rounded),
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(14 * scale)),
                    SizedBox(height: 2 * scale),
                    Text(episode, style: hikkaStyle(12.5 * scale, color: AppTones.rowSub)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
