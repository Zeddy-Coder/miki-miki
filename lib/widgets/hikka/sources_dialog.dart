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
import 'hikka_common.dart';
import 'hikka_watch_dialogs.dart';

/// «Джерела перегляду»: які сайти шукають озвучки й субтитри, найбільша якість, плеєр за замовчуванням,
/// необов'язковий ключ Mikai. Зміни застосовуються одразу; ключ зберігається з невеликою затримкою після набору.
class SourcesDialog extends StatelessWidget {
  final double scale;
  final SourceRegistry registry;

  const SourcesDialog({super.key, required this.scale, required this.registry});

  static Future<void> show(BuildContext context, {required double scale, required SourceRegistry registry}) {
    return AppDialogs.show<void>(context, builder: (ctx) => SourcesDialog(scale: scale, registry: registry));
  }

  /// Відбиток налаштувань, від яких залежить результат пошуку (які сайти й який ключ): змінився — пошук варто повторити
  static String searchSignature(SourceRegistry registry) =>
      '${[for (final s in registry.enabled) s.id].join(',')}|${registry.prefs.mikaiKey}';

  /// Плеєри, які можна вибрати за замовчуванням (порожній — «Авто»: за порядком джерела)
  static const List<String> hosters = ['', 'Moon'];

  @override
  Widget build(BuildContext context) => WatchDialogFrame(
        scale: scale,
        title: 'Джерела перегляду',
        icon: Symbols.tune_rounded,
        body: SourcesSettings(scale: scale, registry: registry),
      );
}

/// Сам вміст «Джерел перегляду» без рамки: його показують і вікно [SourcesDialog], і вкладка «Каталог» налаштувань
class SourcesSettings extends StatefulWidget {
  final double scale;
  final SourceRegistry registry;

  /// [heading] — показати заголовок «Сайти» з поясненням (у вкладці налаштувань його немає: сайти й так підписані)
  final bool heading;

  const SourcesSettings({super.key, required this.scale, required this.registry, this.heading = true});

  @override
  State<SourcesSettings> createState() => _SourcesSettingsState();
}

class _SourcesSettingsState extends State<SourcesSettings> {
  late List<String> _priority = StorageService.getWatchTeamPriority();

  /// Усі команди озвучення Mikai (зі збереженого на диску списку, оновлюється раз на добу)
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
      // немає мережі й збереженого списку: лишаються знайомі команди й ручний ввід
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Серія вважається переглянутою після', hint: 'Тоді ж прогрес передається на Hikka'),
        AppSegmentedBar<int>(
          scale: scale,
          selectedValue: options.contains(pct) ? pct : 85,
          options: [for (final o in options) AppSegmentOption(value: o, label: '$o%')],
          onSelected: (v) => setState(() => StorageService.saveWatchedPercent(v)),
        ),
        SizedBox(height: 10 * scale),
        HikkaToggleRow(
          scale: scale,
          title: 'Зараховувати за ендінґом',
          subtitle: 'Якщо в озвучці є мітка ендінґу, серія вважається переглянутою з його початку',
          value: StorageService.getWatchedByEnding(),
          onChanged: (v) => setState(() => StorageService.saveWatchedByEnding(v)),
        ),
      ],
    );
  }

  /// Аватарка команди за назвою (лише для команд Mikai)
  String? _avatarOf(String name) {
    final n = name.toLowerCase();
    for (final t in _remote) {
      if (t.name.toLowerCase() == n) return t.avatarUrl;
    }
    return null;
  }

  /// Усі відомі команди: з Mikai (за популярністю), знайомі з інших сайтів і вже додані вручну; без повторів
  List<(String, String?)> get _allTeams {
    final all = <(String, String?)>[
      for (final t in _remote) (t.name, t.avatarUrl),
      for (final t in StorageService.getKnownTeams()) (t, null),
      for (final t in _priority) (t, null),
    ];
    final seen = <String>{};
    return [for (final t in all) if (seen.add(t.$1.toLowerCase())) (t.$1, t.$2 ?? _avatarOf(t.$1))];
  }

  /// Додає команду в кінець пріоритету або прибирає, якщо вона вже там
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Пріоритет команд озвучення', hint: 'Зверху — найвищий пріоритет. Для кнопки «Дивитись» вибирається найвища команда, у якої є потрібна серія'),
        HikkaToggleRow(
          scale: scale,
          title: 'Спершу повні озвучення',
          subtitle: 'Озвучення без початку, без кінця чи з пропусками стоять нижче за повні незалежно від пріоритету',
          value: StorageService.getPreferFullDub(),
          onChanged: (v) => setState(() => StorageService.savePreferFullDub(v)),
        ),
        SizedBox(height: 10 * scale),
        for (var i = 0; i < _priority.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 4 * scale),
            child: Row(
              children: [
                SizedBox(width: 24 * scale, child: Text('${i + 1}', style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted))),
                SizedBox(width: 34 * scale, child: HikkaPoster(url: _avatarOf(_priority[i]), scale: scale, aspect: 1, radius: 17, icon: Symbols.groups_rounded)),
                SizedBox(width: 10 * scale),
                Expanded(child: Text(_priority[i], style: hikkaStyle(13 * scale), overflow: TextOverflow.ellipsis)),
                btn(Symbols.arrow_upward_rounded, 'Вище', i == 0 ? null : () => _moveTeam(i, -1)),
                btn(Symbols.arrow_downward_rounded, 'Нижче', i == _priority.length - 1 ? null : () => _moveTeam(i, 1)),
                btn(Symbols.close_rounded, 'Прибрати', () => _setPriority([..._priority]..removeAt(i))),
              ],
            ),
          ),
        SizedBox(height: 8 * scale),
        Builder(builder: (context) {
          final teams = _allTeams;
          final chosen = {for (final t in teams) if (_priority.any((x) => x.toLowerCase() == t.$1.toLowerCase())) t.$1};
          return AppSearchDropdown<String>(
            scale: scale,
            value: '',
            multiSelected: chosen,
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
          );
        }),
      ],
    );
  }

  Widget _title(String text, {String? hint}) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
          if (hint != null)
            Padding(
              padding: EdgeInsets.only(top: 2 * scale),
              child: Text(hint, style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted, height: 1.35)),
            ),
        ],
      ),
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
            // Перемикачі сайтів потрібні, лише коли джерел кілька (зараз є тільки Mikai)
            if (widget.registry.all.length > 1) ...[
              if (widget.heading) _title('Сайти', hint: 'Де шукати українські озвучки й субтитри. Вимкнені сайти не опитуються.'),
              for (final s in widget.registry.all) ...[
                HikkaToggleRow(
                  scale: scale,
                  title: s.name,
                  subtitle: '${s.id == 'mikai' ? 'Основне джерело: знає команди озвучення й серії. ' : ''}${s.about}'.trim(),
                  value: _prefs.isEnabled(s.id),
                  onChanged: (v) => _prefs.setEnabled(s.id, v),
                ),
                SizedBox(height: 14 * scale),
              ],
              SizedBox(height: 8 * scale),
            ],
            _title('Максимальна якість відео', hint: 'Можна змінити й під час перегляду'),
            AppSegmentedBar<int>(
              scale: scale,
              selectedValue: _prefs.maxHeight,
              options: [for (final h in SourcePrefs.heights) AppSegmentOption(value: h, label: SourcePrefs.heightLabel(h))],
              onSelected: (v) => _prefs.maxHeight = v,
            ),
            SizedBox(height: 22 * scale),
            _title('Плеєр за замовчуванням', hint: 'Якщо серія доступна в Moon, використовується він, інакше — інший наявний'),
            AppSegmentedBar<String>(
              scale: scale,
              selectedValue: SourcesDialog.hosters.contains(_prefs.hoster) ? _prefs.hoster : '',
              options: [for (final h in SourcesDialog.hosters) AppSegmentOption(value: h, label: h.isEmpty ? 'Авто' : h)],
              onSelected: (v) => _prefs.hoster = v,
            ),
            SizedBox(height: 22 * scale),
            _watchedBlock(scale),
            SizedBox(height: 22 * scale),
            _priorityBlock(scale),
            SizedBox(height: 4 * scale),
          ],
        ),
    );
  }
}
