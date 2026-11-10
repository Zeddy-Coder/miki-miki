import 'dart:convert';
import 'dart:io';

import 'package:miki_miki/services/sources/source_http.dart';

/// Транспорт для живих перевірок у пісочниці: `dart:io` тут не проходить крізь проксі, а `curl` — проходить.
/// Поводиться як `IoSourceTransport`: один стрибок, без перенаправлень, тіло обмежується `maxBodyBytes`.
SourceSender curlSender() => (SourceRequest r) async {
      final dir = Directory.systemTemp.createTempSync('curl_sender');
      try {
        final bodyFile = File('${dir.path}/body');
        final reqBody = File('${dir.path}/req');
        final args = <String>['-sS', '-m', '40', '-D', '-', '-o', bodyFile.path, '-X', r.method];
        r.headers.forEach((k, v) => args.addAll(['-H', '$k: $v']));
        if (r.body != null) {
          reqBody.writeAsBytesSync(r.body!);
          args.addAll(['--data-binary', '@${reqBody.path}']);
        }
        if (r.maxBodyBytes != null) args.addAll(['--max-filesize', '${r.maxBodyBytes! * 8}']);
        args.add(r.url.toString());
        final p = await Process.run('curl', args, stdoutEncoding: latin1);
        final out = p.stdout as String;
        if (p.exitCode != 0 && out.isEmpty) {
          throw SourceException(SourceErrorKind.network, 'curl ${p.exitCode}: ${p.stderr}');
        }
        // у виводі може бути кілька блоків заголовків (Connection Established від проксі) — беремо останній
        final blocks = out.split(RegExp(r'\r?\n\r?\n')).where((b) => b.trim().isNotEmpty).toList();
        final head = blocks.lastWhere((b) => b.startsWith('HTTP/'), orElse: () => blocks.isEmpty ? '' : blocks.last);
        final lines = head.split(RegExp(r'\r?\n'));
        final status = int.tryParse(RegExp(r'HTTP/\S+\s+(\d+)').firstMatch(lines.first)?.group(1) ?? '') ?? 0;
        final headers = <String, String>{};
        final cookies = <String>[];
        for (final l in lines.skip(1)) {
          final i = l.indexOf(':');
          if (i <= 0) continue;
          final k = l.substring(0, i).trim().toLowerCase();
          final v = utf8.decode(latin1.encode(l.substring(i + 1).trim()), allowMalformed: true);
          if (k == 'set-cookie') {
            cookies.add(v);
          } else {
            headers[k] = headers.containsKey(k) ? '${headers[k]},$v' : v;
          }
        }
        var bytes = bodyFile.existsSync() ? bodyFile.readAsBytesSync() : <int>[];
        if (r.maxBodyBytes != null && bytes.length > r.maxBodyBytes!) bytes = bytes.sublist(0, r.maxBodyBytes!);
        return SourceResponse(status, r.url, bytes, headers: headers, setCookies: cookies);
      } finally {
        dir.deleteSync(recursive: true);
      }
    };
