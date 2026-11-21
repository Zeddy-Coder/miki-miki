part of 'hikka_models.dart';

// ── Community: authors, collections, articles ─────────────────────────────

/// Tags come as strings or as `{"name": …, "content_count": …}`
List<String> _tags(Object? raw) => [
      for (final t in (raw is List ? raw : const []))
        if (t is String && t.trim().isNotEmpty)
          t.trim()
        else if (t is Map && t['name'] is String && (t['name'] as String).trim().isNotEmpty)
          (t['name'] as String).trim(),
    ];

/// Author of a collection or article
class HikkaAuthor {
  final String username;
  final String? avatar;

  const HikkaAuthor({required this.username, this.avatar});

  factory HikkaAuthor.fromJson(Map<String, dynamic> j) => HikkaAuthor(
        username: _str(j['username']) ?? '',
        avatar: _str(j['avatar']),
      );

  static const HikkaAuthor unknown = HikkaAuthor(username: '');
}

/// One collection entry: a title with an optional author comment and a section label
class HikkaCollectionEntry {
  final HikkaAnime anime;
  final String? comment;
  final String? label;
  final int order;

  const HikkaCollectionEntry({required this.anime, this.comment, this.label, this.order = 0});
}

/// An anime collection from a user. The list carries only the first few entries ([items]); the collection
/// page has all of them; [entries] is the total count.
class HikkaCollection {
  final String reference;
  final String title;
  final String? description;
  final HikkaAuthor author;
  final String contentType;
  final int entries;
  final int voteScore;
  final int commentsCount;
  final List<String> tags;
  final List<String> labelsOrder;
  final bool spoiler;
  final bool nsfw;
  final int created; // unix, seconds
  final int updated;
  final List<HikkaCollectionEntry> items;

  const HikkaCollection({
    required this.reference,
    required this.title,
    this.description,
    this.author = HikkaAuthor.unknown,
    this.contentType = 'anime',
    this.entries = 0,
    this.voteScore = 0,
    this.commentsCount = 0,
    this.tags = const [],
    this.labelsOrder = const [],
    this.spoiler = false,
    this.nsfw = false,
    this.created = 0,
    this.updated = 0,
    this.items = const [],
  });

  factory HikkaCollection.fromJson(Map<String, dynamic> j) {
    final type = _str(j['content_type']) ?? 'anime';
    final items = <HikkaCollectionEntry>[];
    final raw = j['collection'];
    if (raw is List && type == 'anime') {
      for (final e in raw) {
        if (e is! Map<String, dynamic>) continue;
        final content = _map(e['content']);
        final anime = HikkaAnime.fromJson(content);
        if (anime.slug.isEmpty) continue;
        items.add(HikkaCollectionEntry(anime: anime, comment: _str(e['comment']), label: _str(e['label']), order: _intOr0(e['order'])));
      }
      items.sort((a, b) => a.order.compareTo(b.order));
    }
    return HikkaCollection(
      reference: _str(j['reference']) ?? '',
      title: _str(j['title']) ?? 'Без назви',
      description: _str(j['description']),
      author: j['author'] is Map<String, dynamic> ? HikkaAuthor.fromJson(j['author'] as Map<String, dynamic>) : HikkaAuthor.unknown,
      contentType: type,
      entries: _int(j['entries']) ?? items.length,
      voteScore: _intOr0(j['vote_score']),
      commentsCount: _intOr0(j['comments_count']),
      tags: _tags(j['tags']),
      labelsOrder: [for (final t in (j['labels_order'] as List? ?? const [])) if (t is String && t.trim().isNotEmpty) t.trim()],
      spoiler: _bool(j['spoiler']),
      nsfw: _bool(j['nsfw']),
      created: _intOr0(j['created']),
      updated: _intOr0(j['updated']),
      items: items,
    );
  }

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(created * 1000);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updated * 1000);

  /// Entries without hentai if showing it is turned off
  List<HikkaCollectionEntry> visibleItems({required bool allowAdult}) =>
      allowAdult ? items : [for (final e in items) if (!e.anime.isAdult) e];

  /// Entries grouped by the author's section labels (section order follows `labels_order`); unlabeled entries come first
  List<(String? label, List<HikkaCollectionEntry> items)> grouped({required bool allowAdult}) {
    final list = visibleItems(allowAdult: allowAdult);
    if (labelsOrder.isEmpty || !list.any((e) => e.label != null)) return [(null, list)];
    final out = <(String?, List<HikkaCollectionEntry>)>[];
    final unlabeled = [for (final e in list) if (e.label == null) e];
    if (unlabeled.isNotEmpty) out.add((null, unlabeled));
    final seen = <String>{};
    for (final label in [...labelsOrder, for (final e in list) if (e.label != null) e.label!]) {
      if (!seen.add(label)) continue;
      final inLabel = [for (final e in list) if (e.label == label) e];
      if (inLabel.isNotEmpty) out.add((label, inLabel));
    }
    return out;
  }
}

/// Article document node (Slate editor): a block (`p`, `h3`, `image`…) or a text leaf with markup
class SlateNode {
  /// Block type; empty means a text leaf
  final String type;
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final String? url;
  final List<SlateNode> children;

  const SlateNode({
    this.type = '',
    this.text = '',
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.url,
    this.children = const [],
  });

  bool get isText => type.isEmpty;

  factory SlateNode.fromJson(Map<String, dynamic> j) {
    final type = _str(j['type']);
    final kids = j['children'];
    return SlateNode(
      type: type ?? '',
      // An empty leaf (`{"text": ""}`) is still a leaf
      text: j['text'] is String ? j['text'] as String : '',
      bold: _bool(j['bold']),
      italic: _bool(j['italic']),
      underline: _bool(j['underline']),
      strike: _bool(j['strikethrough']) || _bool(j['strike']),
      code: _bool(j['code']),
      url: _str(j['url']),
      children: kids is List ? [for (final k in kids) if (k is Map<String, dynamic>) SlateNode.fromJson(k)] : const [],
    );
  }

  static List<SlateNode> parseList(Object? json) =>
      json is List ? [for (final e in json) if (e is Map<String, dynamic>) SlateNode.fromJson(e)] : const [];

  /// All text of the node without markup
  String get plainText {
    if (isText) return text;
    return children.map((c) => c.plainText).join();
  }

  /// First image in the subtree (for the article cover in the list)
  String? get firstImage {
    if (type == 'image' && url != null) return url;
    for (final c in children) {
      final f = c.firstImage;
      if (f != null) return f;
    }
    return null;
  }
}

/// A community article. The list carries only the beginning ([preview]); the article page has the full text ([document]).
class HikkaArticle {
  final String slug;
  final String title;
  final HikkaAuthor author;
  final String category;
  final int created; // unix, seconds
  final int updated;
  final int views;
  final int voteScore;
  final int commentsCount;
  final List<String> tags;
  final List<SlateNode> preview;
  final List<SlateNode> document;

  /// The title the article is about (the site shows it as a card under the heading); `null` when there is none
  final HikkaAnime? content;

  const HikkaArticle({
    required this.slug,
    required this.title,
    this.author = HikkaAuthor.unknown,
    this.category = 'original',
    this.created = 0,
    this.updated = 0,
    this.views = 0,
    this.voteScore = 0,
    this.commentsCount = 0,
    this.tags = const [],
    this.preview = const [],
    this.document = const [],
    this.content,
  });

  static const Map<String, String> categories = {
    'news': 'Новини',
    'reviews': 'Огляди',
    'original': 'Авторські',
    'system': 'Системні',
  };

  factory HikkaArticle.fromJson(Map<String, dynamic> j) => HikkaArticle(
        slug: _str(j['slug']) ?? '',
        title: _str(j['title']) ?? 'Без назви',
        author: j['author'] is Map<String, dynamic> ? HikkaAuthor.fromJson(j['author'] as Map<String, dynamic>) : HikkaAuthor.unknown,
        category: _str(j['category']) ?? 'original',
        created: _intOr0(j['created']),
        updated: _intOr0(j['updated']),
        views: _intOr0(j['views']),
        voteScore: _intOr0(j['vote_score']),
        commentsCount: _intOr0(j['comments_count']),
        tags: _tags(j['tags']),
        preview: SlateNode.parseList(j['preview']),
        document: SlateNode.parseList(j['document']),
        content: j['content'] is Map<String, dynamic> && (j['content'] as Map)['data_type'] == 'anime' && ((j['content'] as Map)['slug'] ?? '') != ''
            ? HikkaAnime.fromJson(j['content'] as Map<String, dynamic>)
            : null,
      );

  String get categoryLabel => categories[category] ?? category;
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(created * 1000);

  /// Beginning of the text for a list card: the first paragraphs without markup, no longer than [maxChars]
  String snippet({int maxChars = 220}) {
    final b = StringBuffer();
    for (final n in preview.isNotEmpty ? preview : document) {
      if (n.type == 'image' || n.type == 'image_group' || n.type == 'video') continue;
      final t = n.plainText.trim();
      if (t.isEmpty) continue;
      if (b.isNotEmpty) b.write(' ');
      b.write(t);
      if (b.length >= maxChars) break;
    }
    final s = b.toString();
    return s.length <= maxChars ? s : '${s.substring(0, maxChars).trimRight()}…';
  }

  /// First image of the article (card cover)
  String? get coverImage {
    for (final n in preview.isNotEmpty ? preview : document) {
      final f = n.firstImage;
      if (f != null) return f;
    }
    return null;
  }
}
