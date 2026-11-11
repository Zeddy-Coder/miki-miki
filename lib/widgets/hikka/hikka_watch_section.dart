import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/episode_check.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/remote_playback.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_models.dart';
import '../../services/watch_service.dart';
import '../../services/watch_store.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import '../watch_callout.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_watch_dialogs.dart';
import 'sources_dialog.dart';

/// «Дивитись» на сторінці аніме (стоїть одразу під шапкою). Головна дія — «Дивитись / Продовжити · серія N» — відкриває
/// плеєр з обраним варіантом; усі знайдені озвучки й субтитри видно рядом чипів, і вибір (перед стартом чи в плеєрі)
/// запамʼятовується. Перед переглядом показується лише застереження про ліцензію; про розбіжність нумерації серій із
/// Hikka попереджає плашка поруч із кнопкою. Список серій згорнуто, поки людина його не відкриє.
class HikkaWatchSection extends StatefulWidget {
  final HikkaAnime anime;
  final HikkaRoute route;
  final double scale;
  final double pad;

  const HikkaWatchSection({super.key, required this.anime, required this.route, required this.scale, required this.pad});

  @override
  State<HikkaWatchSection> createState() => _HikkaWatchSectionState();
}

class _HikkaWatchSectionState extends State<HikkaWatchSection> {
  static const String _memoLoad = 'watch';

  /// Скільки серій показуємо, поки список не розгорнуто
  static const int _cap = 48;

  late WatchLoad _load;
  bool _ack = false; // підтвердження перегляду ліцензованого тайтлу — лише на цей показ сторінки
  bool _allEpisodes = false;
  String? _notice;

  double get _scale => widget.scale;
  WatchService get _service => WatchService.instance;
  WatchStore get _store => _service.store;

  @override
  void initState() {
    super.initState();
    final memo = widget.route.memo[_memoLoad];
    _load = memo is WatchLoad ? memo : _begin();
    _load.addListener(_changed);
    _store.addListener(_changed);
  }

  @override
  void dispose() {
    _load.removeListener(_changed);
    _store.removeListener(_changed);
    super.dispose();
  }

  WatchLoad _begin() {
    final l = _service.start(widget.anime);
    widget.route.memo[_memoLoad] = l;
    return l;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Шукає наново (змінили джерела, щось не відповіло)
  void _restart() {
    _load.removeListener(_changed);
    setState(() {
      _load = _begin();
      _load.addListener(_changed);
      _notice = null;
    });
  }

  // ── Допоміжне ───────────────────────────────────────────────────────────────

  String _sourceName(String id) => _service.registry.byId(id)?.name ?? id;

  /// Звідки й з якою озвучкою почати: «Продовжити» або перша серія; `null` — поки нічого не знайдено
  ({WatchTitle title, WatchGroup group, ContinuePoint point})? _target() {
    final t = _load.title;
    final g = _load.defaultGroup(_store);
    if (g == null) return null;
    final point = continuePoint(episodeKeysOf(g), _store.watched(t.animeKey), _store.last(t.animeKey)?.epKey);
    return (title: t, group: g, point: point);
  }

  Future<void> _play(WatchTitle t, WatchGroup g, String epKey) async {
    final a = widget.anime;
    final started = await WatchLauncher.play(
      RemoteLaunch(title: t, group: g, animeTitle: a.title(HikkaPrefs.instance.titleLang), epKey: epKey, poster: a.image, hikka: _load.hikka),
    );
    if (!started && mounted) setState(() => _notice = 'Плеєр ще не готовий. Спробуйте за мить.');
  }

  /// Ліцензований тайтл: після підтвердження одразу відкриваємо плеєр — людина вже ясно висловила намір
  Future<void> _confirmLicensed(WatchTitle t) async {
    final go = await WatchDialogs.confirmLicensed(context, scale: _scale, license: t.license);
    if (!go || !mounted) return;
    setState(() => _ack = true);
    final target = _target();
    if (target != null) await _play(target.title, target.group, target.point.epKey);
  }

  Future<void> _showTeams(WatchGroup g) => WatchDialogs.teams(context, scale: _scale, teams: g.teams, source: _service.registry.mikai);

  /// Налаштування джерел; якщо змінилося, що саме опитується, шукаємо наново
  Future<void> _openSources() async {
    final registry = _service.registry;
    final before = SourcesDialog.searchSignature(registry);
    await SourcesDialog.show(context, scale: _scale, registry: registry);
    if (mounted && SourcesDialog.searchSignature(registry) != before) _restart();
  }

  // ── Побудова ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = _load.title;
    return HikkaSection(
      scale: _scale,
      pad: widget.pad,
      title: 'Дивитись',
      subtitle: 'Українські озвучки та субтитри',
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: hikkaReadableWidth(_scale)), child: _body(t)),
    );
  }

  Widget _body(WatchTitle t) {
    if (t.licensed && !_ack) return _licenseCard(t);
    final groups = t.groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mainButton(t, groups),
        if (_notice != null)
          Padding(padding: EdgeInsets.only(top: 8 * _scale), child: Text(_notice!, style: hikkaStyle(12 * _scale, color: uiTheme.textMuted))),
        SizedBox(height: 14 * _scale),
        if (groups.isEmpty) _noGroups(t) else _content(t, groups),
      ],
    );
  }

  /// Головна кнопка + «⋮» праворуч (серії, команда, джерела, якість і плеєр, сайт). Видна з першої миті
  Widget _mainButton(WatchTitle t, List<WatchGroup> groups) {
    final scale = _scale;
    final Widget play;
    if (groups.isEmpty) {
      play = AppAccentButton(scale: scale, solid: true, expand: true, icon: Symbols.play_arrow_rounded, label: 'Дивитись', onTap: _noTarget);
    } else {
      final g = _load.defaultGroup(_store) ?? groups.first;
      final keys = episodeKeysOf(g);
      final p = continuePoint(keys, _store.watched(t.animeKey), _store.last(t.animeKey)?.epKey);
      final label = p.allWatched ? 'Дивитись знову' : '${p.started ? 'Продовжити' : 'Дивитись'} · серія ${episodeLabel(g.episodes[p.index], p.index)}';
      play = AppAccentButton(scale: scale, solid: true, expand: true, icon: Symbols.play_arrow_rounded, label: label, onTap: () => _play(t, g, p.epKey));
    }
    final accent = uiTheme.accentColor;
    final r = uiTheme.borderRadius(12 * scale);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: play),
          SizedBox(width: 8 * scale),
          Tooltip(
            message: 'Ще',
            child: Semantics(
              button: true,
              label: 'Ще: серії, джерела, якість і плеєр',
              child: Material(
                color: accent.withValues(alpha: uiTheme.isLight ? 0.15 : 0.18),
                shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: accent.withValues(alpha: 0.65))),
                child: InkWell(
                  borderRadius: r,
                  splashColor: Colors.transparent,
                  highlightColor: uiTheme.touchHighlight,
                  hoverColor: uiTheme.hoverOverlay,
                  onTap: () => _openMenu(t, groups),
                  child: SizedBox(
                    width: AppPlatform.isMobile ? AppPlatform.touchTarget : 44 * scale,
                    child: Icon(Symbols.more_vert_rounded, color: uiTheme.isLight ? accent : Colors.white, size: 24 * scale, weight: 400),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Натиснули «Дивитись», коли дивитись ще нема чого: джерела вимкнено — модалка, інакше пояснення під кнопкою
  Future<void> _noTarget() async {
    if (_service.registry.enabled.isEmpty) {
      final open = await WatchDialogs.noSources(context, scale: _scale);
      if (open && mounted) await _openSources();
      return;
    }
    setState(() => _notice = _load.busy
        ? 'Ще шукаю озвучки, зачекайте мить.'
        : 'Не знайшли, де це дивитись українською. Спробуйте «Оновити» або змініть джерела.');
  }

  // Ліцензований тайтл ----------------------------------------------------------

  Widget _licenseCard(WatchTitle t) {
    final scale = _scale;
    final license = t.license;
    final links = license?.links ?? const <({String title, String url})>[];
    final holder = license?.holder;
    // «Все одно дивитись» має сенс, лише якщо є що показувати (або ще шукаємо)
    final canWatch = t.groups.isNotEmpty || _load.busy;
    return AppCard(
      scale: scale,
      radius: 12,
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.verified_rounded, color: uiTheme.accentColor, size: 24 * scale, fill: 1, weight: 300),
              SizedBox(width: 10 * scale),
              Expanded(child: Text('Ліцензовано в Україні', style: hikkaStyle(15 * scale, weight: FontWeight.bold))),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            holder == null || holder.isEmpty
                ? 'Це аніме має офіційну ліцензію. Дивіться його легально: так ви підтримуєте тих, хто привозить аніме в Україну.'
                : 'Правовласник: $holder. Дивіться це аніме легально: так ви підтримуєте тих, хто привозить аніме в Україну.',
            style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.45),
          ),
          if (links.isNotEmpty) ...[
            SizedBox(height: 14 * scale),
            Wrap(
              spacing: 10 * scale,
              runSpacing: 8 * scale,
              children: [
                for (int i = 0; i < links.length; i++)
                  i == 0
                      ? AppAccentButton(
                        scale: scale,
                        icon: Symbols.open_in_new_rounded,
                        label: links[i].title.isEmpty ? 'Дивитись легально' : links[i].title,
                        onTap: () => HikkaNav.instance.openLink(links[i].url),
                      )
                      : AppSecondaryButton(
                        scale: scale,
                        expand: false,
                        icon: Symbols.open_in_new_rounded,
                        label: links[i].title.isEmpty ? 'Ще одне посилання' : links[i].title,
                        onTap: () => HikkaNav.instance.openLink(links[i].url),
                      ),
              ],
            ),
          ],
          if (canWatch) ...[SizedBox(height: 8 * scale), QuietAction(label: 'Все одно дивитись', scale: scale, onTap: () => _confirmLicensed(t))],
        ],
      ),
    );
  }

  Widget _licensedBanner(WatchTitle t) {
    final scale = _scale;
    final links = t.license?.links ?? const <({String title, String url})>[];
    return Padding(
      padding: EdgeInsets.only(bottom: 12 * scale),
      child: WatchCallout(
        scale: scale,
        icon: Symbols.verified_rounded,
        color: uiTheme.accentColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ліцензовано в Україні. Якщо можете, дивіться легально.', style: hikkaStyle(12.5 * scale, height: 1.4)),
            if (links.isNotEmpty) ...[
              SizedBox(height: 8 * scale),
              Wrap(
                spacing: 8 * scale,
                runSpacing: 6 * scale,
                children: [
                  for (final l in links)
                    HikkaChip(
                      label: l.title.isEmpty ? 'Правовласник' : l.title,
                      scale: scale,
                      icon: Symbols.open_in_new_rounded,
                      onTap: () => HikkaNav.instance.openLink(l.url),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Порожньо / завантаження -----------------------------------------------------

  Widget _noGroups(WatchTitle t) {
    final scale = _scale;
    if (_load.busy) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * scale),
        child: Row(
          children: [
            SizedBox(width: 18 * scale, height: 18 * scale, child: CircularProgressIndicator(strokeWidth: 2.2, color: uiTheme.accentColor)),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text('Шукаю озвучки: ${_load.pending.map(_sourceName).join(', ')}…', style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
            ),
          ],
        ),
      );
    }
    final allOff = _service.registry.enabled.isEmpty;
    return AppCard(
      scale: scale,
      radius: 12,
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.video_library_rounded, color: uiTheme.textDarkMuted, size: 24 * scale, weight: 300),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Text(
                  allOff ? 'Усі джерела вимкнено' : 'Не знайшли, де це дивитись українською',
                  style: hikkaStyle(14 * scale, weight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (allOff) _noteLine(Symbols.info_rounded, watchWarnColor(), 'Увімкніть хоча б одне джерело перегляду.'),
          ..._offerNotes(t, always: true),
          SizedBox(height: 12 * scale),
          Wrap(
            spacing: 10 * scale,
            runSpacing: 8 * scale,
            children: [
              if (!allOff) AppSecondaryButton(scale: scale, expand: false, icon: Symbols.refresh_rounded, label: 'Спробувати ще', onTap: _restart),
              AppSecondaryButton(scale: scale, expand: false, icon: Symbols.tune_rounded, label: 'Джерела', onTap: _openSources),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noteLine(IconData icon, Color color, String text) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.only(top: 8 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(top: 1 * scale), child: Icon(icon, color: color, size: 16 * scale, weight: 300)),
          SizedBox(width: 8 * scale),
          Expanded(child: Text(text, style: hikkaStyle(12 * scale, color: uiTheme.textMuted, height: 1.4))),
        ],
      ),
    );
  }

  /// Що ще відомо про джерела: сторінка без серій (з поясненням розбіжності), помилки, джерела, що ще шукають
  List<Widget> _offerNotes(WatchTitle t, {bool always = false}) {
    final out = <Widget>[];
    for (final o in t.offers) {
      if (o.groups.isNotEmpty) continue;
      final c = checkEpisodes(const [], _load.hikka);
      out.add(
        _noteLine(
          Symbols.info_rounded,
          watchWarnColor(),
          '${o.source.name}: ${c.hasNote ? c.note : 'сторінку знайдено, але серій на ній поки немає.'}',
        ),
      );
    }
    t.errors.forEach((id, message) => out.add(_noteLine(Symbols.cloud_off_rounded, uiTheme.textDarkMuted, '${_sourceName(id)}: $message')));
    if (_load.busy && !always) {
      out.add(_noteLine(Symbols.hourglass_top_rounded, uiTheme.textDarkMuted, 'Ще шукаю: ${_load.pending.map(_sourceName).join(', ')}…'));
    }
    return out;
  }

  // Основний вміст --------------------------------------------------------------

  Widget _content(WatchTitle t, List<WatchGroup> groups) {
    final g = _load.defaultGroup(_store) ?? groups.first;
    final check = _load.checkOf(g);
    final scale = _scale;
    final keys = episodeKeysOf(g);
    final watched = _store.watched(t.animeKey);
    final point = continuePoint(keys, watched, _store.last(t.animeKey)?.epKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t.licensed) _licensedBanner(t),
        _actions(t, g, keys, watched, point),
        _variants(t, groups, g),
        // «Не всі серії» / «озвучено не всі» і так видно в рядку озвучки (жовта іконка й «12 з 170»): плашку лишаємо для нумерації та OVA
        if (check.hasNote && check.level != EpisodeCheckLevel.incomplete && check.level != EpisodeCheckLevel.lag) ...[
          SizedBox(height: 10 * scale),
          EpisodeNote(scale: scale, check: check),
        ],
      ],
    );
  }

  /// Усі знайдені озвучки й субтитри — випадний список просто на сторінці (без окремого вікна)
  Widget _variants(WatchTitle t, List<WatchGroup> groups, WatchGroup current) {
    final byId = {for (final v in groups) v.id: v};
    return AppDropdown<String>(
      scale: _scale,
      value: current.id,
      options: [for (final v in groups) _option(v)],
      onChanged: (id) {
        final v = byId[id];
        if (v == null) return;
        _store.setPreferredGroup(t.animeKey, v.id);
        _store.setFavoriteChoice(choiceKeyOf(v));
      },
    );
  }

  /// Пункт списку: аватарка команди, назва, а під нею іконка виду (озвучення / субтитри), «N з M сер.» і дата оновлення
  AppDropdownOption<String> _option(WatchGroup v) {
    final check = _load.checkOf(v);
    final warn = episodeCheckWarns(check);
    final upd = v.updatedAt;
    final now = DateTime.now();
    final parts = [
      '${check.summary} сер.',
      if (upd != null) 'оновлено ${upd.day.toString().padLeft(2, '0')}.${upd.month.toString().padLeft(2, '0')}${upd.year != now.year ? '.${upd.year}' : ''}',
    ];
    return AppDropdownOption<String>(
      value: v.id,
      label: v.fullLabel,
      title: v.teamLabel,
      subtitle: parts.join(' · '),
      subtitleIcon: warn ? Symbols.warning_rounded : (v.isSub ? Symbols.subtitles_rounded : Symbols.record_voice_over_rounded),
      subtitleColor: warn ? watchWarnColor() : null,
      leading: HikkaPoster(url: v.teams.isEmpty ? null : v.teams.first.avatarUrl, scale: _scale, aspect: 1, radius: 14, icon: Symbols.groups_rounded),
    );
  }

  /// Другорядне під головною кнопкою: «З першої серії» і лічильник переглянутого
  Widget _actions(WatchTitle t, WatchGroup g, List<String> keys, Set<String> watched, ContinuePoint p) {
    final scale = _scale;
    final seen = keys.where(watched.contains).length;
    final fromStart = p.started && p.index > 0;
    if (!fromStart && seen == 0) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 14 * scale),
      child: Wrap(
        spacing: 12 * scale,
        runSpacing: 10 * scale,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (fromStart)
            AppSecondaryButton(scale: scale, expand: false, icon: Symbols.first_page_rounded, label: 'З першої серії', onTap: () => _play(t, g, keys.first)),
          if (seen > 0) Text('Переглянуто $seen з ${keys.length}', style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted)),
        ],
      ),
    );
  }

  /// Сітка серій (живе в модалці «Серії»); [onStart] закриває її перед запуском, [refresh] перемальовує після «Показати всі»
  Widget _episodes(WatchTitle t, WatchGroup g, List<String> keys, Set<String> watched, ContinuePoint p, {VoidCallback? onStart, VoidCallback? refresh}) {
    final scale = _scale;
    final total = g.episodes.length;
    var from = 0, to = total;
    final collapsed = !_allEpisodes && total > _cap;
    if (collapsed) {
      from = (p.index - 8).clamp(0, total - _cap);
      to = from + _cap;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > _cap)
          Align(
            alignment: Alignment.centerRight,
            child: HikkaLinkButton(
              label: collapsed ? 'Показати всі ($total)' : 'Згорнути',
              scale: scale,
              onTap: () {
                setState(() => _allEpisodes = !_allEpisodes);
                refresh?.call();
              },
            ),
          ),
        Wrap(
          spacing: 6 * scale,
          runSpacing: 6 * scale,
          children: [
            for (int i = from; i < to; i++)
              _episodeButton(t, g, i, keys[i], watched: watched.contains(keys[i]), isNext: i == p.index && !p.allWatched, onStart: onStart),
          ],
        ),
        SizedBox(height: 8 * scale),
        Text(
          collapsed
              ? 'Показано серії ${from + 1}–$to з $total. Утримуйте номер серії, щоб позначити її переглянутою.'
              : 'Утримуйте номер серії (на комп’ютері — права кнопка миші), щоб позначити її переглянутою.',
          style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted, height: 1.4),
        ),
      ],
    );
  }

  Widget _episodeButton(WatchTitle t, WatchGroup g, int i, String key, {required bool watched, required bool isNext, VoidCallback? onStart}) {
    final scale = _scale;
    final r = uiTheme.borderRadius(8 * scale);
    final label = episodeLabel(g.episodes[i], i);
    final fg = isNext ? uiTheme.accentColor : (watched ? uiTheme.textDarkMuted : uiTheme.textPrimary);
    void toggle() => _store.setWatched(t.animeKey, key, !watched);
    final name = g.episodes[i].name;
    final button = Material(
      color: isNext ? uiTheme.accentWash : uiTheme.bgElevated,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: isNext ? uiTheme.accentBorder : uiTheme.borderSubtle)),
      child: InkWell(
        borderRadius: r,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        onTap: () {
          onStart?.call();
          _play(t, g, key);
        },
        onLongPress: toggle,
        onSecondaryTap: toggle,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: AppPlatform.isMobile ? AppPlatform.touchTarget : 44 * scale,
            minHeight: AppPlatform.isMobile ? AppPlatform.touchTarget : 34 * scale,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: hikkaStyle(12.5 * scale, color: fg, weight: isNext ? FontWeight.bold : FontWeight.w600)),
                if (watched) ...[SizedBox(width: 4 * scale), Icon(Symbols.check_rounded, color: fg, size: 13 * scale, weight: 500)],
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Серія $label${watched ? ', переглянуто' : ''}',
      child: name.isEmpty || AppPlatform.isMobile ? button : Tooltip(message: name, child: button),
    );
  }

  // Меню «⋮» ---------------------------------------------------------------------

  /// Сторінка тайтла на сайті джерела. У Mikai адреса має вигляд `/anime/<id>-<назва>`: беремо готове посилання
  /// з даних Hikka (там воно точне), а без нього — `/anime/<id>`
  String _siteUrl(WatchOffer offer) {
    if (offer.source.id == 'mikai') {
      final id = offer.anime.url;
      for (final l in widget.anime.external) {
        if (l.isWatch && Uri.tryParse(l.url)?.host.endsWith('mikai.me') == true && RegExp('/anime/$id(-|\$|/)').hasMatch(l.url)) return l.url;
      }
    }
    return offer.webUrl;
  }

  /// Усе другорядне: серії, команда, джерела (з якістю й плеєром за замовчуванням), оновлення, сайт
  Future<void> _openMenu(WatchTitle t, List<WatchGroup> groups) async {
    final scale = _scale;
    final g = groups.isEmpty ? null : (_load.defaultGroup(_store) ?? groups.first);
    final offer = g == null ? null : t.offerOfGroup(g);
    final keys = g == null ? const <String>[] : episodeKeysOf(g);
    final seen = keys.where(_store.watched(t.animeKey).contains).length;
    final canRefresh = !_load.busy && _service.registry.enabled.isNotEmpty;
    final notes = _offerNotes(t);
    final choice = await AppDialogs.show<String>(
      context,
      builder: (ctx) => WatchDialogFrame(
        scale: scale,
        title: 'Ще',
        icon: Symbols.more_horiz_rounded,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (g != null) _MenuRow(scale: scale, icon: Symbols.format_list_numbered_rounded, label: 'Серії', hint: seen > 0 ? '${keys.length} · переглянуто $seen' : '${keys.length}', onTap: () => Navigator.of(ctx).pop('episodes')),
            if (g != null && g.teams.isNotEmpty)
              _MenuRow(scale: scale, icon: Symbols.groups_rounded, label: g.teams.length == 1 ? 'Про команду' : 'Про команди', onTap: () => Navigator.of(ctx).pop('teams')),
            _MenuRow(scale: scale, icon: Symbols.tune_rounded, label: 'Джерела, якість і плеєр', onTap: () => Navigator.of(ctx).pop('sources')),
            if (canRefresh) _MenuRow(scale: scale, icon: Symbols.refresh_rounded, label: 'Оновити пошук', onTap: () => Navigator.of(ctx).pop('refresh')),
            if (offer != null) _MenuRow(scale: scale, icon: Symbols.open_in_new_rounded, label: 'Відкрити на сайті', hint: _sourceName(g!.sourceId), onTap: () => Navigator.of(ctx).pop('site')),
            ...notes,
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'episodes':
        if (g != null) await _openEpisodes(t, g);
      case 'teams':
        if (g != null) await _showTeams(g);
      case 'sources':
        await _openSources();
      case 'refresh':
        _restart();
      case 'site':
        if (offer != null) HikkaNav.instance.openLink(_siteUrl(offer));
    }
  }

  Future<void> _openEpisodes(WatchTitle t, WatchGroup g) {
    return AppDialogs.show<void>(
      context,
      builder: (ctx) => WatchDialogFrame(
        scale: _scale,
        title: 'Серії',
        icon: Symbols.format_list_numbered_rounded,
        body: StatefulBuilder(
          builder: (ctx2, setDialog) => ListenableBuilder(
            listenable: _store,
            builder: (ctx3, _) {
              final keys = episodeKeysOf(g);
              final watched = _store.watched(t.animeKey);
              final point = continuePoint(keys, watched, _store.last(t.animeKey)?.epKey);
              return _episodes(t, g, keys, watched, point, onStart: () => Navigator.of(ctx).pop(), refresh: () => setDialog(() {}));
            },
          ),
        ),
      ),
    );
  }
}

/// Рядок меню «Ще»: іконка, назва, дрібна підказка праворуч; не менше 48 dp заввишки
class _MenuRow extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;

  const _MenuRow({required this.scale, required this.icon, required this.label, required this.onTap, this.hint});

  @override
  Widget build(BuildContext context) => AppMenuRow(scale: scale, icon: icon, title: label, value: hint, onTap: onTap);
}
