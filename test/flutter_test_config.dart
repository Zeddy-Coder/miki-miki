import 'dart:async';

import 'package:miki_miki/services/json_worker.dart';

/// Runs around every test file: big JSON is decoded in place, because a background isolate needs real time while
/// widget tests pump fake time (the background path is covered by `json_worker_test.dart` and the speed tests)
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  JsonWorker.threshold = 1 << 30;
  await testMain();
}
