import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'constants/app_identity.dart';
import 'screens/player_screen.dart';
import 'services/app_diagnostics.dart';
import 'services/app_log.dart';
import 'services/backend_client.dart';
import 'services/app_updater.dart';
import 'services/deep_links.dart';
import 'services/downloads/download_manager.dart';
import 'services/skips/skip_service.dart';
import 'services/episode_alerts.dart';
import 'services/hikka_api.dart';
import 'services/hikka_disk_cache.dart';
import 'services/hikka_lists.dart';
import 'services/media_controls.dart';
import 'services/network_status.dart';
import 'services/push_notifications.dart';
import 'services/settings_sync.dart';
import 'services/storage_service.dart';
import 'services/system_controls.dart';
import 'services/thumbnail_service.dart';
import 'services/ui_theme_service.dart';
import 'utils/platform_info.dart';
import 'widgets/app_ui_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Independent initializations run in parallel (window ↔ reading saved settings)
  await Future.wait([
    if (AppPlatform.isDesktop) windowManager.ensureInitialized(),
    StorageService.init(),
  ]);
  // The log is started right after settings so startup errors are recorded too
  await AppLog.instance.init(
    directory: Directory('${StorageService.appBasePath}/logs'),
    detailed: StorageService.getDetailedLog(),
  );
  AppDiagnostics.instance.install();
  AppLog.i('застосунок', 'запуск ${AppDiagnostics.build}');
  await ThumbnailService.init(); // Video preview cache
  uiTheme.init(); // Global theme initialization
  HikkaApi.instance.disk = HikkaDiskCache(); // Hikka responses on disk: start from the stored copy, refresh in the background
  NetworkStatus.instance.start(); // Online or not, mobile data or not (Android tells by itself; a PC looks after a failed request)
  unawaited(DownloadManager.instance.init()); // Downloaded episodes; unfinished ones go on when the network allows
  // A finished download gets its skips while online (AniSkip; listening, compared with the dub's other downloads)
  DownloadManager.instance.onDone = (item) {
    final dm = DownloadManager.instance;
    unawaited(SkipService.instance.onDownloaded(item, dub: dm.done.where((o) => o.animeKey == item.animeKey && o.groupId == item.groupId), videoOf: dm.localVideo));
  };
  // "Watched" marks made without internet go to Hikka once it is back (and soon after the start)
  NetworkStatus.instance.addListener(() {
    if (NetworkStatus.instance.online) unawaited(HikkaMyList.instance.flushPending());
  });
  unawaited(Future<void>.delayed(const Duration(seconds: 8), () => HikkaMyList.instance.flushPending()));
  unawaited(HikkaMyList.instance.loadIndex(delay: const Duration(seconds: 4))); // Statuses from Hikka lists for poster badges (if signed in)
  unawaited(Future<void>.delayed(const Duration(seconds: 6), () => EpisodeAlerts.instance.check().then((_) {}, onError: (Object _) {}))); // New episodes in the chosen dub (Mikai feed)
  unawaited(Future<void>.delayed(const Duration(seconds: 3), () => AppUpdater.instance.check(auto: true))); // Silent check for new versions on GitHub (at most once per 30 min; also on returning to the app)
  unawaited(EpisodeAlerts.instance.importInbox()); // pushes received while the app was closed
  PushNotifications.instance.start(); // Android: push about new episodes (works once the person turns it on)
  SettingsSync.instance.start(); // Settings, themes and positions of the Hikka account on every device
  unawaited(BackendClient.instance.refreshMoonKey()); // Moon key from the backend (in the background, without waiting)

  MediaControls.init(); // Windows: headphone / keyboard media keys

  if (AppPlatform.isDesktop) {
    const WindowOptions windowOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.black,
      title: AppIdentity.name,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } else {
    // Phone: both orientations (set by the sensor and system auto-rotate); the rotate button in the player
    // can lock one. The home screen shows system bars; only the player hides them (see the controller).
    SystemControls.init();
    // The app was launched via a miki://open/… link: handle it once the UI is up
    unawaited(SystemControls.initialLink().then((l) {
      if (l != null) Future<void>.delayed(const Duration(milliseconds: 600), () => DeepLinks.handle(l));
    }));
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  runApp(ListenableBuilder(
    listenable: uiTheme,
    builder: (context, _) => MaterialApp(
    title: AppIdentity.name,
    debugShowCheckedModeBanner: false,
    navigatorObservers: [AppNavObserver()],
    // Phone: a large system font must not break panels with a fixed height
    builder: (context, child) {
      if (!AppPlatform.isMobile || child == null) return child ?? const SizedBox.shrink();
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25)),
        child: child,
      );
    },
    scrollBehavior: const AppScrollBehavior(),
    // Standard Material widgets (text selection, indicators, cursor) take their accent color from the app theme
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: ThemeData.dark().colorScheme.copyWith(
            primary: uiTheme.accentColor,
            onPrimary: uiTheme.onAccent,
            secondary: uiTheme.accentColor,
          ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: uiTheme.accentColor,
        selectionColor: uiTheme.accentColor.withValues(alpha: 0.35),
        selectionHandleColor: uiTheme.accentColor,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: uiTheme.accentColor),
      textTheme: const TextTheme().apply(
        fontFamily: 'Arial',
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    ),
    home: const PlayerScreen(),
  )));
}
