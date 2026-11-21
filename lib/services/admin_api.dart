import 'backend_client.dart';
import 'hikka_auth.dart';

/// What a notification from the admin panel is
enum AdminPushType {
  /// An announcement (with a title slug the tap opens that title)
  news('news', 'Новина'),

  /// "A new version is out": the tap opens the update window
  update('update', 'Оновлення'),

  /// Looks like a real "new episode" notification, to check the whole chain (needs a title)
  episode('episode', 'Нова серія (тест)');

  final String wire;
  final String label;
  const AdminPushType(this.wire, this.label);
}

/// A notification to send
class AdminPush {
  final AdminPushType type;
  final String title;
  final String body;

  /// The title's Hikka slug: with it only those who follow the title get the message; empty means everybody
  final String audienceSlug;

  /// The title the tap opens (news, episode); empty means none
  final String slug;

  /// A picture for the notification (https)
  final String image;

  const AdminPush({required this.type, required this.title, required this.body, this.audienceSlug = '', this.slug = '', this.image = ''});

  String get target => audienceSlug.isEmpty ? 'all' : 'slug:$audienceSlug';

  Map<String, Object?> toJson() => {
        'type': type.wire,
        'title': title.trim(),
        'body': body.trim(),
        'target': target,
        if (slug.trim().isNotEmpty && type != AdminPushType.update) 'slug': slug.trim(),
        if (image.trim().isNotEmpty) 'image': image.trim(),
      };
}

/// How a send went
class AdminSendResult {
  final int devices;
  final int sent;
  final int failed;
  const AdminSendResult({required this.devices, required this.sent, required this.failed});
}

/// One sent notification from the log on the server
class AdminLogEntry {
  final DateTime at;
  final String by;
  final String type;
  final String title;
  final String body;
  final String target;
  final int devices;
  final int sent;
  final int failed;

  const AdminLogEntry({
    required this.at,
    required this.by,
    required this.type,
    required this.title,
    required this.body,
    required this.target,
    required this.devices,
    required this.sent,
    required this.failed,
  });

  factory AdminLogEntry.fromJson(Map<String, dynamic> j) => AdminLogEntry(
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
        by: '${j['by'] ?? ''}',
        type: '${j['type'] ?? ''}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        target: '${j['target'] ?? 'all'}',
        devices: (j['devices'] as num?)?.toInt() ?? 0,
        sent: (j['sent'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
      );
}

/// A failed admin request, in words for the panel
class AdminException implements Exception {
  final String message;
  final int? status;
  const AdminException(this.message, {this.status});

  @override
  String toString() => message;
}

/// The admin panel's requests (Firebase function `admin`, see `tools/backend/admin.ts`). The server checks who asks by
/// the Hikka token and answers only the accounts in its own list; the app merely hides the entry from everybody else.
class AdminApi {
  static AdminApi instance = AdminApi();

  /// Hikka usernames (lower case) that see the panel; the server keeps the same list (ADMINS in admin.ts)
  static const Set<String> admins = {'zeddy'};

  /// Limits of a notification (as on the server)
  static const int maxTitle = 120;
  static const int maxBody = 300;

  static final RegExp slugPattern = RegExp(r'^[A-Za-z0-9._\-]{1,160}$');

  final BackendClient Function() _backend;
  final HikkaAuth Function() _auth;

  AdminApi({BackendClient Function()? backend, HikkaAuth Function()? auth})
      : _backend = backend ?? (() => BackendClient.instance),
        _auth = auth ?? (() => HikkaAuth.instance);

  static bool isAdminName(String username) => admins.contains(username.trim().toLowerCase());

  /// The entry is shown: signed in to Hikka as an admin
  bool get visible {
    final a = _auth();
    return a.signedIn && isAdminName(a.username);
  }

  /// A Hikka slug or a hikka.io/anime/… address → the slug; null when it is neither
  static String? slugOf(String input) {
    var s = input.trim();
    final m = RegExp(r'hikka\.io/anime/([^/?#\s]+)').firstMatch(s);
    if (m != null) s = Uri.decodeComponent(m.group(1)!);
    return slugPattern.hasMatch(s) ? s : null;
  }

  Future<Map<String, dynamic>> _call(String action, [Map<String, Object?> fields = const {}]) async {
    final token = _auth().token;
    if (token.isEmpty) throw const AdminException('Увійдіть у Hikka, щоб користуватися адмін-панеллю.');
    final (int, Map<String, dynamic>) reply;
    try {
      reply = await _backend().admin(token, action, fields);
    } on BackendException catch (e) {
      if (e.status == null) throw AdminException('Немає зʼєднання з сервером: ${e.message}.');
      throw AdminException(describe(e.status!, null), status: e.status);
    }
    final (status, answer) = reply;
    if (status != 200) throw AdminException(describe(status, answer['error'] as String?), status: status);
    return answer;
  }

  /// A server answer that is not 200, in words
  static String describe(int status, String? error) => switch ((status, error)) {
        (403, _) => 'Цей акаунт Hikka не має доступу до адмін-панелі.',
        (401, 'no_hikka_token' || 'bad_hikka_token') => 'Hikka не підтвердила вхід. Увійдіть в акаунт знову.',
        (401, _) => 'Сервер не визнав сесію застосунку. Спробуйте ще раз.',
        (404, _) => 'На сервері ще немає адмін-функції: розгорніть tools/backend/admin.ts (firebase deploy --only functions,hosting).',
        (429, _) => 'Забагато запитів. Зачекайте хвилину.',
        (400, 'title_and_body_required') => 'Потрібні заголовок і текст.',
        (400, 'too_long') => 'Заголовок довший за $maxTitle знаків чи текст довший за $maxBody.',
        (400, 'bad_slug') => 'Такого slug тайтла не буває: лише латиниця, цифри, крапка, дефіс і підкреслення.',
        (400, 'slug_required') => 'Для «Нової серії» потрібен тайтл: вкажіть його slug.',
        (400, 'bad_image') => 'Картинка має бути посиланням https://',
        (400, 'bad_target') => 'Неправильне «Кому».',
        _ => 'Сервер відповів $status${error == null ? '' : ' ($error)'}.',
      };

  /// Who the server sees, and how many devices get notifications at all
  Future<(String username, int devices)> whoami() async {
    final j = await _call('whoami');
    return ('${j['username'] ?? ''}', (j['devices'] as num?)?.toInt() ?? 0);
  }

  /// How many devices a send to [audienceSlug] (empty: everybody) reaches
  Future<int> count({String audienceSlug = ''}) async {
    final j = await _call('push.count', {'target': audienceSlug.isEmpty ? 'all' : 'slug:$audienceSlug'});
    return (j['devices'] as num?)?.toInt() ?? 0;
  }

  Future<AdminSendResult> send(AdminPush push) async {
    final j = await _call('push.send', push.toJson());
    return AdminSendResult(
      devices: (j['devices'] as num?)?.toInt() ?? 0,
      sent: (j['sent'] as num?)?.toInt() ?? 0,
      failed: (j['failed'] as num?)?.toInt() ?? 0,
    );
  }

  /// The last sent notifications, newest first
  Future<List<AdminLogEntry>> history() async {
    final j = await _call('push.history');
    final items = j['items'];
    if (items is! List) return const [];
    return [for (final x in items) if (x is Map) AdminLogEntry.fromJson(x.cast<String, dynamic>())];
  }
}
