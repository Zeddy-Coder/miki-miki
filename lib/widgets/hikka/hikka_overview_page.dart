import 'package:flutter/material.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_airing_strip.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_page_kit.dart';
import 'hikka_shelf.dart';

/// Розділ «Усе» в Огляді: календар, каталог, колекції, статті та персонажі на одній сторінці.
/// Кожен блок — добірка з кнопкою «Усі», що відкриває відповідний розділ повністю.
class HikkaOverviewPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaOverviewPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  /// Скільки колекцій і статей показувати в добірці
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

  /// Вертикальна добірка карток (колекції, статті) із заголовком і кнопкою «Усі»
  Widget _list<T>({
    required String title,
    required String subtitle,
    required Object token,
    required Future<List<T>> Function() load,
    required Widget Function(T item) card,
    required HikkaTab more,
    required double pad,
  }) {
    final scale = widget.scale;
    return HikkaAsync<List<T>>(
      key: ValueKey('overview-$title-$token'),
      scale: scale,
      compactError: true,
      load: load,
      stateFrame: (context, child) => Padding(
        padding: EdgeInsets.only(bottom: 22 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: AppSectionHeader(scale: scale, title: title, subtitle: subtitle),
            ),
            SizedBox(height: 8 * scale),
            child,
          ],
        ),
      ),
      loading: (context) => HikkaShelfSkeleton(scale: scale, pad: pad),
      builder: (context, list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: 22 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: AppSectionHeader(
                  scale: scale,
                  title: title,
                  subtitle: subtitle,
                  trailing: HikkaLinkButton(label: 'Усі', scale: scale, onTap: () => HikkaNav.instance.setTab(more)),
                ),
              ),
              SizedBox(height: 10 * scale),
              for (final item in list.take(HikkaOverviewPage.previewCount))
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 10 * scale),
                  child: card(item),
                ),
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
        HikkaAiringStrip(scale: scale, pad: pad, token: token),
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
        _list<HikkaCollection>(
          title: 'Колекції',
          subtitle: 'Добірки від спільноти',
          token: token,
          load: () async => (await api.collections(size: 6, allowAdult: adult)).items,
          card: (c) => HikkaCollectionCard(collection: c, scale: scale),
          more: HikkaTab.collections,
          pad: pad,
        ),
        _list<HikkaArticle>(
          title: 'Статті',
          subtitle: 'Новини, огляди й авторські тексти',
          token: token,
          load: () async => (await api.articles(size: 6)).items,
          card: (a) => HikkaArticleCard(article: a, scale: scale),
          more: HikkaTab.articles,
          pad: pad,
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
