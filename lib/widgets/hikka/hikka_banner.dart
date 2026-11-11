import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/banner_art.dart';
import '../../services/app_log.dart';
import '../../services/backend_client.dart';
import '../../services/hikka_images.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import 'hikka_common.dart';

/// Розміри банера (скелет завантаження повторює їх, щоб сторінка не стрибала)
class HikkaBannerCarouselMetrics {
  const HikkaBannerCarouselMetrics._();

  /// Висота банера за його шириною
  static double heightFor(double cardWidth) => (cardWidth * 0.5).clamp(150.0, 210.0);
}

/// Завантажувач банерів тайтлів (MAL-id → зображення); у тестах підміняється
typedef HikkaBannerArtLoader = Future<Map<int, BannerArtwork>> Function(List<HikkaAnime> items);

/// Банери «Головної»: карусель поточних онґоїнґів. Фон — широкий банер з AniList (чи TheMovieDB), а поки він
/// вантажиться або його немає — той самий постер, прокручений крізь крихітну копію (розмиття без дорогого
/// `BackdropFilter`); поверх нього чіткий постер, назва та кнопка «Дивитись».
/// Сама гортає кожні [autoAdvance], коли вкладка на екрані; дотик чи перетягування зупиняє автогортання на деякий час.
class HikkaBannerCarousel extends StatefulWidget {
  final List<HikkaAnime> items;
  final double scale;
  final double pad;
  final Duration autoAdvance;

  /// Звідки брати широкі банери; за замовчуванням — `BannerArt.instance`
  final HikkaBannerArtLoader? artLoader;

  const HikkaBannerCarousel({
    super.key,
    required this.items,
    required this.scale,
    required this.pad,
    this.autoAdvance = const Duration(seconds: 7),
    this.artLoader,
  });

  @override
  State<HikkaBannerCarousel> createState() => _HikkaBannerCarouselState();
}

class _HikkaBannerCarouselState extends State<HikkaBannerCarousel> {
  PageController? _controller;
  double _fraction = 0;
  bool _loopMode = false;
  int _index = 0;
  Timer? _timer;
  DateTime _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Map<int, BannerArtwork> _art = const {};
  int _artGeneration = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.autoAdvance, (_) => _tick());
    BackendClient.keyEpoch.addListener(_loadArt);
    _loadArt();
  }

  @override
  void didUpdateWidget(HikkaBannerCarousel old) {
    super.didUpdateWidget(old);
    final a = [for (final x in old.items) x.slug];
    final b = [for (final x in widget.items) x.slug];
    if (a.length != b.length || !_sameList(a, b)) _loadArt();
  }

  static bool _sameList(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Підтягує широкі банери; до відповіді (чи при збої) картка лишається без банера
  void _loadArt() {
    final gen = ++_artGeneration;
    final load = widget.artLoader ?? BannerArt.instance.load;
    load(widget.items).then<void>((map) {
      if (!mounted || gen != _artGeneration) return;
      setState(() => _art = map);
    }, onError: (Object e) {
      AppLog.w('banners', 'банери не завантажились: ${e.runtimeType}: $e');
    });
  }

  @override
  void dispose() {
    BackendClient.keyEpoch.removeListener(_loadArt);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _tick() {
    final c = _controller;
    if (!mounted || c == null || !c.hasClients || widget.items.length < 2) return;
    // Вкладка на іншому екрані (Offstage) — не гортаємо
    if (!TickerMode.valuesOf(context).enabled) return;
    if (DateTime.now().isBefore(_pausedUntil)) return;
    // Телефон: карусель безкінечна й завжди йде вперед; широке вікно: після останнього — на початок
    final n = widget.items.length;
    var cur = (c.page ?? c.initialPage.toDouble()).round();
    // Дійшли до дальнього краю віртуальних сторінок — непомітно повертаємось до середини (той самий банер)
    if (_loopMode && cur >= n * (_loops + _loops ~/ 2)) {
      cur -= n * (_loops ~/ 2);
      c.jumpToPage(cur);
    }
    final next = _loopMode ? cur + 1 : (_index + 1) % n;
    c.animateToPage(next, duration: AppAnim.long, curve: AppAnim.easeInOut);
  }

  void _pause() => _pausedUntil = DateTime.now().add(widget.autoAdvance * 2);

  /// Скільки «кіл» віртуальних сторінок: безкінечне гортання в обидва боки без стрибків
  static const int _loops = 50;

  PageController _controllerFor(double fraction, bool loop) {
    if (_controller == null || (_fraction - fraction).abs() > 0.001 || _loopMode != loop) {
      _controller?.dispose();
      _fraction = fraction;
      _loopMode = loop;
      final n = widget.items.length;
      _controller = PageController(viewportFraction: fraction, initialPage: _index.clamp(0, n - 1) + (loop ? n * _loops : 0));
    }
    return _controller!;
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 20 * scale),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final maxCard = 640 * (AppPlatform.isMobile ? 1.0 : scale);
          // Телефон: банер майже на всю ширину, сусідній виглядає збоку. Широке вікно: банер фіксованої ширини зліва.
          final single = items.length == 1;
          final fraction = width <= maxCard / 0.92 ? (single ? 1.0 : 0.92) : (maxCard / width).clamp(0.3, 1.0);
          final centered = fraction >= 0.8;
          final cardWidth = width * fraction;
          final height = HikkaBannerCarouselMetrics.heightFor(cardWidth);
          final loop = centered && items.length > 1;
          final n = items.length;
          final controller = _controllerFor(fraction, loop);
          return Column(
            children: [
              SizedBox(
                height: height,
                child: Listener(
                  onPointerDown: (_) => _pause(),
                  child: PageView.builder(
                    controller: controller,
                    padEnds: centered,
                    itemCount: loop ? n * _loops * 2 : n,
                    onPageChanged: (i) => setState(() => _index = loop ? i % n : i),
                    itemBuilder: (context, page) {
                      final i = loop ? page % n : page;
                      return Padding(
                        padding: EdgeInsets.only(
                          left: centered ? 5 : (i == 0 ? widget.pad : 5),
                          right: centered ? 5 : 5,
                        ),
                        child: _Banner(anime: items[i], art: _art[items[i].malId], scale: scale, height: height),
                      );
                    },
                  ),
                ),
              ),
              if (items.length > 1) ...[
                SizedBox(height: 10 * scale),
                _Dots(count: items.length, index: _index, scale: scale),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  final double scale;

  const _Dots({required this.count, required this.index, required this.scale});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < count; i++)
            AppAnimatedContainer(
              margin: EdgeInsets.symmetric(horizontal: 3 * scale),
              width: (i == index ? 18 : 6) * scale,
              height: 6 * scale,
              decoration: BoxDecoration(
                color: i == index ? uiTheme.accentColor : uiTheme.textDarkMuted.withValues(alpha: 0.4),
                borderRadius: uiTheme.borderRadius(3 * scale),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final HikkaAnime anime;
  final BannerArtwork? art;
  final double scale;
  final double height;

  const _Banner({required this.anime, required this.art, required this.scale, required this.height});

  @override
  Widget build(BuildContext context) {
    final a = anime;
    final r = uiTheme.borderRadius(18 * scale);
    final title = a.title(HikkaPrefs.instance.titleLang);
    // «TV-серіал» — звичайний випадок і місця на вузькому банері не варте: позначаємо лише фільми, OVA тощо
    final meta = [if (a.typeLabel.isNotEmpty && a.mediaType != 'tv') a.typeLabel, if (a.seasonLabel.isNotEmpty) a.seasonLabel].join(' · ');
    final posterHeight = height - 24 * scale;
    final progress = a.episodesLabel;
    const white = Colors.white;
    return Semantics(
      button: true,
      label: '$title. ${progress.isEmpty ? '' : '$progress. '}Дивитись',
      excludeSemantics: true,
      child: Material(
        color: art?.color != null ? Color(art!.color!).withValues(alpha: 0.35) : uiTheme.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: uiTheme.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.white.withValues(alpha: 0.08),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (art?.url != null) _WideBackdrop(key: ValueKey(art!.url), url: art!.url!),
              // Затемнення зліва направо: текст читається на будь-якому постері
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xA6000000), Color(0x73000000), Color(0x40000000)],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12 * scale),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: posterHeight * 0.7,
                      child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 10, icon: Symbols.movie_rounded, border: false),
                    ),
                    SizedBox(width: 14 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (a.isOngoing) HikkaPill(text: 'Виходить', scale: scale, background: uiTheme.accentColor.withValues(alpha: 0.8), foreground: uiTheme.onAccent),
                              if (progress.isNotEmpty) ...[
                                SizedBox(width: 8 * scale),
                                Flexible(
                                  child: Text(progress, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, color: white.withValues(alpha: 0.85))),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: 8 * scale),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: hikkaStyle(17 * scale, color: white, weight: FontWeight.bold, height: 1.2),
                          ),
                          // Тип із сезоном і оцінка в одному рядку: так банер не розростається на вузькому екрані
                          if (meta.isNotEmpty || a.hasScore)
                            Padding(
                              padding: EdgeInsets.only(top: 4 * scale),
                              child: Row(
                                children: [
                                  if (meta.isNotEmpty)
                                    Flexible(
                                      child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: white.withValues(alpha: 0.75))),
                                    ),
                                  if (meta.isNotEmpty && a.hasScore) SizedBox(width: 10 * scale),
                                  if (a.hasScore) ...[
                                    Icon(Symbols.star_rounded, color: const Color(0xFFFFC23D), size: 15 * scale, fill: 1),
                                    SizedBox(width: 3 * scale),
                                    Text(a.score.toStringAsFixed(2), style: hikkaStyle(12 * scale, color: white, weight: FontWeight.w600)),
                                  ],
                                ],
                              ),
                            ),
                          const Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 7 * scale),
                            decoration: BoxDecoration(color: uiTheme.accentColor, borderRadius: uiTheme.borderRadius(12 * scale)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Symbols.play_arrow_rounded, color: uiTheme.onAccent, size: 18 * scale, fill: 1),
                                SizedBox(width: 4 * scale),
                                Text('Дивитись', style: hikkaStyle(12.5 * scale, color: uiTheme.onAccent, weight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// Широкий банер (TheMovieDB, запасний — AniList): проявляється, коли завантажиться
class _WideBackdrop extends StatelessWidget {
  final String url;

  const _WideBackdrop({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final px = HikkaImages.bucket(c.maxWidth.isFinite ? c.maxWidth : 640, MediaQuery.devicePixelRatioOf(context));
        return Image(
          image: ResizeImage.resizeIfNeeded(px, null, HikkaImage(url)),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) => sync ? child : AppFade(opacity: frame == null ? 0 : 1, duration: AppAnim.long, child: child),
          errorBuilder: (context, error, stack) {
            AppLog.w('banners', 'зображення банера не завантажилось: $url — $error');
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

/// Підкладка під шапкою сторінки тайтлу: широкий банер, який плавно тоне у фон сторінки (текст лишається читабельним
/// в будь-якій темі). Адреса береться з тих самих джерел, що й банер на головній; поки її немає — порожнє місце.
class HikkaTitleBackdrop extends StatefulWidget {
  final HikkaAnime anime;
  final HikkaBannerArtLoader? artLoader;

  const HikkaTitleBackdrop({super.key, required this.anime, this.artLoader});

  @override
  State<HikkaTitleBackdrop> createState() => _HikkaTitleBackdropState();
}

class _HikkaTitleBackdropState extends State<HikkaTitleBackdrop> {
  BannerArtwork? _art;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    BackendClient.keyEpoch.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(HikkaTitleBackdrop old) {
    super.didUpdateWidget(old);
    if (old.anime.malId != widget.anime.malId) _load();
  }

  @override
  void dispose() {
    BackendClient.keyEpoch.removeListener(_load);
    super.dispose();
  }

  void _load() {
    final gen = ++_generation;
    final loader = widget.artLoader ?? BannerArt.instance.load;
    final a = widget.anime;
    loader([a]).then<void>((map) {
      if (!mounted || gen != _generation) return;
      setState(() => _art = map[a.malId]);
    }, onError: (Object e) {
      AppLog.w('banners', 'підкладка «${a.slug}»: ${e.runtimeType}: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = _art?.url;
    if (url == null) return const SizedBox.shrink();
    final bg = uiTheme.bgPrimary;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _WideBackdrop(key: ValueKey(url), url: url),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.66), bg.withValues(alpha: 0.82), bg],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
