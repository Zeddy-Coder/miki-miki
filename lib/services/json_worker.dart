/// Big JSON is decoded outside the UI thread. A page of Hikka collections is ~0.6 MB of text: decoding it (and, before,
/// encoding it again for the disk cache) took ~40 ms of a phone's UI thread, two or three dropped frames each time the
/// list loaded more.
library;

import 'dart:convert';
import 'dart:isolate';

abstract final class JsonWorker {
  /// From this many characters a text is decoded in a background isolate; smaller texts are faster in place
  static const int defaultThreshold = 48 * 1024;

  /// The current border. Widget tests pump fake time and set it high (`test/flutter_test_config.dart`): a background
  /// isolate needs real time
  static int threshold = defaultThreshold;

  /// [jsonDecode], in a background isolate for a big [text] (the result comes back without a copy). A broken text
  /// throws the same [FormatException] as [jsonDecode]
  static Future<Object?> decode(String text) {
    if (text.length < threshold) return Future<Object?>.value(jsonDecode(text));
    return Isolate.run(() => jsonDecode(text), debugName: 'json');
  }
}
