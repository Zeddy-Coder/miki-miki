import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_franchise.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart' show AppPlate;
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';

/// Franchise: all titles by release year or by group (main story, side stories, recaps…).
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

  // ── Content ──────────────────────────────────────────────────────────────────

  Widget _narrow(double pad, Widget child) => Padding(
        padding: EdgeInsets.fromLTRB(pad - 10 * _scale, 0, pad - 10 * _scale, 0),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: hikkaReadableWidth(_scale)), child: child),
        ),
      );

  /// A grey caption of a year or a group ("2023", "Основна історія · 3")
  Widget _groupTitle(String text, {String? trailing}) {
    final scale = _scale;
    return Padding(
      // The caption starts where the text of the page does; the rows below reach 10 further out on both sides
      padding: EdgeInsets.fromLTRB(10 * scale, 14 * scale, 10 * scale, 2 * scale),
      child: Text(trailing == null ? text : '$text · $trailing', style: hikkaStyle(13 * scale, color: AppTones.caption, weight: FontWeight.w700)),
    );
  }

  Widget _row(FranchiseModel model, FranchiseNode n, {String? label}) {
    return Padding(
      padding: EdgeInsets.only(top: 4 * _scale),
      child: HikkaAnimeRow(
        anime: n.anime,
        scale: _scale,
        label: label,
        highlighted: n.id == model.current.id,
      ),
    );
  }

  /// The page's run of rows as lazy pieces (a long franchise has a hundred titles: each row is built only when it
  /// comes near the screen): a grey caption, the rows under it, a gap
  List<WidgetBuilder> _byYears(FranchiseModel model, double pad) {
    final out = <WidgetBuilder>[];
    for (final (label, nodes) in model.groupByYear()) {
      final visible = nodes.where(_visible).toList();
      if (visible.isEmpty) continue;
      out.add((_) => _narrow(pad, _groupTitle(label)));
      for (final n in visible) {
        out.add((_) => _narrow(pad, _row(model, n, label: model.relationText(n))));
      }
      out.add((_) => SizedBox(height: 4 * _scale));
    }
    return out;
  }

  List<WidgetBuilder> _byGroups(FranchiseModel model, double pad) {
    final out = <WidgetBuilder>[];
    final chain = model.chain.where(_visible).toList();
    if (chain.isNotEmpty) {
      out.add((_) => _narrow(pad, _groupTitle(FranchiseGroup.sequel.label, trailing: chain.length > 1 ? '${chain.length}' : null)));
      for (final n in chain) {
        out.add((_) => _narrow(pad, _row(model, n, label: model.chain.length > 1 ? 'Частина ${(n.chainIndex ?? 0) + 1}' : null)));
      }
      out.add((_) => SizedBox(height: 4 * _scale));
    }
    for (final group in FranchiseGroup.values) {
      if (group == FranchiseGroup.sequel) continue;
      final nodes = model.nodes.where((n) => n.chainIndex == null && n.group == group && _visible(n)).toList();
      if (nodes.isEmpty) continue;
      out.add((_) => _narrow(pad, _groupTitle(group.label, trailing: '${nodes.length}')));
      for (final n in nodes) {
        out.add((_) => _narrow(pad, _row(model, n, label: n.relation?.label)));
      }
      out.add((_) => SizedBox(height: 4 * _scale));
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

    final pieces = _mode == 'years' ? _byYears(model, pad) : _byGroups(model, pad);
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      itemCount: pieces.length,
      itemBuilder: (context, i) => pieces[i](context),
      children: [
        HikkaLeadLine(scale: scale, pad: pad, parts: [summary]),
        // "За роками" / "За групами" as round plates, as the filters
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 4 * scale),
          child: Wrap(
            spacing: 8 * scale,
            children: [
              for (final (value, label) in const [('years', 'За роками'), ('groups', 'За групами')])
                AppPlate(
                  key: ValueKey('franchise-mode-$value'),
                  scale: scale,
                  label: label,
                  height: 34,
                  radius: 17,
                  selected: _mode == value,
                  onTap: () => _setMode(value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
