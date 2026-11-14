/// Anime franchise model: chronology, main line (the sequel chain) and direct relations.
/// The logic is ported from the open hikka.io frontend (franchise-model.ts), anime only:
/// manga and light novels in the response are dropped. No Flutter dependency; covered by tests.
library;

import '../models/hikka_models.dart';

/// Relation group (as on hikka.io)
enum FranchiseGroup {
  sequel('Основна історія'),
  side('Побічні історії'),
  alternative('Альтернативні версії'),
  summary('Рекапи'),
  spinOff('Спінофи'),
  source('Інші медіа');

  final String label;
  const FranchiseGroup(this.label);
}

const Map<String, String> _forwardLabels = {
  'sequel': 'Сиквел',
  'side_story': 'Побічна історія',
  'summary': 'Рекап',
  'spin_off': 'Спіноф',
  'alternative_version': 'Альтернативна версія',
  'alternative_setting': 'Альтернативний сетинг',
  'adaptation': 'Адаптація',
};

const Map<String, String> _reverseLabels = {
  'sequel': 'Приквел',
  'side_story': 'Основна історія',
  'summary': 'Повна історія',
  'spin_off': 'Оригінал',
  'alternative_version': 'Альтернативна версія',
  'alternative_setting': 'Альтернативний сетинг',
  'adaptation': 'Адаптація',
};

const String _sourceLabel = 'Першоджерело';

const Map<String, FranchiseGroup> _typeGroups = {
  'sequel': FranchiseGroup.sequel,
  'side_story': FranchiseGroup.side,
  'summary': FranchiseGroup.summary,
  'spin_off': FranchiseGroup.spinOff,
  'alternative_version': FranchiseGroup.alternative,
  'alternative_setting': FranchiseGroup.alternative,
  'adaptation': FranchiseGroup.source,
};

const List<String> _typePriority = [
  'sequel',
  'side_story',
  'summary',
  'alternative_version',
  'alternative_setting',
  'spin_off',
  'adaptation',
];

const List<String> _directOrder = [
  'Приквел',
  'Сиквел',
  _sourceLabel,
  'Адаптація',
  'Побічна історія',
  'Основна історія',
  'Спіноф',
  'Оригінал',
  'Альтернативна версія',
  'Альтернативний сетинг',
  'Рекап',
  'Повна історія',
];

const int _secondsPerYear = 31557600;
const int _unknownWhen = 1 << 52;

class FranchiseRelationInfo {
  /// What this title is relative to [targetId]: "Сиквел", "Побічна історія"…
  final String label;
  final String targetId;

  const FranchiseRelationInfo(this.label, this.targetId);
}

class FranchiseNode {
  final String id;
  final HikkaAnime anime;

  /// Release moment (unix, seconds); unknown is a very large number
  final int when;

  bool onMainLine = false;
  FranchiseGroup group = FranchiseGroup.alternative;

  /// Index in the main line (from 0) or null
  int? chainIndex;
  FranchiseRelationInfo? relation;

  FranchiseNode(this.id, this.anime, this.when);

  bool get hasKnownDate => when < _unknownWhen;
}

class FranchiseDirect {
  final FranchiseNode node;
  final String label;
  final FranchiseGroup group;

  const FranchiseDirect(this.node, this.label, this.group);
}

class FranchiseEdge {
  final String a;
  final String b;
  final String type;

  const FranchiseEdge(this.a, this.b, this.type);
}

class FranchiseModel {
  final FranchiseNode current;

  /// All franchise titles by release time
  final List<FranchiseNode> nodes;
  final Map<String, FranchiseNode> byId;

  /// The main line (sequel chain) in watch order
  final List<FranchiseNode> chain;

  /// Direct relations of the current title
  final List<FranchiseDirect> direct;

  /// Direct relations of each title
  final Map<String, List<FranchiseDirect>> relations;
  final List<FranchiseEdge> edges;

  const FranchiseModel({
    required this.current,
    required this.nodes,
    required this.byId,
    required this.chain,
    required this.direct,
    required this.relations,
    required this.edges,
  });

  /// "Основна історія, 2 з 3" or the relation name for titles outside the main line
  String relationText(FranchiseNode node) {
    if (node.chainIndex != null) {
      return chain.length > 1 ? 'Основна історія, ${node.chainIndex! + 1} з ${chain.length}' : 'Основна історія';
    }
    return node.relation?.label ?? 'Аніме';
  }

  /// Titles grouped by release year (ascending); without a date, a separate group at the end
  List<(String label, List<FranchiseNode> nodes)> groupByYear() {
    final groups = <String, List<FranchiseNode>>{};
    for (final n in nodes) {
      final label = n.hasKnownDate ? '${n.anime.year ?? DateTime.fromMillisecondsSinceEpoch(n.when * 1000).year}' : 'Дата невідома';
      (groups[label] ??= []).add(n);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }

  static FranchiseModel? build(HikkaFranchiseData data, String slug) => _build(data, slug);
}

// ── Building ─────────────────────────────────────────────────────────────────

int _whenOf(HikkaAnime a) => a.startDate ?? (a.year != null ? (a.year! - 1970) * _secondsPerYear : _unknownWhen);

/// Stable sort (the standard Dart `List.sort` does not guarantee that)
void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (int i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((x, y) {
    final c = compare(x.$2, y.$2);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  for (int i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

int _byWhen(FranchiseNode a, FranchiseNode b) => a.when.compareTo(b.when);

/// What [me] is relative to [other]. Direction in the data: `slug` is the "parent", `related_slug` is its sequel,
/// side story, recap or spin-off; so for `slug` we show the inverse label.
String _relationLabel(HikkaRelation relation, FranchiseNode me, FranchiseNode other) {
  final type = relation.type;
  if (type == 'adaptation') {
    final mine = me.anime.year ?? 1 << 30;
    final theirs = other.anime.year ?? 1 << 30;
    return mine < theirs ? _sourceLabel : _forwardLabels[type]!;
  }
  final isParent = relation.slug == me.anime.slug;
  return (isParent ? _reverseLabels[type] : _forwardLabels[type]) ?? (_forwardLabels[type] ?? 'Пов’язане');
}

Set<String> _sequelComponent(String start, List<FranchiseEdge> sequels) {
  final component = {start};
  var grew = true;
  while (grew) {
    grew = false;
    for (final e in sequels) {
      if (component.contains(e.a) != component.contains(e.b)) {
        component
          ..add(e.a)
          ..add(e.b);
        grew = true;
      }
    }
  }
  return component;
}

List<FranchiseNode> _orderChain(Set<String> component, List<FranchiseEdge> sequels, Map<String, FranchiseNode> byId) {
  final inner = sequels.where((e) => component.contains(e.a) && component.contains(e.b)).toList();
  final indegree = {for (final id in component) id: 0};
  for (final e in inner) {
    indegree[e.b] = (indegree[e.b] ?? 0) + 1;
  }
  final nodes = [for (final id in component) byId[id]!];
  final ready = nodes.where((n) => indegree[n.id] == 0).toList();
  final order = <FranchiseNode>[];
  while (ready.isNotEmpty) {
    _stableSort(ready, _byWhen);
    final node = ready.removeAt(0);
    order.add(node);
    for (final e in inner) {
      if (e.a != node.id) continue;
      final left = (indegree[e.b] ?? 0) - 1;
      indegree[e.b] = left;
      if (left == 0) ready.add(byId[e.b]!);
    }
  }
  final rest = nodes.where((n) => !order.contains(n)).toList();
  _stableSort(rest, _byWhen);
  return [...order, ...rest];
}

/// The main story is the current title's sequel chain. If it has no sequels (a movie, OVA),
/// the longest franchise chain is taken so that the "spine" is not a single side story.
Set<String> _mainStory(FranchiseNode current, List<FranchiseNode> nodes, List<FranchiseEdge> sequels) {
  final own = _sequelComponent(current.id, sequels);
  if (own.length > 1) return own;

  var best = own;
  var bestStart = _unknownWhen;
  final seen = <String>{};
  final sorted = List.of(nodes);
  _stableSort(sorted, _byWhen);
  for (final node in sorted) {
    if (seen.contains(node.id)) continue;
    final component = _sequelComponent(node.id, sequels);
    seen.addAll(component);
    if (component.length > best.length || (component.length == best.length && !identical(best, own) && node.when < bestStart)) {
      best = component;
      bestStart = node.when;
    }
  }
  return best;
}

FranchiseModel? _build(HikkaFranchiseData data, String slug) {
  final byId = <String, FranchiseNode>{};
  for (final a in data.anime) {
    if (a.slug.isEmpty) continue;
    byId[a.slug] = FranchiseNode(a.slug, a, _whenOf(a));
  }
  final current = byId[slug];
  if (current == null) return null;

  // Only relations between anime that are in the response
  final relations = [
    for (final r in data.relations)
      if (r.contentType == 'anime' && r.relatedContentType == 'anime' && byId.containsKey(r.slug) && byId.containsKey(r.relatedSlug)) r,
  ];
  final edges = [
    for (final r in relations)
      FranchiseEdge(r.slug, r.relatedSlug, r.type == 'alternative_setting' ? 'alternative_version' : r.type),
  ];
  final sequels = edges.where((e) => e.type == 'sequel').toList();

  final neighbours = <String, List<(HikkaRelation relation, FranchiseNode other)>>{
    for (final id in byId.keys) id: [],
  };
  for (int i = 0; i < relations.length; i++) {
    final e = edges[i];
    neighbours[e.a]!.add((relations[i], byId[e.b]!));
    neighbours[e.b]!.add((relations[i], byId[e.a]!));
  }

  final nodes = byId.values.toList();
  _stableSort(nodes, _byWhen);
  final chain = _orderChain(_mainStory(current, nodes, sequels), sequels, byId);
  for (int i = 0; i < chain.length; i++) {
    chain[i]
      ..onMainLine = true
      ..group = FranchiseGroup.sequel
      ..chainIndex = i;
  }

  // Distance from the main line (number of relations)
  final distance = {for (final n in chain) n.id: 0};
  final queue = [for (final n in chain) n.id];
  for (int head = 0; head < queue.length; head++) {
    final id = queue[head];
    for (final (_, other) in neighbours[id] ?? const <(HikkaRelation, FranchiseNode)>[]) {
      if (distance.containsKey(other.id)) continue;
      distance[other.id] = distance[id]! + 1;
      queue.add(other.id);
    }
  }

  const far = 1 << 40;
  final offChain = nodes.where((n) => n.chainIndex == null).toList();
  _stableSort(offChain, (a, b) => (distance[a.id] ?? far).compareTo(distance[b.id] ?? far));

  for (final node in offChain) {
    node.group = FranchiseGroup.alternative;
    final links = List.of(neighbours[node.id] ?? const <(HikkaRelation, FranchiseNode)>[]);
    if (links.isEmpty) continue;

    _stableSort(links, (x, y) {
      final d = (distance[x.$2.id] ?? far).compareTo(distance[y.$2.id] ?? far);
      if (d != 0) return d;
      final p = _typePriority.indexOf(x.$1.type).compareTo(_typePriority.indexOf(y.$1.type));
      return p != 0 ? p : x.$2.when.compareTo(y.$2.when);
    });
    final (relation, other) = links.first;
    node.relation = FranchiseRelationInfo(_relationLabel(relation, node, other), other.id);

    if (relation.type == 'sequel') {
      // A sequel of a side story belongs to the same group
      if (!other.onMainLine) node.group = other.group;
    } else if (relation.type != 'adaptation') {
      node.group = _typeGroups[relation.type] ?? FranchiseGroup.alternative;
    }
  }

  final directById = <String, List<FranchiseDirect>>{};
  for (final node in nodes) {
    final list = [
      for (final (relation, other) in neighbours[node.id]!)
        FranchiseDirect(other, _relationLabel(relation, other, node), _typeGroups[relation.type] ?? FranchiseGroup.alternative),
    ];
    int rank(FranchiseDirect d) {
      final i = _directOrder.indexOf(d.label) + 1;
      return i == 0 ? 99 : i;
    }

    _stableSort(list, (a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.node.when.compareTo(b.node.when);
    });
    final seen = <FranchiseNode>{};
    directById[node.id] = [for (final d in list) if (seen.add(d.node)) d];
  }

  return FranchiseModel(
    current: current,
    nodes: nodes,
    byId: byId,
    chain: chain,
    direct: directById[current.id] ?? const [],
    relations: directById,
    edges: edges,
  );
}
