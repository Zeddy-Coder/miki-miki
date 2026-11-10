import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_franchise.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';

/// Франшиза: усі тайтли за роками виходу або за групами (основна історія, побічні історії, рекапи…).
class HikkaFranchisePage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaFranchisePage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaFranchisePage> createState() => _HikkaFranchisePageState();
}

class _HikkaFranchisePageState extends State<HikkaFranchisePage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  FranchiseModel? _model;
  Object? _error;
  bool _missing = false;
  int _generation = 0;

  HikkaRoute get _route => widget.route;
  double get _scale => widget.scale;
  String get _mode => _route.memo['mode'] == 'groups' ? 'groups' : 'years';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_saveScroll);
    final cached = _route.memo['model'];
    if (cached is FranchiseModel) {
      _model = cached;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_saveScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _saveScroll() {
    if (_scroll.hasClients) _route.scroll = _scroll.offset;
  }

  void _load() {
    final gen = ++_generation;
    HikkaApi.instance.franchise(_route.slug).then<void>((data) {
      if (!mounted || gen != _generation) return;
      final model = FranchiseModel.build(data, _route.slug);
      if (model != null) _route.memo['model'] = model;
      setState(() {
        _model = model;
        _missing = model == null;
        _error = null;
      });
    }, onError: (Object e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    });
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  void _setMode(String mode) => setState(() {
        _route.memo['mode'] = mode;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });

  bool _visible(FranchiseNode n) => HikkaPrefs.instance.allowAdult || !n.anime.isAdult;

  // ── Вміст ──────────────────────────────────────────────────────────────────

  Widget _narrow(double pad, Widget child) => Padding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: hikkaReadableWidth(_scale)), child: child),
        ),
      );

  Widget _groupTitle(String text, {String? trailing}) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.only(top: 6 * scale, bottom: 10 * scale),
      child: Row(
        children: [
          Text(text, style: hikkaStyle(14 * scale, weight: FontWeight.bold, color: uiTheme.accentColor)),
          if (trailing != null) ...[
            SizedBox(width: 8 * scale),
            Text(trailing, style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted)),
          ],
        ],
      ),
    );
  }

  Widget _row(FranchiseModel model, FranchiseNode n, {String? label}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * _scale),
      child: HikkaAnimeRow(
        anime: n.anime,
        scale: _scale,
        label: label,
        highlighted: n.id == model.current.id,
      ),
    );
  }

  List<Widget> _byYears(FranchiseModel model, double pad) {
    final out = <Widget>[];
    for (final (label, nodes) in model.groupByYear()) {
      final visible = nodes.where(_visible).toList();
      if (visible.isEmpty) continue;
      out.add(_narrow(
        pad,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _groupTitle(label),
            for (final n in visible) _row(model, n, label: model.relationText(n)),
            SizedBox(height: 10 * _scale),
          ],
        ),
      ));
    }
    return out;
  }

  List<Widget> _byGroups(FranchiseModel model, double pad) {
    final out = <Widget>[];
    final chain = model.chain.where(_visible).toList();
    if (chain.isNotEmpty) {
      out.add(_narrow(
        pad,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _groupTitle(FranchiseGroup.sequel.label, trailing: chain.length > 1 ? '${chain.length}' : null),
            for (final n in chain) _row(model, n, label: model.chain.length > 1 ? 'Частина ${(n.chainIndex ?? 0) + 1}' : null),
            SizedBox(height: 10 * _scale),
          ],
        ),
      ));
    }
    for (final group in FranchiseGroup.values) {
      if (group == FranchiseGroup.sequel) continue;
      final nodes = model.nodes.where((n) => n.chainIndex == null && n.group == group && _visible(n)).toList();
      if (nodes.isEmpty) continue;
      out.add(_narrow(
        pad,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _groupTitle(group.label, trailing: '${nodes.length}'),
            for (final n in nodes) _row(model, n, label: n.relation?.label),
            SizedBox(height: 10 * _scale),
          ],
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final model = _model;
    if (model == null) {
      if (_error != null) return HikkaErrorView(scale: scale, error: _error!, onRetry: _retry);
      if (_missing) return AppEmptyState(scale: scale, icon: Symbols.account_tree_rounded, text: 'Франшизу не знайдено');
      return HikkaLoading(scale: scale, height: 320);
    }

    final pad = HikkaLayout.sidePad(context, scale);
    final count = model.nodes.where(_visible).length;
    final summary = '$count ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}'
        '${model.chain.length > 1 ? ' · основна історія: ${model.chain.length}' : ''}';

    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        _narrow(
          pad,
          Padding(
            padding: EdgeInsets.only(bottom: 14 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted)),
                SizedBox(height: 12 * scale),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 340 * (AppPlatform.isMobile ? 1.0 : scale)),
                  child: AppSegmentedBar<String>(
                    scale: scale,
                    selectedValue: _mode,
                    options: const [
                      AppSegmentOption(value: 'years', label: 'За роками'),
                      AppSegmentOption(value: 'groups', label: 'За групами'),
                    ],
                    onSelected: _setMode,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_mode == 'years') ..._byYears(model, pad) else ..._byGroups(model, pad),
      ],
    );
  }
}
