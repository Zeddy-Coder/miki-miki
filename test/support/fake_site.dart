import 'dart:convert';
import 'dart:io';

import 'package:miki_miki/services/sources/source_http.dart';

/// A fake site for source tests: responses by a substring in `"METHOD address"`, the first match wins.
/// The value is a string (200 OK), a `Resp` (status / body / headers) or a function of the request.
class Resp {
  final int status;
  final String body;
  final Map<String, String> headers;
  final List<String> cookies;

  const Resp(this.body, {this.status = 200, this.headers = const {}, this.cookies = const []});
}

class FakeSite {
  final Map<String, Object> routes;
  final List<SourceRequest> log = [];

  FakeSite(this.routes);

  SourceSender get sender => (SourceRequest r) async {
        log.add(r);
        final line = '${r.method} ${r.url}';
        for (final e in routes.entries) {
          if (!line.contains(e.key)) continue;
          final v = e.value;
          final Resp resp = switch (v) {
            String s => Resp(s),
            Resp x => x,
            Resp Function(SourceRequest) f => f(r),
            _ => throw StateError('Невідомий тип відповіді для ${e.key}'),
          };
          return SourceResponse(resp.status, r.url, utf8.encode(resp.body), headers: resp.headers, setCookies: resp.cookies);
        }
        return SourceResponse(404, r.url, utf8.encode('not found: $line'));
      };

  SourceHttp get http => SourceHttp(sender: sender);

  int count(String part) => log.where((r) => '${r.method} ${r.url}'.contains(part)).length;
}

String fixture(String name) => File('test/data/sources/$name').readAsStringSync();
