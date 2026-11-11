import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_nav.dart';
import '../../services/sources/ua/mikai_source.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// Діалоги блоку «Дивитись»: застереження про ліцензію та відомості про команду озвучення.
class WatchDialogs {
  const WatchDialogs._();

  /// «Тричі подумайте»: `true` — людина все одно хоче дивитись на неофіційних джерелах.
  /// Головна кнопка веде до легального перегляду, а «все одно» — тиха.
  static Future<bool> confirmLicensed(BuildContext context, {required double scale, MikaiLicense? license}) async {
    final r = await AppDialogs.show<bool>(context, builder: (ctx) => _LicenseDialog(scale: scale, license: license));
    return r == true;
  }

  /// Усі джерела перегляду вимкнено: `true` — людина хоче відкрити налаштування джерел
  static Future<bool> noSources(BuildContext context, {required double scale}) async {
    final r = await AppDialogs.show<bool>(context, builder: (ctx) => _NoSourcesDialog(scale: scale));
    return r == true;
  }

  /// Відомості про команди: опис, кількість тайтлів, посилання на соцмережі
  static Future<void> teams(BuildContext context, {required double scale, required List<MikaiTeam> teams, MikaiSource? source}) {
    return AppDialogs.show<void>(context, builder: (ctx) => _TeamsDialog(scale: scale, teams: teams, source: source));
  }

  /// Підпис посилання команди за ключем з API
  static String linkLabel(String key) {
    switch (key.toLowerCase()) {
      case 'telegram':
        return 'Telegram';
      case 'youtube':
        return 'YouTube';
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      case 'twitter':
      case 'x':
        return 'X';
      case 'facebook':
        return 'Facebook';
      case 'discord':
        return 'Discord';
      case 'patreon':
        return 'Patreon';
      case 'site':
      case 'website':
      case 'web':
        return 'Сайт';
      default:
        return key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);
    }
  }
}

/// Спільна оболонка діалогів перегляду: заголовок із закриттям, прокручуваний вміст, ряд кнопок
class WatchDialogFrame extends StatefulWidget {
  final double scale;
  final String title;
  final IconData icon;
  final Widget body;
  final List<Widget> actions;

  const WatchDialogFrame({super.key, required this.scale, required this.title, required this.icon, required this.body, this.actions = const []});

  @override
  State<WatchDialogFrame> createState() => _WatchDialogFrameState();
}

class _WatchDialogFrameState extends State<WatchDialogFrame> {
  final ScrollController _scroll = AppSmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final mq = MediaQuery.of(context);
    final phone = AppPlatform.isMobile;
    final width = phone ? (mq.size.width - 32).clamp(280.0, 480.0) : 480 * scale;
    final maxHeight = mq.size.height - (phone ? mq.padding.vertical + 32 : 80);
    final pad = phone ? 22.0 : 26 * scale;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            // Як вікно в плеєрі: поверхня панелі, великий радіус, без розділювачів
            color: uiTheme.colors.drawerBg,
            borderRadius: uiTheme.borderRadius(22 * scale),
            border: Border.all(color: uiTheme.colors.drawerBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.14 : 0.60),
                blurRadius: 32 * scale,
                offset: Offset(0, 10 * scale),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 10 * scale, pad / 2, 2 * scale),
                child: Row(
                  children: [
                    Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(17 * scale, weight: FontWeight.bold))),
                    HikkaIconButton(icon: Symbols.close_rounded, tooltip: 'Закрити', scale: scale, onTap: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              Flexible(
                child: AppScrollbar(
                  scale: scale,
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 12 * scale),
                    child: widget.body,
                  ),
                ),
              ),
              if (widget.actions.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 16 * scale),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10 * scale,
                    runSpacing: 8 * scale,
                    children: widget.actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Тиха текстова дія (не кнопка): для вибору, який ми не заохочуємо
class QuietAction extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback onTap;

  const QuietAction({super.key, required this.label, required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: uiTheme.borderRadius(8 * scale),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppPlatform.isMobile ? AppPlatform.touchTarget : 32 * scale),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.textDarkMuted,
                fontSize: 12.5 * scale,
                decoration: TextDecoration.underline,
                decorationColor: uiTheme.textDarkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseDialog extends StatelessWidget {
  final double scale;
  final MikaiLicense? license;

  const _LicenseDialog({required this.scale, this.license});

  @override
  Widget build(BuildContext context) {
    final links = license?.links ?? const [];
    final holder = license?.holder;
    return WatchDialogFrame(
      scale: scale,
      title: 'Тричі подумайте',
      icon: Symbols.gavel_rounded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            holder == null || holder.isEmpty ? 'Цей тайтл ліцензовано в Україні.' : 'Цей тайтл ліцензовано в Україні. Правовласник: $holder.',
            style: hikkaStyle(13.5 * scale, weight: FontWeight.w600, height: 1.4),
          ),
          SizedBox(height: 10 * scale),
          Text(
            'Перегляд на неофіційних сайтах відбирає хліб у тих, хто працює легально, і гальмує ліцензування аніме в Україні: що менше людей дивляться легально, то менше нових тайтлів вирішують ліцензувати.',
            style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.45),
          ),
          SizedBox(height: 10 * scale),
          Text(
            links.isEmpty
                ? 'Якщо є можливість, шукайте цей тайтл на офіційних платформах.'
                : 'Якщо є можливість, дивіться за посиланнями правовласника.',
            style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.45),
          ),
        ],
      ),
      actions: [
        QuietAction(label: 'Все одно дивитись', scale: scale, onTap: () => Navigator.of(context).pop(true)),
        AppAccentButton(
          scale: scale,
          icon: links.isEmpty ? Symbols.arrow_back_rounded : Symbols.open_in_new_rounded,
          label: links.isEmpty ? 'Зрозуміло' : 'Дивитись легально',
          onTap: () {
            Navigator.of(context).pop(false);
            if (links.isNotEmpty) HikkaNav.instance.openLink(links.first.url);
          },
        ),
      ],
    );
  }
}

class _NoSourcesDialog extends StatelessWidget {
  final double scale;

  const _NoSourcesDialog({required this.scale});

  @override
  Widget build(BuildContext context) {
    return WatchDialogFrame(
      scale: scale,
      title: 'Немає джерел перегляду',
      icon: Symbols.warning_rounded,
      body: Text(
        'Усі джерела вимкнено, тож нема звідки брати серії. Увімкніть хоча б одне — і кнопка «Дивитись» одразу запрацює.',
        style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.45),
      ),
      actions: [
        QuietAction(label: 'Закрити', scale: scale, onTap: () => Navigator.of(context).pop(false)),
        AppAccentButton(scale: scale, icon: Symbols.tune_rounded, label: 'Відкрити джерела', onTap: () => Navigator.of(context).pop(true)),
      ],
    );
  }
}

class _TeamsDialog extends StatelessWidget {
  final double scale;
  final List<MikaiTeam> teams;
  final MikaiSource? source;

  const _TeamsDialog({required this.scale, required this.teams, this.source});

  @override
  Widget build(BuildContext context) {
    return WatchDialogFrame(
      scale: scale,
      title: teams.length == 1 ? 'Команда' : 'Команди',
      icon: Symbols.groups_rounded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < teams.length; i++) ...[
            if (i > 0) Divider(height: 28 * scale, color: uiTheme.borderSubtle),
            _TeamBlock(scale: scale, team: teams[i], source: source),
          ],
        ],
      ),
    );
  }
}

class _TeamBlock extends StatefulWidget {
  final double scale;
  final MikaiTeam team;
  final MikaiSource? source;

  const _TeamBlock({required this.scale, required this.team, this.source});

  @override
  State<_TeamBlock> createState() => _TeamBlockState();
}

class _TeamBlockState extends State<_TeamBlock> {
  late final Future<MikaiTeamInfo?> _info = _load();

  Future<MikaiTeamInfo?> _load() async {
    final s = widget.source;
    if (s == null) return null;
    try {
      return await s.teamInfo(widget.team);
    } catch (_) {
      return null; // без подробиць лишається назва й посилання на сторінку команди
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final team = widget.team;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 44 * scale, child: HikkaPoster(url: team.avatarUrl, scale: scale, aspect: 1, radius: 22, icon: Symbols.groups_rounded)),
            SizedBox(width: 12 * scale),
            Expanded(child: Text(team.name, style: hikkaStyle(15 * scale, weight: FontWeight.bold, height: 1.25))),
          ],
        ),
        SizedBox(height: 10 * scale),
        FutureBuilder<MikaiTeamInfo?>(
          future: _info,
          builder: (context, snap) {
            final info = snap.data;
            if (snap.connectionState != ConnectionState.done) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8 * scale),
                child: Row(
                  children: [
                    SizedBox(width: 16 * scale, height: 16 * scale, child: CircularProgressIndicator(strokeWidth: 2, color: uiTheme.accentColor)),
                    SizedBox(width: 10 * scale),
                    Text('Завантажую відомості…', style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted)),
                  ],
                ),
              );
            }
            final links = <MapEntry<String, String>>[
              ...?info?.links.entries,
              MapEntry('Mikai', info?.pageUrl ?? 'https://mikai.me/team/${team.slug}'),
            ];
            final desc = info?.description;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info != null)
                  Wrap(
                    spacing: 8 * scale,
                    runSpacing: 6 * scale,
                    children: [
                      if (info.hasVoice) HikkaChip(label: 'Озвучення', scale: scale, icon: Symbols.record_voice_over_rounded),
                      if (info.hasSubs) HikkaChip(label: 'Субтитри', scale: scale, icon: Symbols.subtitles_rounded),
                      if (info.animeCount > 0) HikkaChip(label: 'Тайтлів: ${info.animeCount}', scale: scale),
                    ],
                  ),
                if (desc != null && desc.isNotEmpty) ...[
                  SizedBox(height: 10 * scale),
                  Text(desc, maxLines: 8, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.45)),
                ],
                SizedBox(height: 12 * scale),
                Wrap(
                  spacing: 8 * scale,
                  runSpacing: 8 * scale,
                  children: [
                    for (final l in links)
                      HikkaChip(
                        label: WatchDialogs.linkLabel(l.key),
                        scale: scale,
                        icon: Symbols.open_in_new_rounded,
                        onTap: () => HikkaNav.instance.openLink(l.value),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
