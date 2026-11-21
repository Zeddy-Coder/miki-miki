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
import '../app_tones.dart';
import '../app_ui_kit.dart' show onAccent;
import '../line_icons.dart';
import 'hikka_common.dart';

/// Banner sizes (the loading skeleton repeats them so the page does not jump)
class HikkaBannerCarouselMetrics {
  const HikkaBannerCarouselMetrics._();

  /// Banner height by its width (a wide window)
  static double heightFor(double cardWidth) => (cardWidth * 0.5).clamp(150.0, 210.0);

  /// Banner height on a phone: the same at any width
  static double phoneHeight(double scale) => 198 * scale;
}

/// Title banner loader (MAL id → image); replaced in tests
typedef HikkaBannerArtLoader = Future<Map<int, BannerArtwork>> Function(List<HikkaAnime> items);

/// "Головна" banners: a carousel of current ongoing titles. The background is a wide banner from AniList (or TheMovieDB), and while it
/// loads or is missing, the same poster scaled through a tiny copy (blur without an expensive
/// `BackdropFilter`); over it a sharp poster, the title and the "Дивитись" button.
/// It scrolls itself every [autoAdvance] when the tab is on screen; a touch or drag stops auto-scrolling for a while.
class HikkaBannerCarousel extends StatefulWidget {
  final List<HikkaAnime> items;
  final double scale;
  final double pad;
  final Duration autoAdvance;

  /// Where to get wide banners from; by default `BannerArt.instance`
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

  /// The banner list has answered: titles without a wide banner may show the poster instead
  bool _artKnown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.autoAdvance, (_) => _tick());
    BackendClient.keyEpoch.addListener(_loadArt);
    _loadArt();
  }

  /// The screen the carousel is on: a window opened over it (the settings on a PC) stops the turning too
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
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

  /// Fetches wide banners; until the response (or on failure) the card stays without a banner
  void _loadArt() {
    final gen = ++_artGeneration;
    final load = widget.artLoader ?? BannerArt.instance.load;
    load(widget.items).then<void>((map) {
      if (!mounted || gen != _artGeneration) return;
      setState(() {
        _art = map;
        _artKnown = true;
      });
    }, onError: (Object e) {
      AppLog.w('banners', 'банери не завантажились: ${e.runtimeType}: $e');
      if (mounted && gen == _artGeneration) setState(() => _artKnown = true);
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
    // The tab is on another screen (Offstage): we do not scroll
    if (!TickerMode.valuesOf(context).enabled) return;
    if (DateTime.now().isBefore(_pausedUntil)) return;
    // Scrolled out of sight (the page is read further down) or under a window: turning the pages there only woke the
    // phone up for half a second of frames every few seconds
    if (_route?.isCurrent == false || !_onScreen()) return;
    // Phone: the carousel is endless and always goes forward; wide window: after the last one, back to the start
    final n = widget.items.length;
    var cur = (c.page ?? c.initialPage.toDouble()).round();
    // Reached the far edge of the virtual pages: quietly return to the middle (the same banner)
    if (_loopMode && cur >= n * (_loops + _loops ~/ 2)) {
      cur -= n * (_loops ~/ 2);
      c.jumpToPage(cur);
    }
    final next = _loopMode ? cur + 1 : (_index + 1) % n;
    c.animateToPage(next, duration: AppAnim.long, curve: AppAnim.easeInOut);
  }

  void _pause() => _pausedUntil = DateTime.now().add(widget.autoAdvance * 2);

  /// Whether some of the carousel is inside the page's scroll view (or the page does not scroll)
  bool _onScreen() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final page = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (page is! RenderBox || !page.hasSize || !page.attached) return true;
    final mine = box.localToGlobal(Offset.zero) & box.size;
    final view = page.localToGlobal(Offset.zero) & page.size;
    return mine.overlaps(view);
  }

  /// How many "laps" of virtual pages: endless scrolling both ways without jumps
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
      padding: EdgeInsets.only(bottom: 4 * scale),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final maxCard = 640 * (AppPlatform.isMobile ? 1.0 : scale);
          // Phone: one banner across the page with the page margins (swiping brings the next). Wide window: a fixed-width
          // banner on the left, the neighbors beside it.
          final phone = width <= maxCard + widget.pad * 2;
          final fraction = phone ? 1.0 : (maxCard / width).clamp(0.3, 1.0);
          final centered = fraction >= 0.8;
          final cardWidth = phone ? width - widget.pad * 2 : width * fraction;
          final height = phone ? HikkaBannerCarouselMetrics.phoneHeight(scale) : HikkaBannerCarouselMetrics.heightFor(cardWidth);
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
                        padding: phone
                            ? EdgeInsets.symmetric(horizontal: widget.pad)
                            : EdgeInsets.only(left: centered ? 5 : (i == 0 ? widget.pad : 5), right: 5),
                        child: _Banner(anime: items[i], art: _art[items[i].malId], artKnown: _artKnown, scale: scale, height: height),
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
              width: (i == index ? 16 : 6) * scale,
              height: 6 * scale,
              decoration: BoxDecoration(
                color: i == index ? uiTheme.accentColor : AppTones.dot,
                borderRadius: BorderRadius.circular(3 * scale),
              ),
            ),
        ],
      ),
    );
  }
}

/// One banner: the wide picture under a soft darkening towards the bottom, on it the season and the released episode,
/// the title, one accent "Дивитись" and the score in grey. Without a wide picture, the poster fills the card.
class _Banner extends StatelessWidget {
  final HikkaAnime anime;
  final BannerArtwork? art;

  /// The banner list has answered (until then an empty card, not the poster: the picture would jump)
  final bool artKnown;
  final double scale;
  final double height;

  const _Banner({required this.anime, required this.art, required this.artKnown, required this.scale, required this.height});

  @override
  Widget build(BuildContext context) {
    final a = anime;
    final r = uiTheme.borderRadius(18 * scale);
    final title = a.title(HikkaPrefs.instance.titleLang);
    final released = a.episodesReleased ?? 0;
    final total = a.episodesTotal ?? 0;
    final meta = [
      if (a.seasonLabel.isNotEmpty) a.seasonLabel,
      if (a.isOngoing && released > 0) 'вийшла $released серія' else if (total > 0) '$total ${HikkaText.plural(total, 'серія', 'серії', 'серій')}',
    ].join(' · ');
    const shade = Color(0xFF0B0B0C);
    const text = Color(0xFFD7D7DC);
    const soft = Color(0xFFCFCFD4);
    final accent = uiTheme.accentColor;
    final url = art?.url;
    return Semantics(
      button: true,
      label: '$title. ${meta.isEmpty ? '' : '$meta. '}Дивитись',
      excludeSemantics: true,
      child: Material(
        color: art?.color != null ? Color(art!.color!).withValues(alpha: 0.35) : uiTheme.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.white.withValues(alpha: 0.08),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                _WideBackdrop(key: ValueKey(url), url: url)
              else if (artKnown)
                HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 0, border: false, alignment: const Alignment(0, -0.4), icon: Symbols.movie_rounded),
              // Darkening towards the bottom: the text stays readable on any picture
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0D0B0B0C), Color(0x0D0B0B0C), Color(0xEB0B0B0C)],
                    stops: [0.0, 0.2, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 16 * scale,
                right: 16 * scale,
                bottom: 14 * scale,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: text)),
                    Padding(
                      padding: EdgeInsets.only(top: 3 * scale),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: hikkaStyle(20 * scale, color: Colors.white, weight: FontWeight.bold, height: 1.2).copyWith(
                          shadows: [Shadow(color: shade.withValues(alpha: 0.5), blurRadius: 12)],
                        ),
                      ),
                    ),
                    SizedBox(height: 10 * scale),
                    Row(
                      children: [
                        Container(
                          height: 36 * scale,
                          padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                          decoration: BoxDecoration(color: accent, borderRadius: uiTheme.borderRadius(12 * scale)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LineIconView(LineIcon.play, size: 15 * scale, color: onAccent(accent)),
                              SizedBox(width: 8 * scale),
                              Text('Дивитись', style: hikkaStyle(13.5 * scale, color: onAccent(accent), weight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        if (a.hasScore) ...[
                          SizedBox(width: 10 * scale),
                          LineIconView(LineIcon.star, size: 13 * scale, color: soft, stroke: 1.8),
                          SizedBox(width: 4 * scale),
                          Text(a.score.toStringAsFixed(2), style: hikkaStyle(12.5 * scale, color: soft)),
                        ],
                      ],
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

/// Wide banner (TheMovieDB, AniList as fallback): fades in once loaded
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

/// Backdrop under the title page header: a wide banner that smoothly sinks into the page background (the text stays readable
/// in any theme). The address comes from the same sources as the home banner; until it exists, an empty space.
class HikkaTitleBackdrop extends StatefulWidget {
  final HikkaAnime anime;
  final HikkaBannerArtLoader? artLoader;

  /// Phone header: the picture stays bright (only a light veil at the top) and sinks into the background by its lower edge;
  /// nothing but the poster and the round buttons lies on it
  final bool soft;

  const HikkaTitleBackdrop({super.key, required this.anime, this.artLoader, this.soft = false});

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
                colors: widget.soft ? [bg.withValues(alpha: 0.25), bg] : [bg.withValues(alpha: 0.66), bg.withValues(alpha: 0.82), bg],
                stops: widget.soft ? const [0.0, 1.0] : const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
