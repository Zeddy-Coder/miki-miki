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
import 'services/hikka_api.dart';
import 'services/hikka_disk_cache.dart';
import 'services/hikka_lists.dart';
import 'services/storage_service.dart';
import 'services/system_controls.dart';
import 'services/thumbnail_service.dart';
import 'services/ui_theme_service.dart';
import 'utils/platform_info.dart';
import 'widgets/app_ui_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Незалежні ініціалізації виконуємо паралельно (вікно ↔ читання збережених налаштувань)
  await Future.wait([
    if (AppPlatform.isDesktop) windowManager.ensureInitialized(),
    StorageService.init(),
  ]);
  // Журнал піднімаємо одразу після налаштувань, щоб записати і помилки запуску
  await AppLog.instance.init(
    directory: Directory('${StorageService.appBasePath}/logs'),
    detailed: StorageService.getDetailedLog(),
  );
  AppDiagnostics.instance.install();
  AppLog.i('застосунок', 'запуск ${AppDiagnostics.build}');
  await ThumbnailService.init(); // Кеш прев'юшок відео
  uiTheme.init(); // Ініціалізація глобальної теми
  HikkaApi.instance.disk = HikkaDiskCache(); // Відповіді Hikka на диску: старт зі збереженого, оновлення у фоні
  unawaited(HikkaMyList.instance.loadIndex(delay: const Duration(seconds: 4))); // Статуси зі списків Hikka для позначок на постерах (якщо ввійшли)
  unawaited(Future<void>.delayed(const Duration(seconds: 8), () => AppUpdater.instance.check(auto: true))); // Тиха перевірка нових версій на GitHub (раз на 12 год)
  unawaited(BackendClient.instance.refreshMoonKey()); // Ключ Moon із бекенду (у фоні, без очікування)

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
    // Телефон: обидві орієнтації (їх визначає датчик і системний автоповорот); кнопка повороту в плеєрі
    // може зафіксувати одну. Системні панелі показує головна, ховає — лише плеєр (див. контролер).
    SystemControls.init();
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  runApp(MaterialApp(
    title: AppIdentity.name,
    debugShowCheckedModeBanner: false,
    navigatorObservers: [AppNavObserver()],
    // Телефон: великий системний шрифт не має ламати панелі з фіксованою висотою
    builder: (context, child) {
      if (!AppPlatform.isMobile || child == null) return child ?? const SizedBox.shrink();
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25)),
        child: child,
      );
    },
    scrollBehavior: const AppScrollBehavior(),
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black,
      textTheme: const TextTheme().apply(
        fontFamily: 'Arial',
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    ),
    home: const PlayerScreen(),
  ));
}
