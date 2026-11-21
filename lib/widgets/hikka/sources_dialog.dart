import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/source_prefs.dart';
import '../../services/source_registry.dart';
import '../../services/storage_service.dart';
import '../../services/sources/ua/mikai_source.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import '../settings_kit.dart';
import 'hikka_common.dart';
import 'hikka_watch_dialogs.dart';

/// "Джерела перегляду": which sites search for dubs and subtitles, the highest quality, the default player,
/// an optional Mikai key. Changes apply immediately; the key is saved with a small delay after typing.
class SourcesDialog extends StatelessWidget {
  final double scale;
  final SourceRegistry registry;

  const SourcesDialog({super.key, required this.scale, required this.registry});

  static Future<void> show(BuildContext context, {required double scale, required SourceRegistry registry}) {
    return AppDialogs.show<void>(context, builder: (ctx) => SourcesDialog(scale: scale, registry: registry));
  }

  /// A fingerprint of the settings the search result depends on (which sites and which key): if it changed, the search should be repeated
  static String searchSignature(SourceRegistry registry) =>
      '${[for (final s in registry.enabled) s.id].join(',')}|${registry.prefs.mikaiKey}';

  /// Players that can be chosen by default (empty is "Авто": by the source's order)
  static const List<String> hosters = ['', 'Moon'];

  @override
  Widget build(BuildContext context) => WatchDialogFrame(
        scale: scale,
        title: 'Джерела перегляду',
        icon: Symbols.tune_rounded,
        body: SourcesSettings(scale: scale, registry: registry),
      );
}

/// The content of "Джерела перегляду" itself without a frame: shown by both the [SourcesDialog] window and the settings' "Каталог" tab
class SourcesSettings extends StatefulWidget {
  final double scale;
  final SourceRegistry registry;

  /// [heading]: show the "Сайти" heading with an explanation (the settings tab has none: the sites are labeled anyway)
  final bool heading;

  const SourcesSettings({super.key, required this.scale, required this.registry, this.heading = true});

  @override
  State<SourcesSettings> createState() => _SourcesSettingsState();
}

class _SourcesSettingsState extends State<SourcesSettings> {
  late List<String> _priority = StorageService.getWatchTeamPriority();

  /// All Mikai dub teams (from the list saved on disk, refreshed once a day)
  List<MikaiTeam> _remote = const [];
  bool _teamsLoading = true;

  double get _scale => widget.scale;
  SourcePrefs get _prefs => widget.registry.prefs;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }


  Future<void> _loadTeams() async {
    final mikai = widget.registry.all.whereType<MikaiSource>().firstOrNull;
    if (mikai == null) {
      setState(() => _teamsLoading = false);
      return;
    }
    try {
      final list = await mikai.allTeams();
      if (!mounted) return;
      setState(() {
        _remote = list;
        _teamsLoading = false;
      });
    } catch (_) {
      // no network and no saved list: familiar teams and manual input remain
      if (mounted) setState(() => _teamsLoading = false);
    }
  }

  void _setPriority(List<String> v) {
    setState(() => _priority = v);
    StorageService.saveWatchTeamPriority(v);
  }


  void _moveTeam(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _priority.length) return;
    final l = [..._priority];
    final x = l.removeAt(i);
    l.insert(j, x);
    _setPriority(l);
  }

  Widget _watchedBlock(double scale) {
    final pct = StorageService.getWatchedPercent();
    const options = [70, 80, 85, 90, 95, 100];
    return SettingsGroup(
      scale: scale,
      label: 'Прогрес',
      rows: [
        SettingsChoiceRow<int>(
          scale: scale,
          icon: Symbols.task_alt_rounded,
          title: 'Серія вважається переглянутою після',
          subtitle: 'Тоді ж прогрес передається на Hikka',
          options: [for (final o in options) (o, '$o%')],
          value: options.contains(pct) ? pct : 85,
          onChanged: (v) => setState(() => StorageService.saveWatchedPercent(v)),
        ),
        SettingsToggleRow(
          scale: scale,
          icon: Symbols.sports_score_rounded,
          title: 'Зараховувати за ендінґом',
          subtitle: 'Якщо в озвучці є мітка ендінґу, серія вважається переглянутою з його початку',
          value: StorageService.getWatchedByEnding(),
          onChanged: (v) => setState(() => StorageService.saveWatchedByEnding(v)),
        ),
      ],
    );
  }

  /// Team avatar by name (Mikai teams only)
  String? _avatarOf(String name) {
    final n = name.toLowerCase();
    for (final t in _remote) {
      if (t.name.toLowerCase() == n) return t.avatarUrl;
    }
    return null;
  }

  /// All known teams: from Mikai (by popularity), familiar ones from other sites and already added manually; without repeats
  List<(String, String?)> get _allTeams {
    final all = <(String, String?)>[
      for (final t in _remote) (t.name, t.avatarUrl),
      for (final t in StorageService.getKnownTeams()) (t, null),
      for (final t in _priority) (t, null),
    ];
    final seen = <String>{};
    return [for (final t in all) if (seen.add(t.$1.toLowerCase())) (t.$1, t.$2 ?? _avatarOf(t.$1))];
  }

  /// Adds a team to the end of the priority or removes it if it is already there
  void _toggleTeam(String name) {
    final i = _priority.indexWhere((x) => x.toLowerCase() == name.toLowerCase());
    _setPriority(i < 0 ? [..._priority, name] : ([..._priority]..removeAt(i)));
  }

  Widget _priorityBlock(double scale) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 20 * scale,
          color: uiTheme.textMuted,
          onPressed: onTap,
          icon: Icon(icon),
        );
    final teams = _allTeams;
    final chosen = {for (final t in teams) if (_priority.any((x) => x.toLowerCase() == t.$1.toLowerCase())) t.$1};
    return SettingsGroup(
      scale: scale,
      label: 'Озвучення',
      hint: 'Зверху — найвищий пріоритет. Для кнопки «Дивитись» вибирається найвища команда, у якої є потрібна серія.',
      rows: [
        SettingsToggleRow(
          scale: scale,
          icon: Symbols.mic_rounded,
          title: 'Спершу повні озвучення',
          subtitle: 'Озвучення без початку, без кінця чи з пропусками стоять нижче за повні незалежно від пріоритету',
          value: StorageService.getPreferFullDub(),
          onChanged: (v) => setState(() => StorageService.savePreferFullDub(v)),
        ),
        for (var i = 0; i < _priority.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(16 * scale, 6 * scale, 6 * scale, 6 * scale),
            child: Row(
              children: [
                SizedBox(width: 22 * scale, child: Text('${i + 1}', style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted))),
                SizedBox(width: 34 * scale, child: HikkaPoster(url: _avatarOf(_priority[i]), scale: scale, aspect: 1, radius: 17, icon: Symbols.groups_rounded)),
                SizedBox(width: 10 * scale),
                Expanded(child: Text(_priority[i], style: hikkaStyle(14 * scale), overflow: TextOverflow.ellipsis)),
                btn(Symbols.arrow_upward_rounded, 'Вище', i == 0 ? null : () => _moveTeam(i, -1)),
                btn(Symbols.arrow_downward_rounded, 'Нижче', i == _priority.length - 1 ? null : () => _moveTeam(i, 1)),
                btn(Symbols.close_rounded, 'Прибрати', () => _setPriority([..._priority]..removeAt(i))),
              ],
            ),
          ),
        // The key keeps the open list alive while rows above it are added (a new team)
        Padding(
          key: const ValueKey('team-search'),
          padding: EdgeInsets.all(12 * scale),
          child: AppSearchDropdown<String>(
            scale: scale,
            value: '',
            multiSelected: chosen,
            keyboardReserve: 0, // the settings page adds the slack under the block itself
            placeholder: _teamsLoading && teams.isEmpty ? 'Завантаження команд…' : 'Команди озвучення',
            searchHint: 'Назва команди',
            options: [
              for (final t in teams)
                AppDropdownOption<String>(
                  value: t.$1,
                  label: t.$1,
                  leading: SizedBox(width: 28 * scale, child: HikkaPoster(url: t.$2, scale: scale, aspect: 1, radius: 14, icon: Symbols.groups_rounded)),
                ),
            ],
            onChanged: _toggleTeam,
            onAddCustom: (name) {
              if (!_priority.any((x) => x.toLowerCase() == name.toLowerCase())) _setPriority([..._priority, name]);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return ListenableBuilder(
        listenable: _prefs,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Site switches are needed only when there are several sources (currently only Mikai)
            if (widget.registry.all.length > 1)
              SettingsGroup(
                scale: scale,
                label: 'Сайти',
                hint: widget.heading ? 'Де шукати українські озвучки й субтитри. Вимкнені сайти не опитуються.' : null,
                rows: [
                  for (final s in widget.registry.all)
                    SettingsToggleRow(
                      scale: scale,
                      icon: Symbols.public_rounded,
                      title: s.name,
                      subtitle: '${s.id == 'mikai' ? 'Основне джерело: знає команди озвучення й серії. ' : ''}${s.about}'.trim(),
                      value: _prefs.isEnabled(s.id),
                      onChanged: (v) => _prefs.setEnabled(s.id, v),
                    ),
                ],
              ),
            SettingsGroup(
              scale: scale,
              label: 'Перегляд',
              rows: [
                SettingsChoiceRow<int>(
                  scale: scale,
                  icon: Symbols.high_quality_rounded,
                  title: 'Максимальна якість відео',
                  subtitle: 'Можна змінити й під час перегляду',
                  options: [for (final h in SourcePrefs.heights) (h, SourcePrefs.heightLabel(h))],
                  value: _prefs.maxHeight,
                  onChanged: (v) => _prefs.maxHeight = v,
                ),
                SettingsChoiceRow<String>(
                  scale: scale,
                  icon: Symbols.smart_display_rounded,
                  title: 'Плеєр за замовчуванням',
                  subtitle: 'Якщо серія доступна в Moon, використовується він, інакше — інший наявний',
                  options: [for (final h in SourcesDialog.hosters) (h, h.isEmpty ? 'Авто' : h)],
                  value: SourcesDialog.hosters.contains(_prefs.hoster) ? _prefs.hoster : '',
                  onChanged: (v) => _prefs.hoster = v,
                ),
              ],
            ),
            _watchedBlock(scale),
            _priorityBlock(scale),
            SizedBox(height: 4 * scale),
          ],
        ),
    );
  }
}
