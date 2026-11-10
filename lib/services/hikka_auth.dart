/// Вхід в акаунт Hikka через «зовнішній застосунок» (клієнт): людина дозволяє доступ на hikka.io, сайт
/// перекидає її на адресу клієнта з кодом запиту, а застосунок міняє цей код на токен.
///
/// Код ловить тимчасовий сервер на `127.0.0.1` (див. [HikkaLoopback]): він працює лише поки йде вхід і
/// слухає тільки цей комп'ютер чи телефон. Якщо порт зайнятий чи застосунок убило в фоні — запасний шлях:
/// вставити адресу, на яку перекинув сайт (або сам код), прямо у вікні входу ([HikkaAuth.submit]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../constants/app_identity.dart';
import '../models/hikka_user_models.dart';
import 'app_log.dart';
import 'backend_client.dart';
import 'hikka_api.dart';
import 'hikka_client_key.dart';
import 'storage_service.dart';
import 'system_controls.dart';

/// Стан входу
enum HikkaAuthPhase { signedOut, waiting, exchanging, signedIn }

class HikkaAuth extends ChangeNotifier {
  /// Спільний екземпляр (у тестах підміняється)
  static HikkaAuth instance = HikkaAuth();

  static const String section = 'hikka_auth';
  static const String webBase = 'https://hikka.io';

  /// Які права просимо: профіль, списки перегляду, улюблене
  static const List<String> scopes = ['user-details', 'watchlist', 'favourite'];

  /// Адреса, яку треба вказати в налаштуваннях застосунку на hikka.io («Посилання переспрямування»)
  static const int loopbackPort = 47615;
  static const String loopbackPath = '/auth/confirm';
  static const String redirectUri = 'http://127.0.0.1:$loopbackPort$loopbackPath';

  final HikkaApi? _apiOverride;
  final SectionLoader _load;
  final SectionSaver _save;
  final Future<bool> Function(String url) _openUrl;
  final Future<HikkaLoopback?> Function() _startLoopback;
  final Duration loginTimeout;

  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());
  HikkaAuthPhase _phase = HikkaAuthPhase.signedOut;
  String? _error;
  bool _loopbackReady = false;
  Completer<String?>? _awaiting;
  HikkaLoopback? _loopback;
  bool _cancelled = false;
  int _attempt = 0;

  HikkaAuth({
    HikkaApi? api,
    SectionLoader? load,
    SectionSaver? save,
    Future<bool> Function(String url)? urlOpener,
    Future<HikkaLoopback?> Function()? loopbackFactory,
    this.loginTimeout = const Duration(minutes: 5),
  })  : _apiOverride = api,
        _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        _openUrl = urlOpener ?? SystemControls.openUrl,
        _startLoopback = loopbackFactory ?? HikkaLoopback.start {
    _phase = token.isEmpty ? HikkaAuthPhase.signedOut : HikkaAuthPhase.signedIn;
    // Спільний API бере токен звідси; окремому (тестовому) екземпляру токен задається прямо
    String? provide() => token.isEmpty ? null : token;
    final own = _apiOverride;
    if (own != null) {
      own
        ..tokenProvider = provide
        ..onUnauthorized = _onUnauthorized;
    } else {
      HikkaApi.sharedTokenProvider = provide;
      HikkaApi.sharedOnUnauthorized = _onUnauthorized;
    }
  }

  HikkaApi get _api => _apiOverride ?? HikkaApi.instance;

  // ── Стан ───────────────────────────────────────────────────────

  HikkaAuthPhase get phase => _phase;
  String get token => (_data['token'] as String?) ?? '';
  bool get signedIn => token.isNotEmpty && _phase == HikkaAuthPhase.signedIn;

  /// Йде вхід (чекаємо дозволу на сайті або міняємо код на токен)
  bool get busy => _phase == HikkaAuthPhase.waiting || _phase == HikkaAuthPhase.exchanging;

  /// Остання помилка входу для показу людині (скидається новою спробою)
  String? get error => _error;

  /// Локальна адреса для відповіді сайту піднялась (якщо ні — лишається вставити код вручну)
  bool get loopbackReady => _loopbackReady;

  HikkaMe? get me {
    final j = _data['me'];
    return j is Map ? HikkaMe.fromJson(j.cast<String, dynamic>()) : null;
  }

  String get username => me?.username ?? '';

  /// Передавати прогрес перегляду в списки Hikka (типово так)
  bool get syncProgress => (_data['sync'] as bool?) ?? true;

  set syncProgress(bool value) {
    if (value == syncProgress) return;
    _data['sync'] = value;
    _commit();
  }

  // ── Клієнт Hikka ───────────────────────────────────────────────

  /// Свій клієнт, якщо людина вписала його в налаштуваннях (має перевагу над вбудованим)
  String get customReference => (_data['client_ref'] as String?) ?? '';
  String get customSecret => (_data['client_secret'] as String?) ?? '';

  String get clientReference => customReference.isNotEmpty ? customReference : HikkaClientKey.reference;

  /// Секрет лише свого клієнта; вбудований клієнт секрету в застосунку не має (його додає бекенд)
  String get clientSecret => customSecret;
  bool get hasClient => clientReference.isNotEmpty && (customReference.isEmpty || customSecret.isNotEmpty);

  void setCustomClient(String reference, String secret) {
    final r = reference.trim(), s = secret.trim();
    if (r == customReference && s == customSecret) return;
    if (r.isEmpty && s.isEmpty) {
      _data.remove('client_ref');
      _data.remove('client_secret');
    } else {
      _data['client_ref'] = r;
      _data['client_secret'] = s;
    }
    _commit();
  }

  /// Сторінка дозволу на hikka.io
  String get authorizeUrl => '$webBase/oauth?reference=${Uri.encodeQueryComponent(clientReference)}&scope=${scopes.join(',')}';

  // ── Вхід ───────────────────────────────────────────────────────

  /// Відкриває сторінку дозволу в браузері й чекає код (до [loginTimeout]); далі міняє його на токен
  Future<void> startLogin() async {
    if (busy) return;
    if (!hasClient) {
      _fail('У цій збірці не задано клієнта Hikka для входу.');
      return;
    }
    _error = null;
    _cancelled = false;
    final attempt = ++_attempt;
    _setPhase(HikkaAuthPhase.waiting);

    final done = _awaiting = Completer<String?>();
    try {
      _loopback = await _startLoopback();
    } catch (e) {
      AppLog.w('hikka', 'вхід: локальна адреса не піднялась: $e');
      _loopback = null;
    }
    _loopbackReady = _loopback != null;
    notifyListeners();
    _loopback?.reference.then((r) {
      if (!done.isCompleted) done.complete(r);
    });
    final timer = Timer(loginTimeout, () {
      if (!done.isCompleted) done.complete(null);
    });

    final opened = await _openUrl(authorizeUrl);
    if (!opened) AppLog.w('hikka', 'вхід: браузер не відкрився, лишається посилання вручну');

    final ref = await done.future;
    timer.cancel();
    await _closeLoopback();
    if (attempt != _attempt) return;
    _awaiting = null;
    if (ref == null) {
      _fail(_cancelled ? null : 'Не дочекались відповіді від Hikka. Спробуйте ще раз.');
      return;
    }
    await _finish(ref);
  }

  /// Скасувати вхід (закрили вікно)
  void cancelLogin() {
    if (_phase != HikkaAuthPhase.waiting) return;
    _cancelled = true;
    final c = _awaiting;
    if (c != null && !c.isCompleted) {
      c.complete(null);
    } else {
      _fail(null);
    }
  }

  /// Запасний шлях: людина вставила адресу, на яку перекинув сайт (або сам код). `false` — коду не знайшли.
  bool submit(String pasted) {
    final ref = parseReference(pasted);
    if (ref == null) {
      _error = 'Не знайшов у цьому тексті код входу. Вставте адресу, на яку вас перекинуло, повністю.';
      notifyListeners();
      return false;
    }
    _error = null;
    final c = _awaiting;
    if (c != null && !c.isCompleted) {
      c.complete(ref);
    } else if (!busy) {
      // Застосунок перезапускали, поки людина була на сайті, — завершуємо вхід одразу
      unawaited(_finish(ref));
    }
    return true;
  }

  Future<void> _finish(String ref) async {
    _setPhase(HikkaAuthPhase.exchanging);
    try {
      final t = customSecret.isNotEmpty ? await _api.exchangeToken(ref, customSecret) : await _viaBackend(ref);
      _data['token'] = t.secret;
      _data['expires'] = t.expiration;
      final me = await _api.me();
      _data['me'] = me.toJson();
      _error = null;
      _commit();
      _phase = HikkaAuthPhase.signedIn;
      notifyListeners();
    } on HikkaException catch (e) {
      AppLog.w('hikka', 'вхід: не вдалося завершити: $e');
      _dropSession();
      _fail(_loginMessage(e));
    }
  }

  /// Вбудований клієнт: код міняє бекенд, секрет клієнта до застосунку не потрапляє
  Future<HikkaToken> _viaBackend(String ref) async {
    try {
      final (status, j) = await BackendClient.instance.hikkaToken(ref);
      if (status == 200) {
        final t = HikkaToken.fromJson(j);
        if (t.secret.isNotEmpty) return t;
        throw const HikkaException(HikkaErrorKind.badResponse, 'порожній токен');
      }
      final detail = j['code'] ?? j['detail'];
      throw HikkaException(HikkaErrorKind.badResponse, 'Hikka відхилила вхід', status: status, code: detail is String ? detail : null);
    } on BackendException catch (e) {
      throw HikkaException(HikkaErrorKind.network, 'Не вдалося зв’язатися зі службою входу. Спробуйте пізніше. (${e.message})');
    }
  }

  static String _loginMessage(HikkaException e) {
    if (e.code == 'auth:invalid_token_request') {
      return 'Hikka не прийняла цей запит на вхід: він застарів або вже використаний. Почніть вхід заново.';
    }
    if (e.kind == HikkaErrorKind.badResponse || e.kind == HikkaErrorKind.forbidden) {
      return 'Hikka відхилила вхід (${e.code ?? e.status ?? 'помилка'}). Перевірте клієнта в налаштуваннях.';
    }
    return e.message;
  }

  void _fail(String? message) {
    _error = message;
    _setPhase(token.isEmpty ? HikkaAuthPhase.signedOut : HikkaAuthPhase.signedIn);
  }

  /// Оновлює профіль із сервера (аватар, ім'я)
  Future<void> refresh() async {
    if (!signedIn) return;
    try {
      _data['me'] = (await _api.me()).toJson();
      _commit();
    } on HikkaException catch (e) {
      AppLog.w('hikka', 'профіль не оновився: $e');
    }
  }

  /// Вихід: токен відкликається на сервері (якщо вдасться), але локально людина виходить завжди
  Future<void> signOut() async {
    if (token.isNotEmpty) {
      try {
        final ref = await _api.tokenReference().timeout(const Duration(seconds: 8));
        if (ref != null) await _api.revokeToken(ref).timeout(const Duration(seconds: 8));
      } catch (e) {
        AppLog.w('hikka', 'токен не відкликано на сервері: ${e is HikkaException ? e : HikkaApi.describeError(e)}');
      }
    }
    _dropSession();
    _error = null;
    _setPhase(HikkaAuthPhase.signedOut);
  }

  void _onUnauthorized() {
    if (token.isEmpty) return;
    _dropSession();
    _error = 'Сесія Hikka завершилась. Увійдіть знову.';
    _setPhase(HikkaAuthPhase.signedOut);
  }

  void _dropSession() {
    _data
      ..remove('token')
      ..remove('expires')
      ..remove('me');
    _commit(notify: false);
  }

  Future<void> _closeLoopback() async {
    final l = _loopback;
    _loopback = null;
    _loopbackReady = false;
    await l?.close();
  }

  void _setPhase(HikkaAuthPhase p) {
    _phase = p;
    notifyListeners();
  }

  void _commit({bool notify = true}) {
    _save(_data);
    if (notify) notifyListeners();
  }

  // ── Розбір коду ────────────────────────────────────────────────

  static final RegExp _uuid = RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
  static final RegExp _queryRef = RegExp(r'(?:^|[?&])(?:request_)?reference=([^&#\s]+)');

  /// Дістає код запиту з адреси переспрямування (`…/auth/confirm?reference=…`), з голого коду чи з тексту,
  /// де він є. `null` — нічого схожого.
  static String? parseReference(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    try {
      final q = Uri.parse(s).queryParameters;
      final v = (q['reference'] ?? q['request_reference'])?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    final m = _queryRef.firstMatch(s);
    if (m != null) return Uri.decodeQueryComponent(m.group(1)!);
    final u = _uuid.firstMatch(s);
    if (u != null) return u.group(0);
    if (RegExp(r'^[A-Za-z0-9_\-]{16,}$').hasMatch(s)) return s;
    return null;
  }
}

/// Тимчасовий HTTP-сервер лише на `127.0.0.1`: приймає одне переспрямування від hikka.io й віддає код входу.
class HikkaLoopback {
  final HttpServer _server;
  final String path;
  final Completer<String?> _done = Completer<String?>();

  HikkaLoopback._(this._server, this.path) {
    _server.listen(_handle, onError: (_) {});
  }

  /// Піднімає сервер. `null` — порт зайнятий чи сокет недоступний.
  static Future<HikkaLoopback?> start({int port = HikkaAuth.loopbackPort, String path = HikkaAuth.loopbackPath}) async {
    try {
      return HikkaLoopback._(await HttpServer.bind(InternetAddress.loopbackIPv4, port), path);
    } on SocketException catch (e) {
      AppLog.w('hikka', 'порт $port недоступний для входу: ${e.message}');
      return null;
    }
  }

  int get port => _server.port;

  /// Код запиту, щойно його принесе браузер; `null` — сервер закрили раніше
  Future<String?> get reference => _done.future;

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      // Лише запити до нашої адреси й лише від «127.0.0.1»/«localhost» (захист від підміни DNS)
      final host = req.headers.host ?? '';
      if (req.method != 'GET' || req.uri.path != path || !(host == '127.0.0.1' || host == 'localhost')) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final ref = HikkaAuth.parseReference(req.uri.toString());
      res.statusCode = ref == null ? HttpStatus.badRequest : HttpStatus.ok;
      res.headers
        ..contentType = ContentType('text', 'html', charset: 'utf-8')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      res.write(_page(ok: ref != null));
      await res.close();
      if (ref != null && !_done.isCompleted) _done.complete(ref);
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  static String _page({required bool ok}) {
    final title = ok ? 'Готово ✓' : 'Не вдалося завершити вхід';
    final text = ok
        ? 'Поверніться до ${AppIdentity.name}: вхід в акаунт Hikka завершується. Цю вкладку можна закрити.'
        : 'Сайт не передав код входу. Поверніться до ${AppIdentity.name} і почніть вхід заново.';
    return '<!doctype html><html lang="uk"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1"><title>${AppIdentity.name}</title>'
        '<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0f0f14;'
        'color:#f2f2f5;font-family:Arial,sans-serif;text-align:center}.c{max-width:340px;padding:24px}'
        'h1{font-size:21px;margin:0 0 10px}p{margin:0;color:#a9a9b6;line-height:1.5;font-size:14px}</style></head>'
        '<body><div class="c"><h1>$title</h1><p>$text</p></div></body></html>';
  }

  Future<void> close() async {
    if (!_done.isCompleted) _done.complete(null);
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}
