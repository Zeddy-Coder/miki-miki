/// Signing in to a Hikka account through an "external app" (client): the person allows access on hikka.io, the site
/// redirects them to the client's address with a request code, and the app exchanges that code for a token.
///
/// The code is caught by a temporary server on `127.0.0.1` (see [HikkaLoopback]): it runs only while sign-in is in progress and
/// listens only on this computer or phone. If the port is busy or the app was killed in the background, the fallback is to
/// paste the address the site redirected to (or the code itself) right in the sign-in dialog ([HikkaAuth.submit]).
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

/// Sign-in state
enum HikkaAuthPhase { signedOut, waiting, exchanging, signedIn }

class HikkaAuth extends ChangeNotifier {
  /// Shared instance (replaced in tests)
  static HikkaAuth instance = HikkaAuth();

  static const String section = 'hikka_auth';
  static const String webBase = 'https://hikka.io';

  /// Permissions we ask for: profile, watch lists, favorites
  static const List<String> scopes = ['user-details', 'watchlist', 'favourite'];

  /// The address to enter in the app settings on hikka.io ("Redirect link")
  static const int loopbackPort = 47615;
  static const String loopbackPath = '/auth/confirm';
  static const String redirectUri = 'http://127.0.0.1:$loopbackPort$loopbackPath';

  final HikkaApi? _apiOverride;
  final SectionLoader _load;
  final SectionSaver _save;
  final Future<bool> Function(String url) _openUrl;
  final Future<HikkaLoopback?> Function() _startLoopback;
  final Duration loginTimeout;
  final Duration exchangeTimeout;

  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());
  HikkaAuthPhase _phase = HikkaAuthPhase.signedOut;
  String? _error;
  bool _loopbackReady = false;
  Completer<String?>? _awaiting;
  HikkaLoopback? _loopback;
  bool _cancelled = false;
  int _attempt = 0;
  int _exchangeSeq = 0;

  HikkaAuth({
    HikkaApi? api,
    SectionLoader? load,
    SectionSaver? save,
    Future<bool> Function(String url)? urlOpener,
    Future<HikkaLoopback?> Function()? loopbackFactory,
    this.loginTimeout = const Duration(minutes: 5),
    this.exchangeTimeout = const Duration(seconds: 75),
  })  : _apiOverride = api,
        _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) {
          StorageService.saveSection(section, d);
          StorageService.flush();
        }),
        _openUrl = urlOpener ?? SystemControls.openUrl,
        _startLoopback = loopbackFactory ?? HikkaLoopback.start {
    _phase = token.isEmpty ? HikkaAuthPhase.signedOut : HikkaAuthPhase.signedIn;
    // The shared API takes the token from here; a separate (test) instance gets its token directly
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

  // ── State ───────────────────────────────────────────────────────

  HikkaAuthPhase get phase => _phase;
  String get token => (_data['token'] as String?) ?? '';
  bool get signedIn => token.isNotEmpty && _phase == HikkaAuthPhase.signedIn;

  /// Sign-in is in progress (waiting for consent on the site or exchanging the code for a token)
  bool get busy => _phase == HikkaAuthPhase.waiting || _phase == HikkaAuthPhase.exchanging;

  /// Last sign-in error to show the person (reset by a new attempt)
  String? get error => _error;

  /// The local address for the site's reply is up (if not, pasting the code manually remains)
  bool get loopbackReady => _loopbackReady;

  HikkaMe? get me {
    final j = _data['me'];
    return j is Map ? HikkaMe.fromJson(j.cast<String, dynamic>()) : null;
  }

  String get username => me?.username ?? '';

  /// Send watch progress to Hikka lists (on by default)
  bool get syncProgress => (_data['sync'] as bool?) ?? true;

  set syncProgress(bool value) {
    if (value == syncProgress) return;
    _data['sync'] = value;
    _commit();
  }

  // ── Hikka client ───────────────────────────────────────────────

  /// The person's own client, if entered in settings (takes priority over the built-in one)
  String get customReference => (_data['client_ref'] as String?) ?? '';
  String get customSecret => (_data['client_secret'] as String?) ?? '';

  String get clientReference => customReference.isNotEmpty ? customReference : HikkaClientKey.reference;

  /// Secret of the own client only; the built-in client has no secret in the app (the backend adds it)
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

  /// Consent page on hikka.io
  String get authorizeUrl => '$webBase/oauth?reference=${Uri.encodeQueryComponent(clientReference)}&scope=${scopes.join(',')}';

  // ── Sign-in ───────────────────────────────────────────────────────

  /// Opens the consent page in a browser and waits for the code (up to [loginTimeout]); then exchanges it for a token
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

  /// Cancel sign-in (the window was closed)
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

  /// Fallback: the person pasted the address the site redirected to (or the code itself). `false`: no code found.
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
      // The app was restarted while the person was on the site, so we finish the sign-in immediately
      unawaited(_finish(ref));
    }
    return true;
  }

  Future<void> _finish(String ref) async {
    _setPhase(HikkaAuthPhase.exchanging);
    try {
      // The code exchange must not hang forever: if the network or the sign-in service is silent, the person sees an error and can retry
      await _exchange(ref).timeout(
        exchangeTimeout,
        onTimeout: () => throw const HikkaException(HikkaErrorKind.timeout, 'Служба входу не відповіла вчасно. Перевірте мережу й спробуйте ще раз.'),
      );
    } on HikkaException catch (e) {
      AppLog.w('hikka', 'вхід: не вдалося завершити: $e');
      _dropSession();
      _fail(_loginMessage(e));
    }
  }

  Future<void> _exchange(String ref) async {
    final seq = ++_exchangeSeq;
    final t = customSecret.isNotEmpty ? await _api.exchangeToken(ref, customSecret) : await _viaBackend(ref);
    if (seq != _exchangeSeq || _phase != HikkaAuthPhase.exchanging) return; // the exchange has already been abandoned (timeout)
    _data['token'] = t.secret;
    _data['expires'] = t.expiration;
    final HikkaMe me;
    try {
      me = await _api.me();
    } on HikkaException catch (e) {
      throw HikkaException(e.kind, 'Профіль Hikka: ${e.detail}', status: e.status, code: e.code);
    }
    _data['me'] = me.toJson();
    _error = null;
    _commit();
    _phase = HikkaAuthPhase.signedIn;
    notifyListeners();
  }

  /// Built-in client: the backend exchanges the code, the client secret never reaches the app
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
      throw HikkaException(HikkaErrorKind.network, 'Служба входу (бекенд): ${e.message}');
    }
  }

  static String _loginMessage(HikkaException e) {
    if (e.code == 'auth:invalid_token_request') {
      return 'Hikka не прийняла цей запит на вхід: він застарів або вже використаний. Почніть вхід заново.';
    }
    if (e.kind == HikkaErrorKind.badResponse || e.kind == HikkaErrorKind.forbidden) {
      return 'Hikka відхилила вхід (${e.code ?? e.status ?? 'помилка'}). Перевірте клієнта в налаштуваннях.';
    }
    if (e.kind == HikkaErrorKind.network && e.detail.isNotEmpty) {
      // "No internet" alone explains nothing without the reason: we show exactly where we failed to connect
      final d = e.detail.length > 140 ? '${e.detail.substring(0, 140)}…' : e.detail;
      return '${e.message}\n$d';
    }
    return e.message;
  }

  void _fail(String? message) {
    _error = message;
    _setPhase(token.isEmpty ? HikkaAuthPhase.signedOut : HikkaAuthPhase.signedIn);
  }

  /// Refreshes the profile from the server (avatar, name)
  Future<void> refresh() async {
    if (!signedIn) return;
    try {
      _data['me'] = (await _api.me()).toJson();
      _commit();
    } on HikkaException catch (e) {
      AppLog.w('hikka', 'профіль не оновився: $e');
    }
  }

  /// Sign-out: the token is revoked on the server (if possible), but locally the person always signs out
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

  // ── Code parsing ────────────────────────────────────────────────

  static final RegExp _uuid = RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');
  static final RegExp _queryRef = RegExp(r'(?:^|[?&])(?:request_)?reference=([^&#\s]+)');

  /// Extracts the request code from a redirect address (`…/auth/confirm?reference=…`), a bare code, or text
  /// that contains it. `null`: nothing similar.
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

/// A temporary HTTP server on `127.0.0.1` only: accepts one redirect from hikka.io and returns the sign-in code.
class HikkaLoopback {
  final HttpServer _server;
  final String path;
  final Completer<String?> _done = Completer<String?>();

  HikkaLoopback._(this._server, this.path) {
    _server.listen(_handle, onError: (_) {});
  }

  /// Starts the server. `null`: the port is busy or the socket is unavailable.
  static Future<HikkaLoopback?> start({int port = HikkaAuth.loopbackPort, String path = HikkaAuth.loopbackPath}) async {
    try {
      return HikkaLoopback._(await HttpServer.bind(InternetAddress.loopbackIPv4, port), path);
    } on SocketException catch (e) {
      AppLog.w('hikka', 'порт $port недоступний для входу: ${e.message}');
      return null;
    }
  }

  int get port => _server.port;

  /// The request code as soon as the browser brings it; `null`: the server was closed earlier
  Future<String?> get reference => _done.future;

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      // Only requests to our address and only from "127.0.0.1"/"localhost" (protection against DNS spoofing)
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

  /// Button and automatic return to the app (on a phone the system opens it via the miki:// scheme)
  static const String _backToApp =
      '<p style="margin-top:18px"><a href="miki://open" style="display:inline-block;padding:11px 20px;border-radius:10px;'
      'background:#e8636a;color:#fff;text-decoration:none;font-weight:bold">Повернутись у застосунок</a></p>'
      '<script>if(/Android/i.test(navigator.userAgent)){setTimeout(function(){location.href="miki://open"},700)}</script>';

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
        '<body><div class="c"><h1>$title</h1><p>$text</p>${ok ? _backToApp : ''}</div></body></html>';
  }

  Future<void> close() async {
    if (!_done.isCompleted) _done.complete(null);
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}
