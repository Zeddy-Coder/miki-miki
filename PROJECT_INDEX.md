# PROJECT_INDEX — Miki Miki (Flutter: Windows + Android)

> Індекс для швидкої навігації. Читай ЦЕЙ файл замість сканування lib/. Номери рядків орієнтовні (оновлюй після великих змін).

## Ключові правила
- Мова коментарів у коді (Dart, Kotlin, тести) — англійська; тексти інтерфейсу лишаються українською. CHANGELOG пишеться англійською першочергово (коротко, щоб лаконічно перекладалось), потім за потреби перекладається.
- Windows media keys (навушники/клавіатура): `MediaControls` (`lib/services/media_controls.dart`, канал `miki_miki/media_controls`; `update(...)` з дедуплікацією, `clear()`, `onButton(play|pause|toggle|next|previous|stop)`), підключено в `PlayerStateController` (`_syncMediaControls`, `_onMediaButton`) і `main.dart` (`MediaControls.init`). Нативна частина — C++/WinRT SMTC: `windows/runner/media_controls.h/.cpp`, повідомлення `WM_APP+0x31` обробляє `FlutterWindow::MessageHandler`; `CMakeLists.txt` лінкує `windowsapp.lib`.
- Інсталятор Windows: `tools/installer.iss` (Inno Setup; AppId не змінювати) + `tools/build_installer.ps1/.bat` (білд, пошук ISCC, стейдж із VC++ dll, версія з pubspec) → `build\MikiMiki-Setup-<версія>.exe`. Потрібен `winget install JRSoftware.InnoSetup`.
- Синхронізація налаштувань між пристроями: `SettingsSync` (`lib/services/settings_sync.dart`, `SettingsSync.instance`, `start()` з `main`, `sync({auto})`, `enabled`). Синхронізуються ключі зі списку `SettingsSync.keys` (вигляд, тема, відтворення, мови, субтитри, Hikka-мова) + позиції `hikka:*` (ключ `pos:…`); пристрійні (hwdec, орієнтація, журнал, плейлисти, ключі) — ні. Модель: кожен ключ `{v, t}`, виграє новіший `t`, видалення = `v:null`; зміни знаходяться порівнянням зі станом попереднього запуску (розділ `settings_sync`), перший запуск на пристрої = час 1 (акаунт перемагає дефолти). Бекенд: `BackendClient.syncGet/syncPut` (заголовки `x-session` + `x-hikka-auth`; сервер дізнається користувача в Hikka `/user/me`), серверний код — `tools/backend/sync.ts` (інструкція підключення в шапці файлу; ДЕПЛОЙ `firebase deploy --only functions,hosting` робить користувач). Застосування: `uiTheme.init()` + `HikkaPrefs.reload()`. Перемикач — у вікні акаунта (`hikka_account_ui.dart`). Тест `test/settings_sync_test.dart`.
- Адмін-панель (лише акаунт Hikka ZEDDY): сервер — `tools/backend/admin.ts` (одна функція `admin`, POST `{action}`: `whoami`, `push.count`, `push.send`, `push.history`; сесія `x-session` + `x-hikka-auth` → Hikka `/user/me` → імʼя в `ADMINS`, інакше 403; ліміти в `limits`; журнал надісланого — колекція `adminLog`; push data-only, як у `push.ts`, мертві токени видаляються). Інструкція підключення в шапці файлу (копія в `functions/src/admin.ts`, `export { admin } from "./admin"`, rewrite `/api/admin`); ДЕПЛОЙ робить користувач. Застосунок: `AdminApi` (`lib/services/admin_api.dart`), сторінка `HikkaAdminPage` (`HikkaRouteKind.admin`, `HikkaNav.openAdmin`), вхід — рядок «Адмін-панель» у «Профілі» (видно лише адміну). Ключа адміністратора в застосунку немає; `pushAdmin` із `x-admin-key` лишається для ручних запитів.
- Push про нові серії (Android, FCM; `pushAdmin` на бекенді — ручні тестові/новинні push, див. README бекенду; канали `episodes_alert` і `news`; повідомлення data-only: `MikiMessagingService.kt` показує сповіщення й складає копію в inbox, `SystemControls.pushInbox` → `EpisodeAlerts.importInbox` кладе їх на вкладку «Сповіщення»; `EpisodeAlert.type` episode/news/update): `PushNotifications` (`lib/services/push_notifications.dart`, `PushNotifications.instance`, `start()` з `main`, `setEnabled`, `sync`) — телефон надсилає бекенду список `slug|releaseId` (`EpisodeAlerts.tracked()`) через `BackendClient.pushRegister`; сервер (`tools/backend/push.ts` → `functions/src/push.ts` у miki_backend: `pushRegister` + планова `episodePush` кожні 30 хв, ОДИН запит до фіду Mikai на всіх, збіги в памʼяті, дедуп у `pushed`) шле FCM. Нативно: `MainActivity` (`pushToken`, `pushPermission`, канал `episodes`, тап по сповіщенню → `miki://open/anime/<slug>` через `mikiLink`; тип `update` → `push_open=update` → `miki://open/update` (вікно оновлення), новина без тайтла → `miki://open/notifications`; `DeepLinks.handle` розбирає обидва), `SystemControls.pushToken/requestPushPermission`; gradle: плагін google-services вмикається лише якщо є `android/app/google-services.json` (без нього збірка працює, push вимкнений, токен null). Перемикач — сторінка «Сповіщення». Секрет CI `GOOGLE_SERVICES_JSON` (base64). Тест `test/push_notifications_test.dart`.
- Теми/кольори: тільки через `uiTheme` (`lib/services/ui_theme_service.dart`), не через AppConstants.
- Назва застосунку (Miki Miki) і технічні ідентифікатори — лише з `AppIdentity` (`lib/constants/app_identity.dart`): `name` («Miki Miki», для людей), `shortName` («MikiMiki»: теки, знімки екрана, `User-Agent`), `packageName` («miki_miki»: пакет Dart, префікс журналів і файлів звіту, канал `miki_miki/system`), `dataDirName` («MikiMiki»: `%APPDATA%/MikiMiki`, `files/MikiMiki`, кеші `hikka_images`, `thumbnails`), `legacyDataDirName` («MyPlayerFork»), `tagline`, `version` (синхронна з `pubspec.yaml`), `userAgent(purpose)`, `migrateLegacyData` (перший запуск на ПК: якщо теки `MikiMiki` ще немає, а `MyPlayerFork` є — її перейменовано чи скопійовано; не кидає винятків; на Android це інший застосунок із власною текою). Рядком «Miki Miki» у коді не писати. Поза Dart назва живе в: `pubspec.yaml` (`name: miki_miki` — звідси імпорти `package:miki_miki/…` у тестах), `android/app/build.gradle.kts` (`namespace` і `applicationId` = `com.mikimiki.app`), `AndroidManifest.xml` (`android:label`), `MainActivity.kt` (пакет `com.mikimiki.app`, канал `miki_miki/system`), `windows/CMakeLists.txt` (`project(miki_miki)`, `BINARY_NAME` = «MikiMiki» → `MikiMiki.exe`), `windows/runner/Runner.rc` і `main.cpp` (заголовок вікна), `README.md`, `CLAUDE.md`, `.idea`. Знак застосунку поки тимчасовий (монограма «M» у бічному меню, `Symbols.smart_display_rounded` у «Про програму»); маскот замінить його, коли буде готовий.
- Банери «Головної»: `BannerArt.instance.load(List<HikkaAnime>)` (`services/banner_art.dart`) → `Map<MAL-id, BannerArtwork>`: спершу AniList (`AniListBanners`: один GraphQL-запит на ≤50 MAL-id, `bannerImage` і `coverImage.color`), для тих, у кого банера немає, — TheMovieDB (`TmdbBackdrops`, лише з ключем: `StorageService.getTmdbKey` — «Налаштування → Розробник → Банери на головній» або `--dart-define=TMDB_KEY=…`; ключ v3 іде параметром `api_key`, v4 («read access token», `eyJ…`) — заголовком Bearer). Кеш на диску (розділ `banner_art` у `StorageService`): знайдений банер — 14 днів, «банера немає» — 2 дні, до 400 записів. Збій AniList не кидає виняток і нічого не записує: віддаються лише застарілі записи кешу. Поки банера немає чи він вантажиться — той самий постер, прокручений крізь крихітну копію (~40 px, `FilterQuality.medium`; без `BackdropFilter`, бо той вбиває кадри). Джерела, які треба називати в «Про програму» й у підписі профілю: Hikka (дані), AniList (банери), TheMovieDB (запасні банери, назви й кадри серій; «використовує TMDB API, але не схвалений і не сертифікований TMDB»), MyAnimeList через Tenrai та Anime Skip (назви серій).
- Локальна медіатека (відкрити файл чи посилання, історія файлів, остання черга, плейлисти) — старий головний екран у `widgets/local_library.dart` (`LocalLibrary`): прихована, вмикається в «Налаштування → Розробник → Приховані можливості» (`StorageService.getLocalLibrary` / `saveLocalLibrary`, `localLibraryListenable` — пункт у «Профілі» зʼявляється одразу). Відкривається як сторінка стека (`HikkaRouteKind.localLibrary`); можливо повернеться як офлайн-режим. Файли, відкриті з неї, ідуть тим самим `PlayerScreen`; `HomeHub` передає в неї `onOpenFile` / `onOpenMultipleFiles` / `onOpenQueue`.
- UI будувати з `lib/widgets/app_ui_kit.dart`; розміри `* scale` (виняток — мобільні віджети: розміри в dp, див. правила про телефон нижче); шрифт Arial; іконки Material Symbols.
- Акцент на відео: `uiTheme.accentOnDark`; текст на суцільному акценті: `uiTheme.onAccent`.
- Прев'ю: тільки `AppMediaThumbnail(uri:…)`; кеш/черга в `ThumbnailService` (один файл = один кеш, повторно не генерується).
- Черга/плейлисти: `StorageService.getLastQueue/saveLastQueue/getPlaylists/createPlaylist/updatePlaylist/deletePlaylist`; відкриття — `PlayerStateController.openQueue(items,startIndex:)`; збереження черги — `persistQueue()` (лише черги з 2+ елементів). UI — вкладка «Плейлисти» і картка «Остання черга» у `widgets/local_library.dart` (локальна медіатека тепер прихована, див. правило «Локальна медіатека»).
- Скрол: `AppSmoothScrollController`.
- Продуктивність: позицію/тривалість/буфер НЕ слухати напряму (`player.stream.position` — 24–60 подій/с). Єдине джерело — `PlaybackClock.of(player)` (`lib/services/playback_clock.dart`): `seconds` (підписи часу), `permille` (тонка смужка), `position/duration/buffer/playing`; похідні — `clock.derive(...)` → `ClockValue` (сповіщає лише при зміні результату), для смужки — `ClockProgress` (зсув ≥1 фізичного пікселя). У віджетах — `AppClockBuilder`, `AppProgressLine`, `AppSeekBar(live:)`; прихована панель = `live:false` → 0 перебудов і 0 кадрів. Перед `player.dispose()` — `PlaybackClock.release(player)`.
- `ValueListenableBuilder` кешує значення: якщо значення оновлюється «тихо» (`ClockValue.refresh()` без notify), будувати через `AppClockBuilder`.
- Часті зміни — окремі нотифікатори, а не `notifyListeners()` контролера (той перебудовує весь екран): `liveStats` (статистика), `volumeState` (`VolumeState`: гучність + mute). Нові «гарячі» значення робити так само.
- У обробниках миші/кадру — жодного синхронного IO (`SeekPreviewService.supports()` кешує перевірку файлу); фонові плеєри (прев'ю) звільняються після 30 с простою.
- Іконка застосунку: джерело — малюнок 512×512 (мишка). Android: адаптивна `res/mipmap-anydpi-v26/ic_launcher.xml` (фон `@color/ic_launcher_background` = `#D6ECFA` у `values/ic_launcher_background.xml`, `mipmap-*/ic_launcher_foreground.png` — малюнок у безпечній зоні 66 dp, `ic_launcher_monochrome.png` — білий силует із лініями для тематичних іконок), `mipmap-*/ic_launcher.png` — кругла для API 24–25; сповіщення — `drawable-*/ic_stat_notify.png` (білий силует; `MikiMessagingService.setSmallIcon` і `default_notification_icon` у маніфесті). Windows: `windows/runner/resources/app_icon.ico` (16–48 із темнішим зовнішнім контуром, 64–256 як намальовано; його ж бере інсталятор). У застосунку — `assets/images/app_logo.png` (коло з фоном; `_appLogo` у налаштуваннях). Маскот на повний зріст — `assets/images/app_mascot.png` («Про програму»).
- Android / телефон: у проєкті є `android/` (збірка: `flutter build apk --release --target-platform android-arm64`, потрібен Android SDK; libmpv — `media_kit_libs_android_video`; AGP 8.13.2 / Gradle 8.14.3 в `settings.gradle.kts` і `gradle-wrapper.properties` — file_picker 11 не збирається з AGP 9). Віконні функції (`window_manager`, міні-плеєр, «поверх усіх вікон», повний екран) — лише коли `AppPlatform.isDesktop`. Платформа — `AppPlatform` (`lib/utils/platform_info.dart`): `isMobile`/`isDesktop` (`debugMobile` — перевизначення для тестів), `defaultHwdec` (Windows `d3d11va-copy`, Android `mediacodec-copy`), `mobileScale` (1.15, лише для старих віджетів), `touchTarget` (48 dp); розкладка екрана — `AppLayout(size)` (portrait/landscape, `isCompactWidth` < 640, `isShortHeight` < 520).
- Мобільний інтерфейс (`PlayerScreen._mobilePlayer`, шари знизу вгору): відео на весь екран → `MobileGestureLayer` (вертикально ліворуч — яскравість, праворуч — системна гучність, горизонтально — перемотка; математика в `TouchGestureMath`) → `SkipButton(touch: true)` → `MobileControls` (новий стиль, `player_kit.dart`: лінійні іконки на відео без плашок; угорі: назад / назва з сірим рядком «Серія N з M · озвучка» / PiP / поворот / налаштування; по центру напівпрозорі кола: попередня · −N с · пауза · +N с · наступна; унизу: повзунок із часом і ряд «1×» · Anime4K · субтитри · звук · «Серії»; усе ≥ 48 dp, розміри в dp, а не `* scale`) → `MobileSheetFrame` (портрет — нижня панель до 68 % висоти, альбомна — бічна справа) з `SettingsDrawer(sheet: true)` / `SidePanel(sheet: true)` → `OsdToast`. Тап по відео показує/ховає панелі (`PlayerStateController.toggleControlsByTouch()`, `touchActivity()`, таймер `TouchHideTimer` 4 с; на паузі, з відкритим меню чи панеллю не ховає). Головна: `HomeHub` у вузькому портреті (`HomeHub.isCompact`) має нижню навігацію з чотирма вкладками (`MainTab`: Головна · Огляд · Списки · Профіль); `AppSettingsDialog` на телефоні на весь екран (портрет — рядок вкладок, альбомна — бічне меню).
- Android-можливості — канал `miki_miki/system` (`SystemControls`, `android/app/src/main/kotlin/com/mikimiki/app/MainActivity.kt`): PiP (`enterPip`; автовхід `setPipAuto` лише поки йде відтворення; у вікні PiP — відео й кнопка «пауза / відтворити»: `RemoteAction` + `BroadcastReceiver` у `MainActivity.kt`, подія `pipToggle` → `onPipToggle`, значок оновлює `setPipPlaying`), аудіофокус (`setAudioFocus`: займається, поки йде відтворення, тож чужа музика на паузі; подія `audioFocus` → `onAudioFocus`: `loss` — пауза, `transient` — пауза й продовження на `gain`; логіка в `PlayerStateController._syncPlaybackSystem` / `_onAudioFocus`), маршрут звуку (`AudioDeviceCallback` у `MainActivity.kt` → подія `audioRoute` {change, devices, route} → `SystemControls.onAudioRoute` → `AudioRouteGuard`: після 0,8 с тиші mpv `ao-reload`; «навушники зняли» `ACTION_AUDIO_BECOMING_NOISY` → `audioNoisy` → пауза з OSD), яскравість вікна (жест; на головній — системна, `resetBrightness`/`restoreBrightness`), системна гучність. Орієнтація вільна (датчик / системний автоповорот, `main.dart`); кнопка повороту в плеєрі фіксує портрет ↔ альбомну (`PlayerStateController.toggleRotation`, довге натискання або вихід на головну — `unlockRotation`). Системна «Назад» — `PopScope` у `PlayerScreen` → `handleBack()`; коли застосунок у фоні (не PiP), відео ставиться на паузу й позиція зберігається (`onAppBackgrounded`). Стан застосунку на Android лежить у постійній теці `files/MikiMiki` (застосунок `com.mikimiki.app` має власну приватну теку: старий `com.example.my_player` — окремий застосунок, його дані не переносяться). Правила для нових мобільних віджетів: розміри в dp, цілі дотику ≥ `AppPlatform.touchTarget`, підказки клавіатури не показувати (`!AppPlatform.isMobile`), меню — через `MobileSheetFrame`.
- Ще не зроблено для телефона: легші мініатюри/прев'ю (зараз «безголовий» libmpv), шрифт Arial відсутній (Roboto), сповіщення/медіа-сесія (керування з шторки), підписання release-збірки власним ключем.
- Навігація й вміст (Miki Miki — «hikka-first»: усе, що бачить людина, — це дані hikka.io; аніме, манґи й ранобе в каталозі немає): чотири головні вкладки `MainTab` — «Головна», «Огляд», «Списки», «Профіль». `HomeHub` (`widgets/home_hub.dart`) — лише оболонка: нижня навігація на телефоні в портреті, `AppSidebar` (монограма «M» як тимчасовий знак, назва й підпис з `AppIdentity`, «Налаштування», версія) на ПК і широких екранах; налаштування відкриваються з «Профілю» й знизу бічного меню (`onOpenSettings({int? tab})` → `AppSettingsDialog.show(initialTab:)`). `HikkaHub` (`widgets/hikka/hikka_hub.dart`) тримає вкладки (`HikkaHomePage`, `HikkaDiscoverPage`, `HikkaListsPage`, `HikkaProfilePage`; будуються ліниво й після відкриття не руйнуються — `Offstage` + `TickerMode`, тож пошук і прокрутка лишаються на місці) і шар відкритих сторінок `HikkaRoute` поверх них (`AppFadeSwitcher`, `HikkaBackBar` з «Оновити» та «Відкрити на hikka.io»). `HikkaNav` — одинак (`ChangeNotifier`; власний стек, не `Navigator`): `setMain(MainTab)`, `setTab(HikkaTab)` (розділи «Огляду»: Усе · Календар · Каталог · Колекції · Статті · Персонажі), `openCatalog(HikkaSearchFilters, {focusSearch})` / `openSearch()` (+ одноразові `takePendingFilters` / `takeFocusSearch`), `openAnime` / `openCharacter` / `openPerson(slug, seed, roles)` (`roles` — одразу на вкладці «Ролі») / `openFranchise` / `openAnimeCharacters` / `openCollection` / `openArticle` / `openLocalLibrary` / `openAdmin`, `openLink(url)` (посилання з описів і статей), `back()` з охоронцями `addBackGuard`. «Назад»: `HomeHub.backHandler` (статичний хук; викликає `PlayerScreen._wrapMobile` після `handleBack()`) = `HikkaNav.back()`: охоронці (панель фільтрів тощо) → сторінки зі стеку → з кореня іншої вкладки на «Головну»; на «Головній» повертає `false` — тоді екран плеєра вирішує, чи виходити із застосунку. Мишача кнопка «Назад» теж працює (`kBackMouseButton`). Нова сторінка = новий `HikkaRouteKind` + `HikkaNav.openXxx` + гілка в `HikkaHub._page` + заголовок / адреса в `_routeTitle` / `_routeUrl`.
- Головна (`HikkaHomePage`): рядок пошуку (дотик → `HikkaNav.openSearch()`) і сповіщення (заглушка `HikkaNotificationsDialog`: нові серії й озвучки з Hikka та Mikai зʼявляться після входу), тонка стрічка календаря `HikkaAiringStrip` (які серії щойно вийшли й які вийдуть; підпис — `HikkaAiring.of(entry, now)`; «Календар» → `setTab(HikkaTab.schedule)`), банери поточних онґоїнґів `HikkaBannerCarousel` (гортаються самі; фон — `BannerArt`, див. правило нижче), полиці «Продовжити перегляд» (`ContinueWatching.load`; порожня — не показується), «Рекомендації», «Зараз виходить», «Анонси», «Найпопулярніші», «Найкращі за оцінкою». На телефоні вкладка оновлюється потягом вниз (`HikkaPageFrame.onRefresh`), на ПК — кнопка «Оновити».
- Акаунт Hikka (вхід, списки, прогрес; з v1.0.3). `HikkaAuth` (`services/hikka_auth.dart`, `HikkaAuth.instance`, ChangeNotifier; фази `HikkaAuthPhase`: signedOut / waiting / exchanging / signedIn; дані — розділ сховища `hikka_auth`: `token`, `me`, `sync`, власний клієнт `client_ref` / `client_secret`). Потік входу (застосунок третьої сторони, як на hikka.io/oauth): `startLogin()` піднімає тимчасовий сервер `HikkaLoopback` на `127.0.0.1:47615` (лише GET `/auth/confirm`, Host тільки `127.0.0.1`/`localhost`; гасне після входу чи скасування) і відкриває `https://hikka.io/oauth?reference=<клієнт>&scope=user-details,watchlist,favourite`; людина тисне «Продовжити» — сайт перекидає на зареєстровану адресу клієнта з кодом запиту (`HikkaAuth.redirectUri` = `http://127.0.0.1:47615/auth/confirm` — саме її вписано як «endpoint» клієнта на hikka.io; окремий домен не потрібен) → `POST /auth/token {request_reference, client_secret}` → токен → `GET /user/me`. Запасний шлях без порту: людина вставляє адресу, на яку її перекинуло, або сам код — `submit()` / `parseReference()` (UUID, `reference=` / `request_reference=`). Токен іде заголовком `auth: <секрет>` лише в запитах `HikkaApi._request(auth: true)`; 400 із кодами `auth:*` → `HikkaErrorKind.unauthorized` → `onUnauthorized` розлогінює («Сесія Hikka завершилась»); `HikkaApi.sharedTokenProvider` / `sharedOnUnauthorized` — статичні, щоб підміна `HikkaApi.instance` у тестах не відчепила токен. Вихід `signOut()` відкликає токен (`GET /auth/token/info` → `DELETE /auth/token/{ref}`), але локально виходить завжди. Сторінка згоди показує «Невідомий застосунок», доки Hikka не позначить клієнта верифікованим — це нормально. Схему всіх методів можна взяти з `https://api.hikka.io/openapi.json` (звірено з v0.4.4: `WatchArgs` — `status` обовʼязковий, дати рядком date-time; `WatchResponse` — дати числами; `TokenProceedArgs`, `TokenResponse{secret, created, expiration}`, `TokenRequestResponse{reference, redirect_url, expiration}`, `AuthTokenInfoResponse{reference, scope, expiration…}`; запити акаунта — заголовок або кукі `auth`).
- Клієнт Hikka (референс і ключ застосунку) — ЛИШЕ `HikkaClientKey` (`services/hikka_client_key.dart`): значення зберігаються замаскованими (XOR двох масивів), а НЕ рядками; жодних літералів ключа чи референсу в коді, тестах (там `HikkaClientKey.testOverride`), журналі, індексі та відповідях. Свій клієнт людина вписує в «Налаштування каталогу → Свій клієнт Hikka» (`HikkaAuth.setCustomClient`; діє при наступному вході, має перевагу). Якщо секрет на hikka.io перестворили, вбудований перестає працювати: треба замінити масиви в `HikkaClientKey` на нові (нове значення дає користувач у чаті; у файли, тести й індекс його не писати, у відповідях не повторювати).
- Списки Hikka: `HikkaMyList` (`services/hikka_lists.dart`, `HikkaMyList.instance`, ChangeNotifier; скидається при вході й виході): `entry(slug)` — мій запис (`GET /watch/{slug}`, 404 = немає; кеш у памʼяті), `save(slug, {status, episodes, score, total})` (`PUT /watch/{slug}` — завжди повний запис, щоб не стерти оцінку, нотатку, дати; «Переглянуто» добиває лічильник до кінця, лічильник не перевищує кількість серій), `remove`, `stats()`, улюблене `isFavourite` / `setFavourite`, `version` (росте при змінах — за ним перезавантажується «Списки»). Моделі — `models/hikka_user_models.dart` (`HikkaWatchStatus` watching / planned / completed / on_hold / dropped, `HikkaWatchEntry`, `HikkaWatchStats`, `HikkaMe`, `HikkaToken`). UI: `HikkaAccountCard` і `HikkaLoginDialog` (`widgets/hikka/hikka_account_ui.dart`; у «Профілі» й у «Списках» для гостя); «Списки» після входу — чипи статусів із лічильниками («Дивлюсь · N») + «Улюблене», картки з плашкою `серії/всього` (для «Дивлюсь», «Відкладено», «Кинуто») і `★ оцінка` в підписі, довге натискання / права кнопка — «Прибрати зі списку»; на сторінці аніме кругла закладка (`HikkaMyListBar` у `hikka_my_list_bar.dart`, `Positioned` на банері в `HikkaAnimePage._top` навпроти «Назад»; значок статусу малює `HikkaListMark`; тултіп «Додати в список» / «У списку: <статус>»; гість → вхід; меню: статуси, «Серії…» → `HikkaListEditDialog`, «Оцінити»/«Оцінка: N» (власне меню 1–10), «В улюблене», «Видалити зі списку»).
- Прогрес із плеєра: `RemoteDriver._markWatched` для ключів `hikka:<slug>` викликає `HikkaMyList.syncEpisode(slug, номер, total:)` (без `await`, збої тихі; лише коли ввійшли й увімкнено `HikkaAuth.syncProgress`): тайтл потрапляє в «Дивлюсь», лічильник серій лише зростає, після останньої серії — «Переглянуто»; вже «Переглянуто» не чіпається. Номер — `HikkaMyList.episodeNumber(number, position, total)` (номер із джерела, якщо він цілий і не більший за кількість серій, інакше позиція серії в черзі).
- «Огляд» (`HikkaDiscoverPage`) — розділи: «Колекції» (`HikkaCollectionsPage` → `HikkaCollectionPage`) і «Статті» (`HikkaArticlesPage` → `HikkaArticlePage`) — користувацький вміст Hikka (`HikkaApi.collections/collection/articles/article`, моделі — `hikka_community_models.dart`, текст статей — документ Slate, малює `HikkaSlateView`: абзаци, заголовки, списки, цитати, спойлери, картинки з переглядом `HikkaImageViewer`, відео, посилання всередину застосунку); «Каталог» (`HikkaCatalogPage`); «Персонажі»; «Календар». Списки з підвантаженням — `HikkaPagedList<T>`; рядки — `HikkaCollectionRow` / `HikkaArticleRow` (`hikka_community_cards.dart`). Колекції з позначкою 18+ ховаються, поки вимкнено `HikkaPrefs.allowAdult`.
- «Списки» (`HikkaListsPage`) — для гостя картка входу й пояснення, що буде після входу (Дивлюсь · У планах · Переглянуто · Відкладено · Кинуто · Улюблене); після входу — вкладки статусів із лічильниками та «Улюблене» (правило «Акаунт Hikka» нижче). «Профіль» (`HikkaProfilePage`) — після входу профіль Hikka як на `hikka.io/u/<імʼя>` (`HikkaUserProfile`, `widgets/hikka/hikka_user_profile.dart`: обкладинка, аватар, роль, опис, посилання, «стежать / відстежує», «На Hikka з…»; «Список» — `HikkaWatchSummary`: лічильники статусів, смуга-пропорція, «Час перегляду» (`HikkaProfileText.watchTime`, місяць = 30 днів); «Активність» — `HikkaActivityHeatmap` за рік (стільки тижнів, скільки влазить; натискання / наведення — дії за день) і коментарі · відгуки · правки; полиці «Улюблені аніме» / «Улюблені персонажі»; «Статті» й «Колекції» автора (порожні не показуються); «Історія» — `HikkaHistoryList` по днях, лише аніме, «Показати ще»); лічильники статусів і «Усі» в улюблених ведуть у «Списки» (`HikkaNav.openLists`). Після входу «Акаунт» (`HikkaAccountDialog`: перемикач «Передавати прогрес у списки», «Вийти з акаунта»), «Налаштування застосунку» — дві іконки в шапці вкладки («Про Miki Miki» — вкладка в налаштуваннях; коли є оновлення, на шестерні точка й вона відкриває саме її); внизу лишається лише «Локальна медіатека» (якщо ввімкнена). Гість бачить картку входу й звичайні рядки меню. Чужий профіль — сторінка `HikkaRouteKind.user` (`HikkaNav.openUser(імʼя)`, `HikkaUserPage`; власне імʼя відкриває вкладку «Профіль»), сюди ж ведуть посилання `hikka.io/u/<імʼя>` (`HikkaLinkKind.user`) та автор статті. Далі: «Налаштування застосунку» (`AppSettingsDialog`), «Каталог і дані» (`HikkaSettingsDialog`), «Джерела перегляду» (`SourcesDialog`), «Про Miki Miki» (`AppSettingsDialog.tabAbout`), прихована «Локальна медіатека» й підпис джерел даних.
- Дані Hikka — лише через `HikkaApi` (`lib/services/hikka_api.dart`; api.hikka.io без авторизації, `dart:io` `HttpClient`, нових пакетів у pubspec немає): кеш із TTL, спільні запити (один URL — один політ), застарілі дані при збої, повтор на 5xx / мережевих помилках; відповіді розбирає `lib/models/hikka_models.dart` (чиста Dart-логіка, без Flutter); помилки — `HikkaException` з українським `message`. Тести підміняють `HikkaApi.instance = HikkaApi(sender: …)` (записані відповіді — `test/support/hikka_fakes.dart`), `HikkaImageStore.instance`, `HikkaPrefs.instance`, `HikkaNav.instance`.
- Зображення Hikka: `HikkaImage` (`ImageProvider`) → `HikkaImageStore` (диск: тека `MikiMiki/hikka_images` у тимчасовій теці системи (`AppIdentity.dataDirName`), до 300 МБ; обмежений паралелізм, останній запит — першим; `diskSize()` / `clear()`), зменшені копії через img.hikka.io (`HikkaImages.resized`); у віджетах — `HikkaPoster` (+ `ResizeImage` під розмір картки). Описи й синопсиси — Markdown сайту (`:::spoiler`, посилання на сторінки каталогу, колекції й статті): `HikkaMarkdown.parse` → `HikkaMarkdownView` (`HikkaSpoilerBox` — спільний із `HikkaSlateView`).
- 18+: `HikkaPrefs.allowAdult` (типово вимкнено; перемикач у `HikkaSettingsDialog`). Пошуки підміняють порожній рейтинг на безпечні (`HikkaSearchFilters.toBody`), списки додатково фільтруються (`HikkaAnime.isAdult`), франшиза ховає 18+ вузли, сторінка аніме 18+ закрита заглушкою («Показати цю сторінку» діє лише для неї: `route.memo['revealed']`).
- Нова сторінка каталогу: `HikkaRoute` має `scroll` і `memo` (завантажене, режим, пейджер) — вони переживають перебудову сторінки; прокрутку брати з `AppSmoothScrollController(initialScrollOffset: route.scroll)`; завантаження — `HikkaAsync` / `HikkaPagedGrid` (+ `HikkaPager`), полиці — `HikkaShelfAsync`; каркас — `HikkaPageFrame` / `HikkaSection`. Пастка Dart: `future.whenComplete(() => map.remove(key))` — `remove` повертає сам Future зі списку, і `whenComplete` чекає на нього (вічне очікування або чужі помилки); завжди тіло з дужками `{ map.remove(key); }`.
- Каталог — ще не зроблено: окремі сторінки людей (сейю, автори) — зараз лише текст; сповіщення про нові серії (вхід в акаунт, списки й синхронізація «переглянуто» вже зроблені — правило «Акаунт Hikka»); блок «Першоджерело» (манґа/ранобе) з MangaBaka (`api.mangabaka.org`, публічне API; зв'язок — через AniList `relations` з типом SOURCE; джерело даних треба вказувати); «репозиторії» (додавання сайтів без перезбірки застосунку) — спершу домовитись із користувачем, коли перегляд перевірено на живих сайтах.
- Перегляд аніме з сайтів (порт моделі Aniyomi на Dart; нових нативних залежностей немає, лише пакет `html`): джерело — це `AnimeSource` (`lib/services/sources/anime_source.dart`: `popular` / `latest` / `search` / `details` / `episodes` / `hosters` / `hosterVideos` / `videos`; для DLE-сайтів — `HttpAnimeSource` з `document()` і `parseList()`). Джерела лежать у `lib/services/sources/ua/`: `MikaiSource` (api.mikai.me, основне: за slug Hikka віддає релізи по командах озвучення / субтитрів, прапорець `licensed`), `UfDubSource` (ufdub.com, прямі mp4), `UaKinoSource` (uakino.best, плейлист `playlists.php` → Moon / Ashdi). Відео дістають екстрактори (`extractors.dart`): `MoonExtractor` (обидва шаблони сторінки — Video.js і PlayerJS; розшифровує посилання, субтитри й таймкоди пропуску), `AshdiExtractor` (`index.m3u8`); майстер-плейлисти HLS розбирає `hls.dart` (якості «Авто / 1080p / 720p / 480p»). Fenix і Tortuga не підтримуються: серії лише з ними відкидає `MikaiSource.episodesOfRelease`. Новий сайт = клас `AnimeSource` у `ua/` + рядок у `SourceRegistry.standard()` + тест на збережених сторінках (`test/data/sources/`).
- Мережа джерел — лише через `SourceHttp` (`source_http.dart`: `dart:io`, ручні редиректи, `CookieJar`, помилки `SourceException(kind: SourceErrorKind…)` з українським повідомленням). Перевірки Cloudflare поки немає (див. нижче). У тестах `SourceHttp(sender: …)` підміняє відповіді (`test/support/fake_site.dart`: `FakeSite({'підрядок «МЕТОД адреса»': відповідь})`). Селектори Jsoup емулює `html_select.dart` (`select`, `selectFirst`, `attr`, `text`) над `package:html`. Посилання на відео діє кілька годин, тому `StreamResolver.resolve` викликається в момент відтворення, а не при показі списку серій. Діагностика: `SourceLog` (`services/sources/source_log.dart`, `SourceLog.add(текст)`, ≤400 рядків, значення token/key/apikey приховуються) — кожен запит `SourceHttp` (→ метод адреса, ← код / мс / байти або ✗ помилка), кроки `StreamResolver`, `MoonExtractor.extract`, `RemoteDriver` (відкриття, таймер, збої). CDN Moon (mooncdn.online, Cloudflare) віддає 403, якщо в запиті немає `Accept-Language` разом з `Accept` (ffmpeg/libmpv шле лише `Accept`; перевірено на живому сервері) — тому заголовки відео Moon містять `HlsProxy.browserDefaults`. На Android відео Moon йдуть через локальний HLS-проксі (`HlsProxy`, `hls_proxy.dart`): libmpv (mbedtls) не проходить CDN mooncdn.online (збій TLS / 403), а `dart:io` проходить. `HlsProxy.enabled` (за замовчуванням лише Android), `HlsProxy.instance.wrap(url, headers)` → адреса `http://127.0.0.1:порт/…`; списки переписуються (`rewritePlaylist`), сегменти віддаються з Range і заголовками оригіналу. Показується у «Статистика → Джерела» і в «Копіювати звіт». Нові кроки джерел логуйте через `SourceLog.add`.
- Журнал (єдиний): `AppLog` (`services/app_log.dart`) — `AppLog.i/w/e/d(тег, текст)`; `AppLog.on` (детальний режим) — захищайте ним дорогі рядки. Памʼять: кільце 1500 рядків (у детальному режимі 8000). У детальному режимі ще й файл сесії `<appBasePath>/logs/miki_miki_<дата>_<час>.log` (ротація: 6 МБ на файл, до 8 файлів / 30 МБ, поточна сесія не видаляється; журнали під старою назвою `my_player_*.log` теж читаються й прибираються — `AppLog.legacyFilePrefix`); секрети маскуються (`AppLog.sanitize`), однакові рядки поспіль згортаються. Режим: `StorageService.getDetailedLog` (типово УВІМКНЕНО на час тестування), перемикач — «Налаштування → Розробник → Журнал і діагностика» (`AppLog.setDetailed`); докладність libmpv (`MPVLogLevel.v`) береться при створенні плеєра, тож змінюється після перезапуску. Зберігати журнал треба ЗАВЖДИ у файл (не в буфер обміну): `LogExport.save` → системне вікно «Зберегти як» (`FilePicker.saveFile`; на телефоні — вибір теки, напр. «Завантаження»); кнопки — «Розробник → Зберегти журнал у файл» і «Статистика → Зберегти у файл». Файл звіту: шапка (пристрій, екран, налаштування — `AppLog.environment`) + додаткові розділи + журнал сесії + хвіст попереднього запуску. Що пишеться: помилки Flutter і необроблені асинхронні (`AppDiagnostics.install`), життєвий цикл, розміри вікна, повільні кадри, памʼять, стан Android (`SystemControls.deviceInfo`: модель, RAM, енергозбереження, нагрів, маршрут звуку — Bluetooth тощо), навігація діалогами (`AppNavObserver`) і вкладками / сторінками (`HikkaNav`, тег `навігація`), банери (тег `banners`), дії контролера плеєра (тег `дія`), гарячі клавіші, Anime4K, `SourceLog` (тег `джерела`), запити Hikka (тег `hikka`), події плеєра та знімок синхронізації кожні 3 с (`PlayerDiagnostics`, тег `синхронізація`: avsync, втрачені й запізнілі кадри, буфер; відхилення — попередження через `analyzeSync`). Нові підсистеми логуйте через `AppLog`.
- Орієнтація плеєра (телефон): `OrientationPolicy` (`services/orientation_policy.dart`) + налаштування `StorageService.getPlayerOrientation` (`PlayerOrientation`: system / landscape / portrait; «Налаштування → Відтворення → Орієнтація плеєра»). Поки відео на екрані (`!showHome`), діє налаштування; при виході на головну чи згортанні в міні-плеєр повертається те, що було до відкриття плеєра (`PlayerStateController._syncSystemUi` → `enterPlayer` / `leavePlayer`); кнопка повороту в плеєрі теж скидається при виході. `rotationLocked` — геттер політики.
- Hikka API (`hikka_api.dart`): мережеві збої (`SocketException`, `HttpException`, TLS) повторюються до 3 спроб, тайм-аут і 5xx / 429 — до 2; після будь-якого збою транспорту спільний `HttpClient` відкидається (м'яке закриття: запити, що йдуть, доробляються, нові — на новому клієнті з чистим пулом з'єднань; мертві з'єднання з пулу давали «Немає зв'язку» через раз). Причина кожної спроби (`HikkaApi.describeError`: тип винятку, код ОС) і перевірка DNS після збою пишуться в `AppLog` (тег `hikka`).
- Потік «Дивитись»: `WatchService.start(HikkaAnime)` → `WatchLoad` (ChangeNotifier: `title` — `WatchTitle` з `WatchOffer` на кожне джерело, `pending`, `busy`, `checkOf(group)`). Mikai шукається за slug Hikka (запасний шлях — MAL-id), решта сайтів — пошуком за назвами Hikka (`title_match.dart`: `bestAnimeMatch`; розбіжність сезону чи типу OVA / фільм різко знижує оцінку); знайдене запам’ятовує `WatchStore.setLink`. Серії групуються в `WatchGroup` (озвучення першими, далі субтитри; всередині — де серій більше). Налаштування — `SourcePrefs` (ввімкнені джерела, ключ API Mikai, бажана якість і плеєр), переглянуте й остання серія — `WatchStore`; обидва зберігаються розділами `StorageService.getSection/saveSection`. Варіант за кнопкою «Дивитись» — `WatchLoad.defaultGroup(store)` = `pickGroup(groups, preferredId: store.preferredGroup(animeKey), favorites: store.favoriteChoices, safe: checkOf(g).syncSafe)`: обраний (або останній переглянутий) для цього тайтлу → улюблена команда з інших тайтлів (`choiceKeyOf`: вид + id команд або `джерело:назва`; `WatchStore.setFavoriteChoice`, до 8, найновіші першими) → перший варіант без розбіжності нумерації → перший. Вибір людини завжди сильніший за «безпеку»: склеєний варіант («24 з 12») не нав'язується, але й не забороняється.
- Вибір озвучення для «Дивитись / Продовжити» (`watch_service.dart`, `watch_models.dart`): `WatchLoad.defaultGroup(store, {seen})` — спершу озвучення, закріплене вручну для тайтла (`WatchStore.pinnedGroup`, ставиться з вибору в блоці «Дивитись» і `RemoteDriver.switchGroup`), якщо воно має серію `seen + 1`; далі групи, що мають цю серію; далі групи з пізнішими серіями; далі всі. У межах шару за `StorageService.getPreferFullDub` повні озвучення (`!WatchGroup.isPartial`) стоять вище, а далі діє пріоритет команд (`pickGroup`). `seen` = більше з відміток Hikka (`HikkaMyList.entry`, свіжий запит при «Дивитись») і історії застосунку. Якщо закріплена група не має наступної серії, `WatchLoad.missingNext(store, {seen})` повертає `MissingNext` (закріплена / наступна за пріоритетом / повна), а `WatchDialogs.missingNext` питає, куди перейти (вибір знімає закріплення). Охоплення серій для підписів — `WatchGroup.coverage` («1–5, 7–19»; `ranges({limit})` ігнорує зайві серії за `looksLikeExtra` і номери понад `WatchTitle.episodeLimit` = кількість серій на Hikka); `sortGroups(..., fullFirst, limit)`. Відмітка на Hikka: `HikkaMyList.episodeNumber({number, position, total, trustNumber})` — номер серії з плеєра, не більший за `total`; `RemoteDriver._syncToHikka` довіряє номеру, лише якщо мінімальний номер варіанта не перевищує `total` (інакше нумерація наскрізна й береться позиція).
- Звірка з Hikka (`episode_check.dart`, `checkEpisodes(episodes, HikkaEpisodeInfo)`): рівні `match / unknown / lag / incomplete / lead / extra / mismatch`. Розбіжність нумерації — злиті частини («24 з 12»), наскрізна 13–24, повтори номерів, OVA посеред сезону, кілька сезонів, серії без номерів — це `mismatch`: показати дисклеймер (без речення про синхронізацію: що відмітки йдуть за номером серії, і так зрозуміло) і не обирати такий варіант автоматично (`syncSafe == false`). Менше чи більше серій, ніж на Hikka (`lag`, `incomplete`, `lead`), пропуски в нумерації й старт із середини сезону, коли номери тримаються, — без примітки взагалі (`note` порожній; кількість видно в рядку озвучки «10 з 19»); примітка лишається для OVA в кінці (`extra`) і порожньої сторінки «0 з N». Окремо `numbersHold` — чи кожен номер досі означає ту саму серію на Hikka (за ним працюють AniSkip і пісні): пропуски нічого не зсувають (у «Ґінтамі» перші дві серії йдуть однією, тож у озвучок 1, 3, 4…), 0 перед 1 — теж; старт не з 1 — лише коли інша озвучка того ж сайту йде з 1 (`checkEpisodes(othersFrom:)`; `checkGroup(group, info, all:)` бере його з `othersFromOf` — так роблять `WatchLoad.checkOf` і `RemoteDriver.checkOf`: «Далі Буде» в «Переродженні» 4 — 10–19 з 19) і номери в межах «всього» (або вже вийшлого, з запасом 2 для онґоїнґу); повтори, кілька сезонів, OVA посеред, рахунок від нуля (0…N−1 для N серій), номери понад «всього» чи старт не з 1 без такого сусіда — зсувають. OVA лише в кінці → `extra` із `syncLimit` (синхронізувати до цього номера). «0 з N» (сторінка є, серій немає) → `incomplete` / `lag`. `looksLikeExtra(name)` визнає OVA лише за позначкою на початку назви чи в дужках («Серія 12. Special Training» — звичайна серія).
- Тести (`test/`; запуск: `flutter test test/sources_*_test.dart test/watch_services_test.dart test/watch_pick_test.dart test/continue_dub_test.dart test/update_prompt_test.dart test/track_defaults_test.dart test/hls_proxy_test.dart test/app_log_test.dart test/orientation_policy_test.dart test/player_diagnostics_test.dart test/remote_playback_test.dart test/remote_driver_test.dart test/hikka_core_test.dart test/identity_test.dart test/hikka_community_test.dart test/hikka_slate_test.dart test/home_services_test.dart test/hikka_franchise_test.dart test/hikka_markdown_test.dart test/touch_hide_timer_test.dart test/anime4k_test.dart test/downloads_test.dart test/downloads_ui_test.dart`): детерміновані, без мережі (сторінки сайтів — `test/data/sources/*`, відповіді Hikka — `test/support/hikka_fakes.dart`). `sources_live_test.dart` ходить у справжні сайти (UFDub, Mikai, UAKino) лише з `LIVE=1` (транспорт застосунку; з `LIVE_CURL=1` — через `curl`, `test/support/curl_sender.dart`, для пісочниць без прямого `dart:io`). Драйвер перегляду — `remote_driver_test.dart` (`test/support/remote_fakes.dart`: `FakeEngine`, `FakeSource`, `Rig` — стенд із драйвером, сховищем у пам'яті й керованими плеєрами). Віджетні тести (`remote_ui_test.dart`, `hikka_watch_ui_test.dart`, `hikka_ui_test.dart` та інші з `loadTestFonts()` з `test/support/fakes.dart`) прив'язані до шляхів шрифтів середовища, де їх писали, і до теки користувача не потрапляють. `watch_pick_test.dart` — який варіант відкриває «Дивитись» (`pickGroup`, `choiceKeyOf`, улюблені); `track_defaults_test.dart` — мови доріжок (`LangMatch`) і автовибір субтитрів та звуку (`TrackDefaults`). `Rig` у `remote_fakes.dart` має параметр `subLangs` (пріоритет мов субтитрів). `app_log_test.dart` — журнал (рівні, згортання повторів, маскування, файл, ротація, звіт) і збереження у файл (`LogExport`); `orientation_policy_test.dart` — орієнтація плеєра; `player_diagnostics_test.dart` — `analyzeSync`. У `hikka_core_test.dart` — повтори мережевих збоїв. `identity_test.dart` — `AppIdentity` (назви, `userAgent`, перенос даних зі старої теки); `hikka_community_test.dart` — колекції й статті Hikka (моделі, `HikkaApi`, Slate, посилання); `hikka_slate_test.dart` — текст статей (`HikkaSlateView`): розмітка, списки, цитати, посилання (власний обробник, каталог, браузер), спойлери, картинки й перегляд на весь екран. `hikka_synopsis_test.dart` — опис `HikkaSynopsis`: у згорнутому посилання не діють (дотик лише розгортає), у розгорнутому працюють, короткий текст одразу повністю. `home_services_test.dart` — `HikkaText.compact`, `HikkaAiring.of`, `ContinueWatching`, `AniListBanners` / `TmdbBackdrops` / `BannerArt` (кеш, TTL, запасний пошук). `HikkaTestEnv` (`test/support/hikka_fakes.dart`) — готовий стенд для віджетних тестів Hikka: підмінює `HikkaApi` (`FakeHikka`), зображення, `HikkaPrefs`, `WatchService`, `BannerArt` (AniList віддає банер лише для парних MAL-id; TMDB без ключа) і `HikkaNav` (`opened` — записані зовнішні посилання); `dispose()` повертає все назад. Віджетні тести `hikka_ui_test.dart` (десктоп, банери, телефон, оболонка `HomeHub`, стани, вузьке вікно) і `mobile_test.dart` використовують його. `FakeHikka.interceptor` — власні відповіді поверх записаних; `HikkaTestEnv` підставляє `HikkaAuth` (гість, без локального сервера, браузер — лише журнал `opened`) і `HikkaMyList`. Акаунт: `hikka_auth_test.dart` (потік входу, локальний сервер, запасне вставлення адреси, токен, вихід), `hikka_lists_test.dart` (запис, збереження без втрати полів, улюблене, синхронізація прогресу), `hikka_lists_ui_test.dart` (вхід у вікні, «Списки» зі статусами, «Мій список» на сторінці аніме, профіль; `FakeAccountServer` — стан акаунта, що змінюється запитами); підроблений сервер входу й списків для сервісних тестів — `test/support/hikka_account_fakes.dart`.
- Серії з сайтів у плеєрі: кнопки блоку «Дивитись» викликають `WatchLauncher.play(RemoteLaunch)` (`remote_playback.dart`); `PlayerScreen` підписується через `WatchLauncher.attach(state.openRemote)` (відписка в `dispose`) → `PlayerStateController.openRemote(launch)` → `RemoteDriver.start`. `RemoteDriver` (`lib/services/remote_driver.dart`) — чиста логіка без media_kit і віджетів: плеєр для нього — інтерфейс `RemoteEngine` (у застосунку `MpvRemoteEngine`, `remote_engine.dart`; у тестах `FakeEngine`). Фази `RemotePhase` (idle / resolving / opening / playing / failed). Посилання на потік шукається в момент відтворення (`StreamResolver`; живе кілька годин), місце початку передається опцією `Media.start`, позиція зберігається через `StorageService.savePlaybackPosition` (ключ запису `hikka:<slug>#<серія>`), «переглянуто» — за `episodeSeen` (≥ 85 % або ендінґ), автоперехід — за `StorageService.getAutoplayNext()`. Сторож запуску: 30 с (`openTimeout`) і 6 с після помилки mpv (`errorGrace`; помилки бувають дрібні) → наступний не пробований плеєр → «Не вдалося» з «Повторити»; якщо потік завис посеред перегляду — нове посилання з того ж місця (`_recover`, не частіше ніж раз на 30 с).
- Чого не можна робити із серіями з сайтів: у mpv відкрите лише одне відео, тому в `player.playlist` лежать «синтетичні» елементи `remote://<ключ>` (щоб працювали черга, `currentPlaylistIndex` і заголовок) — `player.next()/previous()`, `reorderQueue` / `removeFromQueue` / `persistQueue` для них не викликати: «Наступна / Попередня» — це `PlayerStateController.playNext()/playPrevious()` (самі розрізняють файли й серії; їх передають у `BottomDock` / `MobileControls` через `onNext` / `onPrevious`), вибір серії — `selectEpisode(i)` (веде в драйвер). `currentFilePath` для серії = ключ запису; `SeekPreviewService.supports()` відхиляє адреси `схема://` (наведення на смужку не показує прев'ю потоку); `remote.stop()` викликають усі `open*` і `returnToHome`.
- Інтерфейс серій: `RemoteStatusOverlay` (`widgets/remote_status_overlay.dart`: «Шукаю відео…», помилка з діями «Спробувати ще / Інший плеєр / Озвучки та плеєри / Наступна серія / Закрити»; під час стану на телефоні ховається перемотка — `MobileControls.showTransport`), `RemotePanelBody` (`widgets/remote_panel.dart`: вкладки «Серії» / «Озвучка» / «Плеєр» (плеєр і якість) — перемикання на льоту з того ж місця). Бічна панель і шторка на телефоні показують його замість черги файлів, коли `state.remote.active` (`SidePanel(remote:)`, `SidePanelDrawer(remote:)`); «Інформація» показує серію, озвучку й плеєр (адресу потоку не показуємо). Розділи беруться з таймкодів Moon (`chaptersFromTimestamps`), тож «Пропустити опенінг» працює звичайним `SkipButton`; без таймкодів сайту — з AniSkip і аналізу звуку (`SkipService`, правило «Пропуск опенінґу без таймкодів сайту»).
- Блок «Дивитись» (`widgets/hikka/hikka_watch_section.dart`) стоїть під шапкою сторінки аніме (ПК: назва → `_scores` → `_watch(wide: true)` → жанри → опис; телефон: див. «Сторінка аніме»). Заголовка немає. Головна кнопка `_mainButton` — `AppAccentButton(solid, expand, compact, leading: _playGlyph)` (44 dp, текст `onAccent(accent)` — темний на світлому акценті, трикутник малює `_GlyphPainter`), видна з першої миті («Дивитись / Продовжити · серія N / Дивитись знову»). Під нею `_summary`: мікрофон (жовтий знак — `episodeCheckWarns`), рядок «команда · переглянуто N з M · якість» і сіра плашка 44×38 `_panelButton` (тултіп «Ще», дві повзунки `_Glyph.sliders`); поки нічого не знайдено, `_panelButton` стоїть поруч із кнопкою. Тихий рядок «Наступна серія N · коли» (`_nextEpisodeRow`, з `HikkaAnime.nextEpisode`). Панель «Перегляд» `_openMenu`: телефон — `showModalBottomSheet` у `_PanelSheet` (ручка, «Перегляд», «Закрити»), ПК — `WatchDialogFrame`; вміст `_panelBody` з рядків `SettingsRow`/`SettingsChoiceRow`: «Озвучення»/«Субтитри» (`_variantLine`, `_episodesOf`: «28 з 28 серій» / «1–12 з 28»; тап → `_pickVariant`: телефон — окрема шторка `_PanelSheet`, ПК — `WatchDialogFrame`; плашки `_kindPlate` «Озвучення · N / Субтитри · N», рядки `_variantRow` (ключ `variant-<id>`, аватарка, серії й «оновлено ДД.ММ», жовта крапка `variant-warn-<id>` для `episodeCheckWarns`, жовта галочка у вибраного); вибір → `setPreferredGroup` + `setPinnedGroup` + `setFavoriteChoice`), «Серії» з плашками `_episodeGrid` у `below` (6 у ряд, два ряди навколо наступної, «Показати всі N ›» / «Згорнути»; тап → `play:<ключ>` і закриття; утримання/права кнопка — позначка «переглянуто»), «Якість», «Плеєр», «Джерела перегляду» (→ `SourcesDialog`), «Про команду», «Відкрити на сайті», «Оновити пошук», примітки джерел (`_offerNotes`). Пошук ще нічого не дав → тап по головній кнопці: джерела вимкнено — модалка `WatchDialogs.noSources`, інакше підпис під кнопкою. Ліцензовано → картка «Ліцензовано в Україні» → «Все одно дивитись» → `WatchDialogs.confirmLicensed` (`_ack` лише на цей показ). `bottom` — відступ під блоком (телефон 0: опис іде одразу). Стан — `HikkaRoute.memo['watch']` (`WatchLoad`). Діалоги — `widgets/hikka/hikka_watch_dialogs.dart`.
- Завантаження серій і офлайн (1.1.6): `DownloadManager` (`lib/services/downloads/download_manager.dart`, `DownloadManager.instance`, ChangeNotifier, `init()` з `main`) — черга (по одній серії; сегменти HLS у 4 потоки — `DownloadWorker`), індекс `<appBasePath>/downloads.json` (запис через `.tmp` + rename), файли в `root` (Android — `files/MikiMiki/downloads`, Windows — `%USERPROFILE%\Videos\Miki Miki`, інша тека — `DownloadPrefs.folder`; тека серії зберігається абсолютною: `<назва>/<Озвучення команда>/<Серія N>`, уже завантажене при зміні теки лишається на місці). Серія — `DownloadItem` (id `джерело|адреса серії`; позиція й «переглянуто» за тим самим `animeKey#epKey`), озвучка — знімок `DownloadGroup` (усі серії: з нього `launch()` будує `RemoteLaunch` без мережі, `offlineStart()` — з якої завантаженої серії почати). Мережа — `NetworkStatus` (`lib/services/network_status.dart`): Android каже сам (`ConnectivityManager` у `MainActivity.kt` → подія `network` {online, metered, type}, метод `networkState`; `certain` — відомо від системи), на ПК — пошук імені після збою запиту й повтор кожні 20 с; `HikkaApi` повідомляє `reportSuccess` / `reportFailure` і без мережі (за системою) не робить повторів. Правила черги: без інтернету чи на мобільному з «Лише через Wi-Fi» (`DownloadPrefs.wifiOnly`, типово так) — чекає (`waitReason`) і продовжує сам, з місця зупинки; мережевий збій — повтор із наростаючою паузою (`retryBase`), повернення мережі — одразу; менше 300 МБ вільно (`storageInfo`, StatFs) чи ENOSPC — «Замало місця»; посилання протухло (401/403/404/410) — нове від сайту, готові сегменти лишаються. Відтворення: `PlayerStateController.remote` має `DownloadAwareResolver` (`download_resolver.dart`) — завантажена серія грає з пристрою (плеєр «Пристрій»: локальний `index.m3u8` або `video.*`, субтитри й звук поруч; ключі AES-128 — `key_N.bin`, ffmpeg відкриває їх лише з `allowed_extensions=ALL`, який media_kit ставить у `demuxer-lavf-o` сам), решта — із сайту, а без мережі (за системою) — одразу зрозуміла помилка. «Розумні» завантаження: `RemoteDriver.onWatched` (лише автоматична позначка) → `DownloadManager.onWatched`: наступна серія (`autoNext`), переглянута — у `trash`, видаляється, коли вмикається інша (`markPlaying`, `deleteWatched`). Фон на Android — `DownloadService.kt` (foreground `dataSync`, сповіщення з прогресом і «Пауза» → `downloadsAction`, wake lock; `SystemControls.downloadService`; зупиняється разом з активністю). Позначки Hikka без мережі — розділ `hikka_pending` у `HikkaMyList` → `flushPending()` (на старті й коли мережа повертається). `WatchService.start` без мережі чи коли сайт не відповідає підставляє завантажені озвучки (`WatchService.downloadedOffer`); `HikkaWatchSection._target` і `QuickPlay.resume` («Продовжити перегляд») без мережі починають з найближчої завантаженої серії. Інтерфейс: «Завантажити серії» в панелі «Перегляд» (`DownloadPicker`), позначки на плашках серій (`DownloadPlateMark`) і в плеєрі (`RemotePanelBody`), сторінки `HikkaRouteKind.downloads` / `downloadShelf` (`DownloadsPage`, `DownloadShelfPage`; `HikkaNav.openDownloads` / `openDownloadShelf`; посилання `miki://open/downloads` з дотику по сповіщенню), полиця «Завантажене» на «Головній» (`DownloadsHomeShelf`; без мережі — першою), `OfflineStrip` над навігацією (`HomeHub`), рядок «Завантаження» в «Профілі» (`downloadsSummary`). Тести: `test/downloads_test.dart` (HLS, воркер, менеджер, резолвер, мережа), `test/downloads_ui_test.dart`; прев'ю — `PREVIEW=1 flutter test --update-goldens test/title_preview_test.dart --plain-name 'завантаження'` → `test/preview/downloads_*.png`.
- Пропуск опенінґу без таймкодів сайту (1.1.6, `lib/services/skips/`): `SkipService` (`SkipService.instance`; `RemoteDriver(skips:)` з `PlayerStateController`) дає плеєру план `current` (`SkipPlan`: таймкоди, `shift`, `source`, `opBase`) для серії, яку `RemoteDriver.onDuration` передає в `attach(SkipRequest)`; `_onPlan` перебудовує розділи (`chapters`, а в контролері — `currentChapters`), `episodeSeen` бере ті самі таймкоди. Порядок: таймкоди сайту (Moon) як є — і порівнянням з AniSkip вони вчать зсув озвучки (`_learnFromSite`); почуте в цій серії (опенінґ, заставка команди); AniSkip (`aniskip.dart`: `api.aniskip.com/v2/skip-times/{malId}/{ep}`, MAL id — з Hikka; `candidates` = найдовіреніше + найближче за довжиною; кеш `<appBasePath>/aniskip_cache.json`, тиждень, старе служить без мережі), а де в AniSkip для опенінґу / ендінґу / рекапу нічого не підходить — Anime Skip (`anime_skip.dart`; `withFallback` у `skip_align.dart`: друга база заповнює прогалини, а не розмиває точні таймкоди першої; у плані `source` — `basesOf`: «AniSkip», «Anime Skip» чи «AniSkip і Anime Skip»), зсунуте на відомий зсув (`SkipProfiles`, розділ `skip_profiles`: спостереження `site` / `audio`, ручне `user` над усім, заставка, почуті серії; підказка команди `teamHint` лише впорядковує версії). Номер для AniSkip (і для пісень) — лише цілий номер без сезону, коли номери озвучки — це номери Hikka (`RemoteDriver._numberOf` за `EpisodeCheck.numbersHold`, а не `syncSafe`: пропуск у нумерації не заважає; повертає й причину — `onDuration` пише її в журнал). Невідомий зсув → безпечні таймкоди (`alignSkips`: версія AniSkip годиться, коли наше відео довше чи коротше до 75 с — `maxInsert` / `maxCut`; кнопка лише там, де опенінґ є за будь-якого зсуву, що дозволяють довжини, і за кожної версії AniSkip; `TimeStamp.exact = false` → `VideoChapter.autoSkip = false`, автопропуску немає). Аналіз звуку (`audio_probe.dart` — прихований media_kit `Player` з `ao=pcm` пише 8 кГц моно; `audio_print.dart` — відбиток Haitsma–Kalker, крок 16 мс, порівняння з кроком 64 мс, `commonRuns` → `listenRuns`): перші 240 с цієї й сусідньої серії, лише Wi-Fi або завантажені файли, перемикач «Шукати опенінґ за звуком» (`StorageService.getListenForSkips`); відбитки — `<appBasePath>/skip_prints/*.bin` (до 200). Завершене завантаження (`DownloadManager.onDone` у `main`) → `SkipService.onDownloaded`: AniSkip про запас для офлайну й аналіз разом з іншою завантаженою серією озвучки. Меню «Розділи»: «Зсув таймкодів» (±0,5 с, для всіх серій озвучки), «Опенінґ почався тут» (`openingAt`), примітка `SettingsDrawer.skipNote`. Кнопка «Пропустити заставку» — розділ «Заставка» (`SkipButton.accusative`). Журнал (тег «пропуск»): `refresh` пише одним рядком озвучку, серію й довжину відео, що дали AniSkip і Anime Skip (`describeTimes`: кожна версія з різницею довжин, «інша версія» — за межами ±75 с) і що з того вийшло (`describePlan`) або «пропусків нема»; той самий план удруге не пишеться. `attach` пише й про аналіз звуку: коли слухатиме або чому ні (`_whyNotListen`: вимкнено, лише Wi-Fi — з типом мережі, немає інтернету). Тести: `test/skips_test.dart`, `test/skips_service_test.dart`, `test/anime_skip_test.dart` (справжні відповіді AniList і Anime Skip для «Саги про Вінланд» 2 у `test/data/skips/`); прев'ю — `PREVIEW=1 flutter test --update-goldens test/skips_preview_test.dart` → `test/preview/skips_p*.png`.
- Пісні опенінґу й ендінґу (1.1.6, `lib/services/songs/`): `SongService` (`SongService.instance`; `RemoteDriver(songs:)` з `PlayerStateController`) — `RemoteDriver.onDuration` передає серію (`attach(animeKey, epKey, number)`, номер — `_numberOf`), `current` (`EpisodeSongs`: `op` / `ed` — `ThemeSong`, `art` — `SongArt`); зміни `current` будять драйвер (`_changed`), тож меню перебудовується. Дані — з трьох джерел (`combineSongs`): AnimeThemes — лише GraphQL (`https://graphql.animethemes.moe/`, POST `animeThemesQuery(mal)` → `findAnimeByExternalSite(site: MAL, id: [mal])`; REST `api.animethemes.moe` за перевіркою Cloudflare віддає застосунку 503); MyAnimeList — через Tenrai (`tenraiThemes(mal)` = `https://api.tenrai.org/v1/anime/{mal}/themes`, формат Jikan v4 `{data: {openings, endings}}` рядками «1: "Haruka Mirai (ハルカミライ)" by Kankaku Piero (感覚ピエロ) (eps 1-13)» → `songsOfMal` / `songOfMalLine`: «R1:» / «S1:» — повтори й спецвипуски, не свої; «(CV: …)» прибирається; оригінальні імена — у `ThemeSong.nativeArtists`; «eps 158-???» — відкритий кінець; без ключа, 4 запити/с і 120/хв з IP; Jikan більше не існує); теми з `group` («Yorinuki Gintama-san» на сторінці Gintama, «Naruto Shounen-hen», «TV Version») — не свої, беруться лише без групи (`songsOfAnimeThemes`); серії теми — об'єднання діапазонів її версій, версія без серій нічого не додає (Naruto «GO!!!»: v1 78–103, v2 без серій). Основа — пісні AnimeThemes, коли він знає тайтл (серії за версіями точніші), інакше MyAnimeList, інакше список Hikka (`HikkaAnime.ost` → `songsOfHikka`: «Yuusha (勇者)» → `splitNative`, `HikkaOst.spotify`; без серій). `enrichSongs`: MyAnimeList (`full`) додає до пісень AnimeThemes виконавців і серії, яких там немає (Black Clover «Haruka Mirai» — Kankaku Piero), оригінальні назви й імена; Hikka — оригінальні назви й Spotify, але не виконавців (обрізає їх до першого слова: «Tommy» замість Tommy heavenly⁶). Пара (`_twinIn`) шукається за назвою, а коли тезок кілька — ще й за виконавцем (у Black Clover «four» FAKY і «four» Megumi Han). Пісня серії — `pickSong`: з названих серій найвужча (`parseEpisodes`, `ThemeSong.span`), без серій — лише коли така пісня одна. `attach` питає AnimeThemes і Tenrai паралельно (кеш `themes:<mal>` і `tenrai:<mal>`) і пише в журнал (тег «пісні») знайдене або «не знайдено» з тим, що дало кожне джерело (`_sources`). Обкладинка: точна зі сторінки пісні (iTunes lookup за `appleTrackId` у магазині посилання — `appleCountry`; Spotify oEmbed — посилання з Hikka є майже завжди), інакше пошук Apple Music (country=JP) / Deezer зі строгим збігом виконавця (зокрема оригінального імені) й назви (`matchScore`; живі, кавери, інструментальні — ні; без виконавця не шукається); шукається `ThemeSong.query` — оригінальні ім'я й назва, коли відомі. Кеш `<appBasePath>/theme_songs.json` (пісні тайтлу — 14 днів, порожньо — 2, обкладинки й посилання — 60; старе служить без мережі). Інтерфейс: `SongCard` (`lib/widgets/song_card.dart`: верхній лівий кут на радіальному затемненні `_CornerEllipse`, що пропускає дотики; під верхньою панеллю, коли вона видна; перші 8 с розділу опенінґу / ендінґу — `ChapterMath.songStateAt` / `songKindOf` — і з панеллю; ховається під меню й панелями; дотик → `PlayerStateController.openSongDrawer` → сторінка меню `song-op` / `song-ed` у `SettingsDrawer`), `SongCover` (обкладинка через `HikkaImage` + `EqualizerPainter`, рухається, лише коли грає), `MusicAppBadge` (значок сервісу — favicon з його сайту через `HikkaImage`, логотипів у застосунку немає; до завантаження — перша літера). Посилання: `SongService.linksFor` — пряме (AnimeThemes, Spotify з Hikka, Apple з пошуку) або `searchLink`; відкриває `HikkaNav.urlOpener`. Перемикач «Пісня опенінґу й ендінґу» (`StorageService.getShowThemeSongs`). Тести: `test/songs_test.dart` (справжні відповіді AnimeThemes GraphQL для Frieren, Gintama, Black Clover, Naruto, «Монологу травниці» 2, Tenrai для Frieren, Gintama, Black Clover, Naruto, списки пісень Hikka для Gintama і Black Clover, iTunes, Deezer, Spotify у `test/data/songs/`), `test/songs_ui_test.dart`; прев'ю — `PREVIEW=1 flutter test --update-goldens test/songs_preview_test.dart` → `test/preview/songs_p*.png`.
- Назви й кадри серій (1.1.6, `lib/services/episode_guide.dart`): `EpisodeGuideService` (`EpisodeGuideService.instance`) — `load(animeKey, from, to)` / `peek` (зібране за останні 30 хв) → `EpisodeGuide` (`GuideEpisode` за номером MyAnimeList: `uk`, `en`, `ja`, `aired`, `still` / `stillUrl` — `image.tmdb.org/t/p/w300`, `runtime`, `filler`, `recap`). MAL id — `HikkaApi.malIdOf`. Англійські назви, дати й позначки — MyAnimeList через Tenrai (`api.tenrai.org/v1/anime/{mal}/episodes`, сторінки по 100 — `malEpisodesOf`); українські назви й кадри — TheMovieDB (`language=uk-UA`, ключ — `BackendClient.effectiveTmdbKey`, v4 заголовком, v3 параметром; `isUkrainianTitle`: кирилиця, без суто російських літер, не заглушка «Епізод 5»): шоу шукається за назвами тайтлу (`TmdbBackdrops.searchQueries`, `tmdbShowsOf` — японські, інакше анімаційні) і береться перше, де за датою виходу збіглася бодай половина серій (`matchByDate`: ±1 день, кілька серій за день — по черзі; сезони — `seasonsBetween`); коли Tenrai недоступний — назви з Anime Skip (`AnimeSkip.names`, `animeSkipNames`). Після TMDB — MoonAnime через бекенд (`BackendClient.guide`, `moonEpisodesOf` / `MoonEpisode`: `t` назва, `d` секунди, `a` опис, `i` шлях зменшеного кадру на Hosting, `f` / `r`; у кеші `moon:<mal>` — доба): українська назва — TMDB, потім MoonAnime; кадр — TMDB, потім MoonAnime (`GuideEpisode.still` — повна адреса); `seconds` і `about` — лише з MoonAnime (у рядку «23:40» замість «24 хв», опис — у підказці на ПК). Кеш `<appBasePath>/episode_guide.json`: сторінка MAL — 14 днів (остання сторінка онґоїнґу — день), шоу TMDB — 60 днів (не знайдено — 3), сезони — 3, серії сезону — 2 / 7 / 30 днів (свіжий / без перекладів / решта); старе служить без мережі. Журнал — тег «назви». Панель «Перегляд» (`RemotePanelBody`) бере номери з `RemoteDriver.malNumbers` (те саме правило, що для AniSkip), назву — `uk`, інакше назву з сайту (`siteEpisodeTitle`: «Серія 13 - Нацу проти Юкі»), інакше `en`; є кадри — рядки з кадрами, нема — рядки з номером, нема назв — плашки; поки назви йдуть — сірі рядки-заготовки; утримання рядка — деталі серії з описом (картка чи сторінка панелі). Тести: `test/episode_guide_test.dart` (справжні відповіді Tenrai у `test/data/guide/`; відповіді TMDB — у його формі, вигадані), `remote_ui_test.dart` (група «список із назвами», `FakeGuide`). Живий замір покриття (TMDB проти MoonAnime на популярних і нещодавно оновлених тайтлах MoonAnime): `test/episode_guide_live_test.dart` — лише з ключами в змінних середовища (`MOON_API_KEY`, `TMDB_KEY`), без них пропускається.
- Прокрутка й карусель (v34): `main.dart` → `_AppScrollBehavior` (на краю — `StretchingOverscrollIndicator`, як в Android 12+, а не світіння); `AppScrollbar`/усі `RawScrollbar` — `thumbVisibility: false` + згасання за ~0,9 с (на ПК `interactive`); `HikkaBannerCarousel` на вузьких екранах безкінечна (`_loops` віртуальних кіл, `_loopMode`, перецентрування в `_tick`), на широких — зі стрибком на початок; `AppDropdownOption` має `leading/title/subtitle/subtitleIcon` (розширений вигляд пункту), `AppAccentButton.solid` — головна дія сторінки.
- Налаштування джерел перегляду — `SourcesDialog` (`widgets/hikka/sources_dialog.dart`): найбільша якість, плеєр за замовчуванням (Авто / Moon / Ashdi), поріг «Серія вважається переглянутою після» і «Зараховувати за ендінґом», пріоритет команд озвучення (`StorageService.get/saveWatchTeamPriority`; список команд — випадний `AppSearchDropdown` у режимі `multiSelected` із пошуком і `onAddCustom`; команди беруться з `MikaiSource.allTeams()` + `StorageService.getKnownTeams()`) і перемикач «Спершу повні озвучення» (`getPreferFullDub`). Сайтів і ключів тут немає: перемикач сайтів зник (`SourceRegistry.isEnabled` ігнорує вимкнення єдиного джерела), ключі API та власний клієнт Hikka — у налаштуваннях, вкладка «Розробник». Відкривається з блоку «Дивитись» (кнопка «Джерела») і з налаштувань каталогу (розділ «Перегляд»).
- Ще не зроблено для перегляду: обхід Cloudflare для UAKino (куки з прихованого WebView, як у Mihon / Aniyomi; у вікні «Джерела» вже є попередження), «репозиторії» (спершу домовитись із користувачем). Синхронізація «переглянуто» з Hikka вже є (правило «Акаунт Hikka»).
- Субтитри й доріжки: libass на Android не має жодного системного шрифту — без власного він не малює субтитри взагалі, тому `assets/fonts/subtitle.ttf` (Liberation Sans, SIL OFL; текст ліцензії поруч) передається в `PlayerConfiguration(libassAndroidFont, libassAndroidFontName)` (`MpvConfig.androidSubtitleFontAsset` / `androidSubtitleFontName`); `MpvConfig.applySubtitleStyles` на Android НЕ виставляє `sub-font` і `sub-fonts-dir` (вони б перебили вбудований шрифт). Автовибір доріжок за мовою з налаштувань: `PlayerStateController._applyTrackDefaults` (на кожен новий перелік доріжок) → `TrackDefaults.plan` (`lib/services/track_defaults.dart`; мова — `LangMatch`, `lib/services/lang_match.dart`: мітка доріжки, а без неї її назва): перша мова зі списку «Пріоритет мов субтитрів / аудіодоріжок», повні субтитри перед «Signs & Songs», текстові перед PGS; «Автоматично завантажувати субтитри» вимкнено → субтитри вимикаються; ручний вибір (`setSubtitleTrack` / `setAudioTrack`) зупиняє автовибір до наступного файлу; при автовмиканні показується OSD «Субтитри». Зовнішні субтитри: перетягнути `.srt` / `.ass` / `.vtt` … на вікно (`handleDroppedFiles`) або «Додати файл субтитрів…» у меню субтитрів (`pickSubtitleFile`). Серії із сайтів автовибір контролера пропускає: їхні субтитри вмикає драйвер (`LangMatch.pickByLabel`). Змінилося: аудіодоріжка тепер вибирається за «Пріоритетом мов аудіодоріжок» (типово ja, uk, en), раніше це налаштування не діяло.
- Гарячі клавіші: єдине джерело — `ShortcutCatalog.all` (`lib/services/shortcut_catalog.dart`); з нього працюють і обробник (`KeyboardShortcuts`), і довідка (`ShortcutsView`/`ShortcutsDialog`). Нова комбінація = запис у каталозі + замикання з тим самим id у `PlayerActions` (`_buildTable`). Схеми `KeyScheme.standard` / `KeyScheme.mpv` (`PlayerStateController.keyScheme`, зберігається в `StorageService`); комбінації, що різняться в схемах, мають `KeyScope`.
- Anime4K: шейдери (bloc97/Anime4K v4.0.1, MIT) лежать в `assets/shaders/anime4k/` і розпаковуються в `%APPDATA%/MikiMiki/shaders/anime4k`; ланцюжки й режими — `Anime4kService`, стан/застосування — `Anime4kController` (`PlayerStateController.anime4k`). UI: вкладка налаштувань, сторінка в випадному меню, кнопка в `BottomDock`. Нові шейдери додавати в assets (папка вже в `pubspec.yaml`).
- OSD поверх відео: `PlayerStateController.showOsd(...)` → `osd` (ValueNotifier<OsdMessage?>) → `OsdToast` у `player_screen.dart`.
- Кнопки клавіатури в UI: `AppKeyCap` / `AppKeyCombo`; пошук — `AppSearchField`.
- Flutter тут не запускається ззовні: користувач сам робить `flutter analyze`/run.
- Стек: media_kit 1.2.6, media_kit_video 2.0.1, window_manager, file_picker, desktop_drop, html (розбір сторінок джерел).

## Файли

### `lib/constants/app_constants.dart` (108 р.)
Не-тематичні константи (швидкості, розміри тощо). Кольори/теми — в uiTheme. Набір декодерів `hwdecOptions` залежить від платформи.

- **AppConstants** (р.4)

### `lib/constants/app_identity.dart` (68 р.)
Назва й технічні ідентифікатори застосунку в одному місці (див. правило «Назва застосунку»): `AppIdentity.name` / `shortName` / `packageName` / `dataDirName` / `legacyDataDirName` / `tagline` / `version`, `userAgent(purpose)` (`MikiMiki/1.0.3 (Flutter; <призначення>)`). Версію міняти в двох місцях разом: `AppIdentity.version` і `version:` у `pubspec.yaml` (зараз `1.0.3+4`; `flutter.versionName/versionCode` в `android/local.properties` підтягуються самі при збірці), `migrateLegacyData(legacy, current)` — перенос теки даних зі старої назви при першому запуску (перейменування, а якщо не вийшло — копіювання; без винятків).

- **AppIdentity** (р.10)
  - `userAgent()` р.35
  - `migrateLegacyData()` р.40

### `lib/main.dart` (135 р.)
Вхід: ініціалізація media_kit, StorageService (і window_manager — лише на десктопі), uiTheme, ThumbnailService. Десктоп: вікно 1280×720. Телефон: `SystemControls.init()`, вільна орієнтація (`setPreferredOrientations([])`), edge-to-edge, масштаб тексту обмежено 0.9–1.25. Запуск: `AppLog.instance.init(<appBasePath>/logs, detailed)` → `AppDiagnostics.instance.install()`; `MaterialApp.navigatorObservers: [AppNavObserver()]`. Назва вікна й застосунку — `AppIdentity.name`.

- `main()` (р.32)

### `lib/models/hikka_community_models.dart` (283 р.)
Колекції й статті спільноти Hikka (`part of 'hikka_models.dart'`, чиста Dart-логіка): `HikkaAuthor` (автор), `HikkaCollectionEntry` (запис колекції: `anime`, `comment` автора, `label` розділу, `order`), `HikkaCollection` (`reference`, `title`, `description` — Markdown, `author`, `entries` — скільки записів усього, `voteScore`, `commentsCount`, `tags`, `labelsOrder`, `spoiler`, `nsfw`, `items` — записи; у списку лише перші), `SlateNode` (вузол документа редактора Slate: `type`, `text`, `bold` / `italic` / `underline` / `strike` / `code`, `url`, `children`; `isText`, `plainText`, `firstImage`, `parseList`; `fromJson` стійкий до сміття) і `HikkaArticle` (`slug`, `title`, `author`, `category`, `views`, `voteScore`, `commentsCount`, `tags`, `preview` — початок тексту, `document` — весь текст у Slate, `content` — тайтл, про який стаття, або `null`). Теги приходять рядками або `{name, content_count}` — `_tags`.

- **HikkaAuthor** (р.15)
- **HikkaCollectionEntry** (р.30)
- **HikkaCollection** (р.41)
  - `visibleItems()` р.113
- **SlateNode** (р.134)
  - `parseList()` р.177
- **HikkaArticle** (р.198)
  - `snippet()` р.260

### `lib/models/hikka_models.dart` (1162 р.)
Моделі API Hikka (чиста Dart-логіка): `HikkaAnime` (назви за мовою `title(lang)`, `isAdult`, `nextEpisode(now)`, `seasonLabel`, `episodesLabel`, студії, жанри, посилання, відео, OST, розклад, статистика), `HikkaPage<T>` (`{pagination, list}`), `HikkaCharacter` / `HikkaCharacterRole` / `HikkaCharacterAnime`, `HikkaCharacterVoice` (коди мов → українські назви, `groupByLanguage`, `actors` — актори озвучення по одному: людина, мова, скільки аніме), `HikkaStaff`, `HikkaScheduleEntry`, `HikkaRelation` / `HikkaFranchiseData`, `HikkaSearchFilters` (умови пошуку → тіло POST /anime, `copyWith`, `activeCount`) + `HikkaSortOption`, `HikkaTitleLang`; `HikkaText` — українські підписи значень API (статус, тип, сезон, вікова категорія, числа з нерозривним пробілом, `plural`, дні тижня). `HikkaText.compact(n)` — лічильники для карток («1,3 тис.», «2,4 млн»). Колекції й статті спільноти лежать в окремому файлі `hikka_community_models.dart` (`part`), але користуються тими самими допоміжними функціями розбору.

- **HikkaTitleLang** (р.32)
  - `fromName()` р.40
- **HikkaText** (р.45)
  - `mediaType()` р.132
  - `status()` р.133
  - `season()` р.134
  - `rating()` р.135
  - `source()` р.136
  - `seasonOfMonth()` р.139
  - `currentSeason()` р.148
  - `nextSeason()` р.154
  - `plural()` р.161
  - `dayMonth()` р.171
  - `count()` р.177
  - `compact()` р.188
  - `hhmm()` р.203
  - `dayName()` р.206
  - `airingLabel()` р.216
  - `dayHeader()` р.219
- **HikkaGenre** (р.228)
- **HikkaCompany** (р.247)
- **HikkaAnimeCompany** (р.259)
- **HikkaLink** (р.273)
- **HikkaVideo** (р.286)
- **HikkaOst** (р.297)
- **HikkaEpisodeSlot** (р.320)
- **HikkaAnimeStats** (р.332)
- **HikkaAnime** (р.363)
  - `title()` р.508
  - `secondaryTitle()` р.521
  - `otherTitles()` р.532
  - `nextEpisode()` р.567
- **HikkaPage** (р.585)
  - `parse()` р.595
- **HikkaCharacter** (р.610)
- **HikkaCharacterRole** (р.665)
- **HikkaCharacterAnime** (р.676)
- **HikkaPerson** (р.686)
- **HikkaPersonAnime** (р.741)
- **HikkaPersonCharacter** (р.756)
- **HikkaCharacterVoice** (р.767)
  - `actors()` р.854
- **HikkaRole** (р.906)
- **HikkaStaff** (р.925)
- **HikkaScheduleEntry** (р.943)
- **HikkaRelation** (р.963)
- **HikkaFranchiseData** (р.989)
- **HikkaSortOption** (р.1006)
- **HikkaSearchFilters** (р.1019)
  - `copyWith()` р.1078
  - `toBody()` р.1134

### `lib/models/hikka_user_models.dart` (172 р.)
Моделі акаунта Hikka: `HikkaWatchStatus` (watching «Дивлюсь», planned «У планах», completed «Переглянуто», onHold «Відкладено», dropped «Кинуто»; `api` — значення API, `label` — підпис, `fromApi`), `HikkaToken` (`secret`, `created`, `expiration`), `HikkaMe` (профіль без пошти; `toJson` для сховища), `HikkaWatchEntry` (`status`, `episodes`, `score`, `note`, `rewatches`, дати, `anime`; `copyWith`, `toArgs()` — повний запис для `PUT /watch/{slug}` без втрати полів), `HikkaWatchStats` (лічильники за статусами, `of(status)`, `total`).

- **HikkaWatchStatus** (р.7)
- **HikkaToken** (р.28)
- **HikkaMe** (р.43)
- **HikkaWatchEntry** (р.73)
- **HikkaWatchStats** (р.146)

### `lib/models/media_models.dart` (82 р.)
Моделі даних (файли, історія, глави). `VolumeState` — гучність + mute одним значенням (для `PlayerStateController.volumeState`).

- **VideoChapter** (р.3)
- **VolumeState** (р.21)
- **CachedSubtitleTrack** (р.34)
- **CachedAudioTrack** (р.44)
- **PlaybackStats** (р.54)

### `lib/models/source_models.dart` (256 р.)
Моделі джерел перегляду (Dart-версія `animesource.model` з Aniyomi; чиста логіка): `SAnime` (сторінка сайту: назва, оригінальна назва, постер, студія, жанри, `SAnimeStatus`, рік, серій вийшло / всього; `mergedWith`, `toJson` / `fromJson`), `SAnimePage` (сторінка видачі + `hasNextPage`), `SEpisode` (адреса, назва, номер, сезон, озвучка `voice`, службові `data`), `Track` (зовнішні субтитри / звук), `TimeStamp` + `ChapterType` (опенінґ / ендінґ / рекап…), `Video` (посилання, підпис якості, висота, заголовки, доріжки, таймкоди, `preferred`), `Hoster` (плеєр сайту з відкладеним завантаженням відео); `pickVideo(videos, maxHeight:)` — вибір якості (0 — найвища).

- **SAnimeStatus** (р.5)
- **SAnime** (р.8)
  - `mergedWith()` р.46
  - `toJson()` р.62
- **SAnimePage** (р.95)
- **SEpisode** (р.105)
  - `toJson()` р.125
- **Track** (р.150)
- **ChapterType** (р.157)
- **TimeStamp** (р.160)
- **Video** (р.174)
  - `copyWith()` р.210
- **Hoster** (р.229)
- `pickVideo()` (р.243)

### `lib/screens/player_screen.dart` (673 р.)
Кореневий екран: збирає HomeHub / VideoViewport + оверлеї + SidePanelDrawer, слухає PlayerStateController і uiTheme. Утримання на відео — `_holdSpeedStart` / `_holdSpeedEnd` (налаштування «Прискорення утримуванням»: вмикач і швидкість `StorageService.getHoldToSpeedRate`, підпис плашки — `speedLabel`); «Усі налаштування» з меню плеєра — `_openAppSettings` (`AppSettingsDialog.show(initialTab: tabPlayback)`). Підключає `KeyboardShortcuts`, `OsdToast` і довідку клавіш (`state.onShowShortcuts` → `ShortcutsDialog`). Статистика (`StatsOverlay`) слухає лише `state.liveStats`, гучність у доці — `state.volumeState`. Телефон: `_mobilePlayer` (див. правило про мобільний інтерфейс), `_wrapMobile` (`PopScope` «Назад», кольори системних панелей), спостерігач життєвого циклу. `_wrapMobile`: «Назад» спершу віддається `HomeHub.backHandler` (сторінки каталогу), далі `handleBack()`. Серії із сайтів: `WatchLauncher.attach(state.openRemote)` в `initState` (відписка в `dispose`); `RemoteStatusOverlay(driver: state.remote)` поверх відео на десктопі й телефоні (`onOpenPanel` → `openSidePanel(episodes)`, `onClose` → `returnToHome`); `state.remote` передається в `SidePanelDrawer`; «попередня / наступна» (`state.playPrevious` / `playNext`) — у `ControlsOverlay` і `MobileControls`; назва й сірий рядок у керуванні — `state.chromeTitle` / `chromeSubtitle()` (на ПК з якістю), `hasQueue` на телефоні для серій — `hasNext || hasPrevious`. Перетягування на вікно: `onDragDone` → `state.handleDroppedFiles` (відео відкривається, самі субтитри додаються до відкритого відео); у шухляді налаштувань `onAddSubtitleFile: state.pickSubtitleFile`. `HomeHub(onOpenSettings: ({int? tab}) => AppSettingsDialog.show(…, initialTab: tab ?? 0))`. `SongCard` стоїть поруч із `SkipButton` в обох розкладках (`hidden` — відкрите меню чи панель; `onOpen` → `openSongDrawer`).

- **PlayerScreen** (р.42)
- **_PlayerScreenState** (р.49)
  - `didChangeAppLifecycleState()` р.86

### `lib/services/anime4k_controller.dart` (253 р.)
Стан і застосування Anime4K (ChangeNotifier; `setSuspended(bool)` — вимикає шейдери в міні-плеєрі й PiP): режим / якість / поріг пропуску за роздільністю, черга команд до mpv, OSD-відгук, повторне застосування після відкриття файлу, виявлення помилок шейдерів у логах рушія. Живе в `PlayerStateController.anime4k`. Результат застосування / вимкнення / помилки шейдера пишеться в `AppLog` (тег `anime4k`).

- **Anime4kController** (р.13)
  - `load()` р.58
  - `syncToEngine()` р.80
  - `setMode()` р.127
  - `enable()` р.137
  - `disable()` р.147
  - `toggle()` р.155
  - `setQuality()` р.157
  - `toggleQuality()` р.171
  - `configure()` р.175
  - `onVideoHeight()` р.198
  - `onFileChanged()` р.204
  - `onEngineLog()` р.219

### `lib/services/anime4k_service.dart` (219 р.)
Нативний Anime4K: режими A / B / C / A+A / B+B / C+A × Fast / HQ → ланцюжки GLSL-шейдерів (як в офіційному input.conf), розпаковка assets на диск і `change-list glsl-shaders` (clr — вимкнути). Комбінації клавіш режимів: Ctrl+1…6, Ctrl+0 — вимкнути, Ctrl+8 / Ctrl+9 — додаткові. Шейдери розпаковуються в `%APPDATA%/MikiMiki/shaders/anime4k`.

- **MpvCommand** (р.8)
- **Anime4kQuality** (р.11)
- **Anime4kMode** (р.26)
- **Anime4kService** (р.108)
  - `chain()` р.124
  - `describe()` р.150
  - `ensureExtracted()` р.157
  - `apply()` р.178
  - `clear()` р.207
  - `looksLikeShaderFailure()` р.214

### `lib/services/app_diagnostics.dart` (272 р.)
Глобальна діагностика: `AppDiagnostics.instance.install()` (помилки Flutter й асинхронні, життєвий цикл, зміни розмірів, повільні кадри >40 мс у вікні 5 с, памʼять / стан пристрою раз на 15 с), `logEnvironment()` (шапка звіту; наприкінці — `ExitReports.logRecent()`), `describeAudioRoute()`, `AppDiagnostics.build` (позначка збірки); `AppNavObserver` — відкриття / закриття діалогів і панелей.

- **AppDiagnostics** (р.22)
  - `install()` р.46
  - `logEnvironment()` р.75
  - `describeAudioRoute()` р.130
  - `didChangeAppLifecycleState()` р.144
  - `didHaveMemoryPressure()` р.159
  - `didChangeMetrics()` р.165
- **AppNavObserver** (р.245)
  - `didPush()` р.247
  - `didPop()` р.252
  - `didRemove()` р.257
  - `didReplace()` р.262

### `lib/services/app_log.dart` (545 р.)
Єдиний журнал: `AppLog.i/w/e/d(тег, текст)`, `AppLog.on`, `AppLog.instance` (`init(directory, detailed)`, `setDetailed`, `flushNow`, `files()`, `totalBytes()`, `clear()`, `sessionText()`, `previousSessionText()`, `buildReport(extra:)`, `environment`), `LogEntry` / `LogLevel`; кільце в памʼяті + файл сесії з ротацією, `AppLog.sanitize` (токени, ключі, паролі, cookie), згортання однакових рядків, `AppLog.stamp`, `AppLog.bytesLabel`. Не кидає винятків. Файли журналу — `miki_miki_<дата>_<час>.log` (`filePrefix`); під старою назвою (`legacyFilePrefix` = `my_player_`) теж читаються й ротуються (`_orderKey` сортує за часом сесії, а не за буквами).

- **LogLevel** (р.19)
- **LogEntry** (р.29)
- **AppLog** (р.47)
  - `d()` р.94
  - `i()` р.95
  - `w()` р.96
  - `e()` р.99
  - `init()` р.160
  - `setDetailed()` р.168
  - `log()` р.187
  - `flushNow()` р.313
  - `files()` р.353
  - `totalBytes()` р.390
  - `clear()` р.401
  - `sessionText()` р.447
  - `previousSessionText()` р.461
  - `buildReport()` р.472
  - `shutdown()` р.503
  - `sanitize()` р.529
  - `stamp()` р.532
  - `bytesLabel()` р.540

### `lib/services/banner_art.dart` (270 р.)
Широкі зображення для банерів «Головної» (див. правило «Банери»): `BannerArtwork` (`url`, `color`; `none`, `hasImage`, JSON), `JsonFetcher` / `ioJsonFetch` (запит JSON на `dart:io`; у тестах підміняється), `AniListBanners.load(malIds)` / `parse` (GraphQL `graphql.anilist.co`, ≤50 id за запит), `TmdbBackdrops.backdropFor(anime)` / `pickBackdrop` (запасний пошук за назвами й роком; без ключа не питає), `BannerArt.instance.load(anime)` — кеш із TTL (`foundTtl` 14 днів, `missingTtl` 2 дні, до 400 записів), запасний пошук лише для тайтлів без банера в AniList і лише з ключем, збої не кидають винятків.

- **BannerArtwork** (р.17)
- **JsonFetcher** (р.46)
- **AniListBanners** (р.73)
  - `load()` р.87
  - `parse()` р.99
- **TmdbBackdrops** (р.122)
  - `backdropFor()` р.136
  - `pickBackdrop()` р.161
- **BannerArt** (р.173)
  - `load()` р.223

### `lib/services/continue_watching.dart` (227 р.)
«Продовжити перегляд»: `ContinueWatching.recent({store, limit})` — тайтли Hikka (ключ `hikka:<slug>` у `WatchStore`) з останньою відкритою серією, найновіші першими; `load({store, api, limit, allowAdult})` → `ContinueItem` (`anime`, `episodeKey`, `at`, `episodeLabel` «Серія 3» / «Сезон 2 · серія 5», `episodeShort` «С2 · Е5»): запити до Hikka йдуть паралельно, збійні, 18+ (без дозволу) і завершені, повністю переглянуті тайтли пропускаються; `episodeCaption` / `episodeShort` — підписи за ключем серії.

- **ContinueItem** (р.17)
- **ContinueWatching** (р.51)
  - `episodeCaption()` р.58
  - `episodeShort()` р.66
  - `recent()` р.77
  - `load()` р.150

### `lib/services/downloads/hls_media.dart` (255 р.)
Медіаплейлисти HLS для завантажень (чиста логіка): `parseHlsMedia(text, base)` → `HlsMedia` (сегменти з тривалістю, номером, `BYTERANGE` з неявними зсувами, `HlsKey` AES-128 / `SAMPLE-AES`, `HlsMap` для fMP4, розриви, `ENDLIST`; `unsupportedEncryption`), `buildLocalPlaylist` (локальна копія: нумерація з 0, неявний IV виписано явно, `key_N.bin`, `init_N.mp4`), `hlsIv`, `segmentExtension`.

- **HlsKey** (р.6)
- **HlsMap** (р.24)
- **HlsSegment** (р.34)
- **HlsMedia** (р.52)
- `parseHlsMedia()` (р.124)
- `hlsIv()` (р.193)
- `buildLocalPlaylist()` (р.199)
- `segmentExtension()` (р.247)

### `lib/services/downloads/download_models.dart` (347 р.)
Що зберігається про завантаження: `DownloadState` (queued / running / paused / failed / done), `DownloadItem` (серія однієї озвучки: джерело, `SEpisode`, `epKey`, номер і кількість, висота; тека (абсолютна), файл, якість, плеєр, байти, частини, тривалість, субтитри / звук (`DownloadTrack`), таймкоди; `toJson` / `fromJson` — running після перезапуску стає queued), `DownloadShelf.of` (тайтл + озвучка, новіші першими), `formatBytes`.

- **DownloadState** (р.7)
- **DownloadItem** (р.19)
  - `idOf()` р.110
  - `copyWith()` р.129
  - `toJson()` р.182
  - `fromJson()` р.218
- **DownloadTrack** (р.277)
  - `toJson()` р.283
  - `fromJson()` р.285
- **DownloadShelf** (р.292)
  - `of()` р.316
- `formatBytes()` (р.339)

### `lib/services/downloads/download_worker.dart` (505 р.)
Завантаження однієї серії: `DownloadWorker.run()` — свіже посилання від сайту (`VideoResolver`; на Android посилання Moon розгортається з `HlsProxy.original`), HLS (майстер → варіант за висотою `pickVariant`, ключі, init-секції, сегменти в `parallel` потоків, `.part` + rename, докачка наявного, `index.m3u8`) або файл (докачка з `.part` діапазоном), субтитри й окремий звук, `episode.json`. Протухле посилання → нове (до 3 разів); мережеві збої → `DownloadFailure(network: true)` після повторів; немає місця → `noSpace`; `DownloadCancel` рве з'єднання. Мережа підміняється (`DownloadFetch`); справжня — `DownloadWorker.httpFetch`.

- **FetchResponse** (р.17)
- **ResolvedVideo** (р.30)
- **DownloadFailure** (р.40)
- **DownloadCancelled** (р.52)
- **_Expired** (р.57)
- **DownloadCancel** (р.63)
  - `cancel()` р.69
- **DownloadWorker** (р.83)
  - `run()` р.126
  - `pickVariant()` р.278
  - `httpFetch()` р.492

### `lib/services/downloads/download_manager.dart` (998 р.)
Черга, тека, індекс, правила мережі, розумні завантаження, запуск без мережі (правило «Завантаження серій і офлайн»). `DownloadPrefs` (wifiOnly, height, autoNext, deleteWatched, folder), `DownloadGroup` (знімок озвучки), `DownloadManager`: `init`, `enqueue`, `pause` / `resume` / `pauseAll` / `resumeAll`, `remove` / `removeMany` / `removeGroup` / `removeAll`, `onWatched`, `markPlaying`, `launch`, `offlineStart`, `localVideo`, `playable`, `byEpKey`, `groupsOf`, `shelves`, `pending` / `done` / `current`, `speed`, `waitReason`, `storageInfo`, `save`.

- **DownloadPrefs** (р.37)
  - `copyWith()` р.55
  - `toJson()` р.63
  - `fromJson()` р.71
- **DownloadGroup** (р.82)
  - `keyOf()` р.109
  - `toJson()` р.117
  - `fromJson()` р.130
- **_Job** (р.153)
- **DownloadManager** (р.164)
  - `Function()` р.168
  - `item()` р.295
  - `group()` р.312
  - `groupsOf()` р.315
  - `itemOf()` р.317
  - `byEpKey()` р.320
  - `playable()` р.326
  - `hasDone()` р.332
  - `storageInfo()` р.359
  - `init()` р.367
  - `debugReload()` р.422
  - `enqueue()` р.436
  - `pause()` р.534
  - `resume()` р.546
  - `pauseAll()` р.558
  - `resumeAll()` р.573
  - `remove()` р.590
  - `removeMany()` р.592
  - `removeGroup()` р.616
  - `removeAll()` р.619
  - `onWatched()` р.634
  - `markPlaying()` р.660
  - `launch()` р.678
  - `offlineStart()` р.701
  - `localVideo()` р.717
  - `save()` р.937

### `lib/services/downloads/download_resolver.dart` (68 р.)
`DownloadAwareResolver extends StreamResolver`: завантажена серія — з пристрою (`deviceHoster` «Пристрій»), вибраний вручну інший плеєр — із сайту (без мережі все одно з пристрою), без мережі й без копії — `SourceException` зі зрозумілим `note`.

- **DownloadAwareResolver** (р.13)
  - `resolve()` р.33

### `lib/services/exit_reports.dart` (366 р.)
Чому застосунок минулого разу закрився сам (Android 11+): `ExitReports.logRecent({exits})` при старті пише в журнал (тег «аварія», по разу — мітка `exits_seen` у розділі `diagnostics` `StorageService`) кожне ненормальне завершення (`ExitRecord.abnormal`: аварія Java / нативна, ANR, помилка запуску, надмір ресурсів; «сигнал», брак памʼяті, заморожування — лише якщо процес був видимий, `importance` ≤ 230; закриття людиною й оновлення — ні). `describe(record)`: «Запуск 21.11 о 12:23:27 (на екрані) завершився: аварія в нативному коді (сигнал 11); SIGSEGV (SEGV_MAPERR) адреса 0x10; потік «mpv/vo»; стек: libmpv.so (…) ← …; памʼять N МБ». `parseTombstone(bytes)` → `NativeCrash` (сигнал, код, адреса, повідомлення abort, потік, що впав, перші `frameCount` кадрів): protobuf Android 12+ (`tombstone.proto`: tid 6, signal_info 10, abort_message 14, threads 16; власний мінімальний читач `_Proto`) або текст Android 11; `anrMain(bytes)` — стек головного потоку з тексту ANR. Тести: `test/exit_reports_test.dart`.

- **ExitRecord** (р.16)
  - `fromMap()` р.43
- **NativeCrash** (р.76)
- **ExitReports** (р.87)
  - `parseTombstone()` р.94
  - `anrMain()` р.232
  - `describe()` р.247
  - `logRecent()` р.290
- **_Proto** (р.308)
  - `varint()` р.319
  - `tag()` р.331
  - `lengthDelimited()` р.337
  - `string()` р.345
  - `skip()` р.350

### `lib/services/episode_guide.dart` (692 р.)
Назви, дати й кадри серій для списку в плеєрі (правило «Назви й кадри серій»): розбір відповідей — `dayOf`, `isStandInTitle`, `isUkrainianTitle`, `MalEpisode` / `malEpisodesOf` (Tenrai), `TmdbEpisode` / `tmdbEpisodesOf`, `tmdbShowsOf`, `tmdbSeasonsOf`, `seasonsBetween`, `matchByDate`; `GuideEpisode`, `EpisodeGuide`; `EpisodeGuideService` (`load`, `peek`, `save`; `GuideGet` і решта підміняються в тестах).

- `dayOf()` (р.29)
- `isStandInTitle()` (р.49)
- `isUkrainianTitle()` (р.52)
- **MalEpisode** (р.55)
  - `toJson()` р.67
  - `fromJson()` р.76
- **TmdbEpisode** (р.107)
  - `toJson()` р.123
  - `fromJson()` р.132
- `tmdbEpisodesOf()` (р.140)
- `tmdbShowsOf()` (р.165)
- `tmdbSeasonsOf()` (р.178)
- `seasonsBetween()` (р.194)
- `matchByDate()` (р.211)
- **MoonEpisode** (р.234)
- `moonEpisodesOf()` (р.253)
- **GuideEpisode** (р.279)
- **EpisodeGuide** (р.323)
- **EpisodeGuideService** (р.335)
  - `peek()` р.384
  - `load()` р.391
  - `save()` р.671

### `lib/services/episode_check.dart` (273 р.)
Звірка серій варіанта з Hikka (див. правило «Звірка з Hikka»): `checkEpisodes(episodes, HikkaEpisodeInfo, othersFrom:)` / `checkGroup(all:)` → `EpisodeCheck` (`level`, `count`, `expected`, `summary` «24 з 12», `note` — текст дисклеймера лише для справжніх розбіжностей нумерації та OVA в кінці, `hasNote`, `isWarning`, `syncSafe`, `syncLimit`, `numbersHold` — номери досі номери Hikka, для AniSkip і пісень), `othersFromOf`, `looksLikeExtra(name)`.

- **EpisodeCheckLevel** (р.16)
- **HikkaEpisodeInfo** (р.40)
- **EpisodeCheck** (р.53)
- `looksLikeExtra()` (р.113)
- `checkEpisodes()` (р.124)
- `checkGroup()` (р.258)

### `lib/services/hikka_api.dart` (786 р.)
Клієнт api.hikka.io (див. правило про дані Hikka; запити акаунта — `auth: true`, токен у заголовку `auth`, див. правило «Акаунт Hikka»): `HikkaApi.instance`, підставний `sender` / `retryDelay` для тестів, `networkCalls`, `clearCache()`; `HikkaException(kind, …)` з українським `message` (мережа / не знайдено / сервер / відповідь). Транспорт `_IoTransport` відкидає `HttpClient` після збою (м'яке закриття) і перевіряє DNS; `HikkaApi.describeError(e)`; повтори: мережа до 3 спроб, тайм-аут і 5xx / 429 — до 2; усе пишеться в `AppLog` (тег `hikka`). Колекції й статті: `collections({contentType, sort: 'popular' | 'new', page, size, allowAdult})` (колекції 18+ відкидаються, якщо `allowAdult` вимкнено), `collection(reference)`, `articles({category, sort: 'new' | 'top', page, size})`, `article(slug)`; `User-Agent` — `AppIdentity.userAgent`. `malIdOf(animeKey)` — id MyAnimeList для `hikka:<slug>` (AniSkip, пісні).

- **HikkaErrorKind** (р.20)
- **HikkaException** (р.22)
- **HikkaRequest** (р.50)
- **HikkaResponse** (р.61)
- **_IoTransport** (р.77)
  - `send()` р.94
- **_CacheEntry** (р.135)
- **HikkaApi** (р.141)
  - `Function()` р.170
  - `Function()` р.173
  - `Function()` р.175
  - `Function()` р.176
  - `clearCache()` р.188
  - `describeError()` р.200
  - `anime()` р.444
  - `malIdOf()` р.453
  - `person()` р.473
  - `franchise()` р.513
  - `character()` р.546
  - `collection()` р.612
  - `article()` р.638
  - `exchangeToken()` р.653
  - `me()` р.661
  - `tokenReference()` р.664
  - `revokeToken()` р.666
  - `myWatch()` р.669
  - `saveWatch()` р.679
  - `removeWatch()` р.683
  - `watchStats()` р.709
  - `isFavourite()` р.713
  - `setFavourite()` р.724
  - `user()` р.741
  - `userStats()` р.749
  - `followStats()` р.757
  - профіль (публічний): `user()`, `userStats()`, `followStats()`, `userActivity()`, `userHistory()` (лише аніме), `favouriteCharacters()`; `articles(author:)`, `collections(author:)`

### `lib/services/hikka_auth.dart` (402 р.)
Вхід в акаунт Hikka (правило «Акаунт Hikka»): `HikkaAuth` (ChangeNotifier; `instance`; `phase`, `signedIn`, `token`, `me`, `username`, `error`, `busy`, `loopbackReady`, `syncProgress` (+ сеттер), `authorizeUrl`, `redirectUri`, `scopes`; `startLogin()`, `cancelLogin()`, `submit(текст)` (запасний шлях), `parseReference(текст)`, `refresh()`, `signOut()`, `setCustomClient(ref, secret)`; залежності підміняються в конструкторі: `api`, `load`/`save`, `urlOpener`, `loopbackFactory`, `loginTimeout`) і `HikkaLoopback` (тимчасовий `HttpServer` на `127.0.0.1:47615`, лише GET `/auth/confirm`, перевірка Host, відповідь-сторінка «Можна повертатися в застосунок»).

- **HikkaAuthPhase** (р.23)
- **HikkaAuth** (р.25)
  - `setCustomClient()` р.125
  - `startLogin()` р.144
  - `cancelLogin()` р.187
  - `submit()` р.199
  - `refresh()` р.252
  - `signOut()` р.263
  - `parseReference()` р.316
- **HikkaLoopback** (р.334)
  - `start()` р.344
  - `close()` р.396

### `lib/services/hikka_client_key.dart` (63 р.)
Вбудований клієнт Hikka («Miki Miki»): референс і ключ лише замасковані (XOR двох масивів, не рядки). `HikkaClientKey.reference` / `secret` збирають значення в памʼяті, `testOverride` — підміна в тестах. Літералів ключа ніде не писати.

- **HikkaClientKey** (р.9)

### `lib/services/hikka_disk_cache.dart` (118 р.)
Кеш відповідей Hikka на диску (`HikkaDiskCache`, тека `hikka_api` у тимчасовій теці застосунку; до 600 файлів, до 14 днів): застосунок стартує зі збережених даних і працює без мережі. `read(key)` → `DiskHit(json, at)` (розбір великого тексту — `JsonWorker`), `write(key, json, at, raw:)` — готовий текст відповіді (`raw`) пишеться як є, без повторного кодування, `clear()`.

- **DiskHit** (р.12)
- **HikkaDiskCache** (р.18)
  - `fileName()` р.43
  - `read()` р.53
  - `write()` р.69
  - `clear()` р.91

### `lib/services/hikka_franchise.dart` (373 р.)
Логіка франшиз (портована з hikka-next, лише аніме): `FranchiseModel` — основна лінія (ланцюг сіквелів), прямі зв’язки, групи (`FranchiseGroup`: основна історія / побічні / альтернативні / рекапи / спінофи / першоджерела), `groupByYear()`, `relationText(node)` («Основна історія, 2 з 3»). Чиста логіка — покрита тестами.

- **FranchiseGroup** (р.9)
- **FranchiseRelationInfo** (р.81)
- **FranchiseNode** (р.89)
- **FranchiseDirect** (р.108)
- **FranchiseEdge** (р.116)
- **FranchiseModel** (р.124)
  - `relationText()` р.152
  - `groupByYear()` р.160
  - `FranchiseModel()` р.364

### `lib/services/hikka_images.dart` (297 р.)
Зображення каталогу: `HikkaImages` (`resized`, `bucket`, `fileName`), `HikkaImageStore` (дисковий кеш, `load`, `evict`, `diskSize`, `clear`, лічильник `downloads`), `HikkaImage` — `ImageProvider` із запасною адресою. `User-Agent` і тека кешу беруться з `AppIdentity` (`<temp>/MikiMiki/hikka_images`).

- **HikkaImages** (р.18)
  - `resized()` р.24
  - `bucket()` р.31
  - `fileName()` р.37
- **HikkaImageFetcher** (р.50)
- **_Gate** (р.53)
- **HikkaImageStore** (р.79)
  - `load()` р.136
  - `evict()` р.187
  - `diskSize()` р.197
  - `clear()` р.210
- **HikkaImage** (р.258)

### `lib/services/hikka_lists.dart` (392 р.)
Мої списки Hikka й прогрес із плеєра (правило «Акаунт Hikka»): `HikkaMyList` (ChangeNotifier; `instance`; кеш записів і улюбленого в памʼяті, скидається при вході/виході): `entry(slug)`, `cached`, `knows`, `save(slug, {status, episodes, score, total, anime})`, `remove`, `stats()`, `isFavourite`, `setFavourite`, `version`, `syncEpisode(slug, серія, {total})` (черга на тайтл, тихі збої), статичний `episodeNumber(number, position, total)`.

- **HikkaMyList** (р.16)
  - `clear()` р.75
  - `statusOf()` р.93
  - `loadIndex()` р.101
  - `knows()` р.187
  - `cached()` р.188
  - `entry()` р.191
  - `save()` р.204
  - `remove()` р.228
  - `stats()` р.238
  - `isFavourite()` р.249
  - `setFavourite()` р.256
  - `episodeNumber()` р.267
  - `syncEpisode()` р.278
  - `unmarkEpisode()` р.290
  - `flushPending()` р.318

### `lib/services/hikka_markdown.dart` (613 р.)
Розбір Markdown з Hikka у прості блоки (абзаци, списки, цитати, спойлери `:::spoiler`; посилання, жирний, курсив; HTML-сутності, нульова ширина): `HikkaMarkdown.parse` / `plain`, `HikkaMarkdown.classify(url)` → `HikkaLinkTarget` (аніме / персонаж каталогу чи зовнішнє посилання). Без Flutter — покрито тестами. `HikkaLinkKind` тепер ще й `collection` / `article`: `hikka.io/collections/<id>` і `hikka.io/articles/<slug>` відкриваються всередині застосунку.

- **MdSpan** (р.9)
- **MdBlock** (р.35)
- **MdParagraph** (р.40)
- **MdListItem** (р.48)
- **MdQuote** (р.55)
- **MdSpoiler** (р.62)
- **HikkaLinkKind** (р.71)
- **HikkaLinkTarget** (р.74)
- **HikkaMarkdown** (р.106)
  - `parse()` р.110
  - `plain()` р.118
  - `parseInline()` р.289

### `lib/services/hikka_nav.dart` (334 р.)
Навігація застосунку: `MainTab` (Головна · Огляд · Списки · Профіль, `label`), `HikkaTab` (розділи «Огляду»: Усе · Календар · Каталог · Колекції · Статті · Персонажі), `HikkaRouteKind` / `HikkaRoute` (відкрита сторінка: вид, slug, `seed` — дані зі списку для миттєвої шапки, `scroll`, `memo`), `HikkaNav` — одинак `HikkaNav.instance` (`ChangeNotifier`; власний стек, не `Navigator`, до 40 сторінок): `main`, `tab`, `routes`, `top`, `canGoBack`; `setMain` (повторний тап по вкладці веде на її корінь), `setTab`, `openCatalog(filters, {focusSearch})` / `openSearch()` (одноразово: `takePendingFilters`, `takeFocusSearch` / `wantsSearchFocus`), `openAnime` / `openCharacter` / `openFranchise` / `openAnimeCharacters` / `openCollection` / `openArticle` / `openLocalLibrary` (повторне відкриття тієї самої сторінки згортається, порожній slug ігнорується), `openLink(url)` (всередину застосунку чи в браузер через `urlOpener`), `back()` (охоронці `addBackGuard` → стек → з іншої вкладки на «Головну» → `false`), `reset()`. Усе пишеться в `AppLog` (тег `навігація`).

- **MainTab** (р.12)
- **HikkaTab** (р.23)
- **HikkaRouteKind** (р.35)
- **HikkaRoute** (р.38)
- **HikkaNav** (р.67)
  - `immersive()` р.69
  - `Function()` р.87
  - `setMain()` р.99
  - `setTab()` р.109
  - `openCatalog()` р.120
  - `openSearch()` р.135
  - `takePendingFilters()` р.138
  - `takeFocusSearch()` р.147
  - `openAnime()` р.164
  - `openCharacter()` р.168
  - `openNotifications()` р.173
  - `openPerson()` р.176
  - `openAnimeStaff()` р.183
  - `openFranchise()` р.187
  - `openAnimeCharacters()` р.191
  - `openCollection()` р.195
  - `openSettings()` р.207
  - `openArticle()` р.212
  - `openLists()` р.221
  - `openUser()` р.231
  - `openLocalLibrary()` р.243
  - `openAdmin()` р.246
  - `openDownloads()` р.249
  - `openDownloadShelf()` р.256
  - `shelfOf()` р.259
  - `openLink()` р.265
  - `addBackGuard()` р.287
  - `removeBackGuard()` р.289
  - `back()` р.293
  - `reset()` р.324

### `lib/services/hikka_pager.dart` (107 р.)
`HikkaPager<T>` — посторінкове завантаження списків (`reload`, `loadMore`, `retry`, `items`, `total`, `hasMore`, `error`); захист від застарілих відповідей (покоління).

- **HikkaPager** (р.8)
  - `reload()` р.44
  - `loadMore()` р.56
  - `retry()` р.90

### `lib/services/hikka_prefs.dart` (35 р.)
Налаштування каталогу: мова назв (`titleLang`) і показ 18+ (`allowAdult`, типово вимкнено); ChangeNotifier, зберігається через `StorageService`.

- **HikkaPrefs** (р.8)
  - `titleLang()` р.22
  - `allowAdult()` р.29

### `lib/services/json_worker.dart` (24 р.)
`JsonWorker.decode(text)` — `jsonDecode` у фоновому ізоляті для тексту від `threshold` (типово 48 КБ: сторінка колекцій ~0,6 МБ займала ~40 мс потоку інтерфейсу телефона), менший — на місці; помилка — той самий `FormatException`. `HikkaApi._request` і `HikkaDiskCache.read` розбирають ним; сирий текст відповіді доходить до запису на диск через `Expando` (`HikkaApi._rawText`). У віджетних тестах поріг високий (`test/flutter_test_config.dart`): фоновому ізоляту потрібен справжній час.

- **JsonWorker** (р.9)
  - `decode()` р.19

### `lib/services/keyboard_shortcuts.dart` (50 р.)
Обробник клавіш: фізичні клавіші + Ctrl/Shift/Alt (однаково в українській та англійській розкладці), пошук у `ShortcutCatalog`, виконання через `PlayerActions`; не втручається, коли фокус у полі вводу; повтор утриманням лише для дій із `repeat`.

- **KeyboardShortcuts** (р.9)
  - `handle()` р.22

### `lib/services/lang_match.dart` (97 р.)
Чиста логіка збігу мови доріжки з кодом із налаштувань (без media_kit — її беруть і плеєр, і драйвер серій): `LangMatch.aliases(code)` (`uk` → {uk, ukr}), `normalizeTag` («pt-BR» → `pt`; `und` → порожньо), `matches(code, {language, title})` (мітка мови важливіша за назву; без мітки мову видно з назви: «Українські», «Ukrainian [FanVox]», «UA»), `pickByLabel(labels, priorities)` (індекс зовнішньої доріжки за пріоритетом; 0, якщо жодна не збіглась).

- **LangMatch** (р.7)
  - `aliases()` р.11
  - `normalizeTag()` р.52
  - `matches()` р.69
  - `pickByLabel()` р.87

### `lib/services/log_export.dart` (81 р.)
Збереження журналу в окремий файл: `LogExport.save({extra, log, saver, now})` → `LogExportResult` (`saved`, `cancelled`, `path`, `fileName`, `error`); системне вікно «Зберегти як» (`FilePicker.saveFile`), `LogExport.fileName()`. Назва файлу — `miki_miki_log_<дата>_<час>.txt`.

- **LogExportResult** (р.16)
- **LogSaver** (р.35)
- **LogExport** (р.37)
  - `fileName()` р.41
  - `save()` р.58

### `lib/services/mpv_config.dart` (301 р.)
Конфіг mpv (hwdec, video-sync) і збір статистики для Stats. Звук: `audioOptions(android:)` — `gapless-audio=weak` (вихід іде за форматом кожної серії; з `yes` перша моно-серія лишала моно на всю сесію, а вихід не перевідкривався) і на Android `ao=audiotrack,opensles` (media_kit ставить OpenSL ES, який міряє затримку пристрою один раз; AudioTrack стежить за часовими мітками); `describeAudioOutput` — плитка «Вихід звуку» у статистиці («5.1 → стерео · 48 кГц · audiotrack»; властивості `current-ao`, `audio-params/hr-channels`, `audio-out-params/…`). Перевірка зі справжнім mpv — `tools/audio_bench.py`. Android: `androidSubtitleFontAsset` / `androidSubtitleFontName` — єдиний шрифт libass (системних у libmpv немає); `sub-font` і `sub-fonts-dir` на Android не виставляються. Теки даних — `AppIdentity.dataDirName`.

- **MpvConfig** (р.11)
  - `ensureEmbeddedFontsDir()` р.18
  - `audioOptions()` р.45
  - `configureEngine()` р.50
  - `loadCustomMpvConf()` р.86
  - `applySubtitleStyles()` р.128
  - `fetchLiveStats()` р.182
  - `describeAudioOutput()` р.243
  - `extractSubtitleTracks()` р.288
  - `extractAudioTracks()` р.295

### `lib/services/network_status.dart` (118 р.)
`NetworkStatus` (`instance`, ChangeNotifier): `online`, `metered`, `type`, `certain` (від системи), `allows(wifiOnly:)`, `ready` (перший стан від системи: завантаження чекають його, щоб перші секунди не йшли мобільним інтернетом), `start()` (Android — події `SystemControls.onNetwork` і `networkState`; ПК — перевірка), `apply`, `reportFailure` / `reportSuccess`, `check()` (пошук `api.hikka.io`; поки офлайн — повтор кожні `recheck`).

- **NetworkStatus** (р.13)
  - `allows()` р.40
  - `start()` р.53
  - `apply()` р.69
  - `reportFailure()` р.81
  - `reportSuccess()` р.86
  - `check()` р.91

### `lib/services/orientation_policy.dart` (126 р.)
Орієнтація плеєра на телефоні: `PlayerOrientation` (system / landscape / portrait, `parse`, `orientations`) і `OrientationPolicy` (`enterPlayer`, `leavePlayer`, `preferenceChanged`, `toggle`, `unlock`, `locked`) — зберігає орієнтацію до відкриття відео й повертає її при виході чи згортанні.

- **PlayerOrientation** (р.11)
  - `parse()` р.20
  - `switch()` р.24
- **OrientationPolicy** (р.31)
  - `enterPlayer()` р.58
  - `leavePlayer()` р.69
  - `preferenceChanged()` р.82
  - `toggle()` р.93
  - `unlock()` р.103

### `lib/services/osd_message.dart` (30 р.)
Модель OSD-повідомлення (заголовок, значення, іконка, клавіші, прогрес, помилка) і `OsdSink`.

- **OsdMessage** (р.5)
- **OsdSink** (р.30)

### `lib/services/playback_clock.dart` (283 р.)
Єдиний «годинник відтворення» на плеєр (`PlaybackClock.of(player)`): одна підписка на потоки position/duration/buffer/playing і готові похідні (`seconds`, `permille`). `ClockValue` — значення, що сповіщає лише при зміні результату; `ClockProgress` — прогрес смужки, що сповіщає при зсуві на піксель (з режимом `live`); `ChapterMath` — чисті функції над розділами (поточний, «Пропустити»). `ChapterMath.songKindOf` / `songStateAt` — розділ опенінґу / ендінґу і перші секунди (для картки пісні).

- **PlaybackClock** (р.17)
  - `of()` р.36
  - `release()` р.39
  - `derive()` р.84
- **ClockValue** (р.96)
  - `refresh()` р.113
- **ClockProgress** (р.141)
- **ChapterMath** (р.224)
  - `indexAt()` р.228
  - `isSkippable()` р.237
  - `songKindOf()` р.246
  - `songStateAt()` р.254
  - `skippableFlags()` р.266
  - `skipIndexAt()` р.270

### `lib/services/player_actions.dart` (450 р.)
Таблиця дій гарячих клавіш: id з `ShortcutCatalog` → замикання (перемотка, швидкість, гучність, субтитри, зображення, Anime4K, вікно, скриншот…) з OSD-відгуком. `run(id)` виконує дію, `escape()` — поведінка Esc. Перемикання доріжок гарячими клавішами — `setSubtitleTrack(…, closeMenu: false)` / `setAudioTrack(…, closeMenu: false)`. Кожна гаряча клавіша пишеться в журнал (`клавіші`, debug).

- **PlayerActions** (р.18)
  - `has()` р.27
  - `run()` р.30
  - `escape()` р.291
  - `Function()` р.314

### `lib/services/player_diagnostics.dart` (251 р.)
Події плеєра в журнал і знімок синхронізації кожні 3 с: `PlayerDiagnostics(player, context:)` (`start`, `sample`, `dispose`), `SyncSnapshot`, `analyzeSync(prev, cur)` — застереження (розбіжність A/V >0,1 с, ≥8 втрачених кадрів за знімок, позиція стоїть, відставання від годинника).

- **SyncSnapshot** (р.17)
- **PlayerDiagnostics** (р.71)
  - `start()` р.86
  - `sample()` р.188

### `lib/services/player_state_controller.dart` (1566 р.)
ГОЛОВНИЙ стан плеєра (ChangeNotifier): Player, VideoController, плейлист, драйвери/меню (drawerOwner, _drawerStack), side panel, stats, fullscreen, збереження позиції, live-знімок прев'ю. `chromeTitle` (для серій із сайтів — назва аніме) і `chromeSubtitle({quality})` («Серія 6 з 28 · Inari», на ПК ще « · 1080p»; черга файлів — «Серія 2 з 3») — назва й сірий рядок у керуванні. Також: `anime4k` (Anime4kController), `keyScheme` / `setKeyScheme()`, `osd` + `showOsd()`, прямі команди mpv (`mpv()`, `mpvGet()`), скриншот, always-on-top, `onShowShortcuts`. Часті значення — окремі нотифікатори, що не перебудовують екран: `liveStats` (опитування статистики, `currentStats`), `volumeState` (`VolumeState`). Наявність файлів черги перевіряється паралельно й асинхронно. `handleBack()` / Esc (`PlayerActions.escape`) спершу питають `panelStepBack()` (панель «Перегляд» повертається з деталей серії чи внутрішньої сторінки до списку). Телефон: панелі показує тап (`toggleControlsByTouch()`, `touchActivity()`); `isInPip`, `pipSupported`, `enterPip()`, автовхід у PiP (`_syncPipArm`); `rotationLocked`, `toggleRotation()`, `unlockRotation()`; `handleBack()` (кнопка «Назад»); `onAppBackgrounded()` (пауза + збереження позиції); `showOsdMessage()` для жестів; системні панелі (immersive у плеєрі, edge-to-edge на головній) та яскравість синхронізує `_syncSystemUi()` при кожному `notifyListeners()`. `toggleFullscreen()` на телефоні нічого не робить. Серії із сайтів: поле `remote` (`RemoteDriver` + `MpvRemoteEngine`), `openRemote(RemoteLaunch)` (скидає панелі й розділи, запускає драйвер), `playNext()` / `playPrevious()` (файли → `player.next/previous`, серії → драйвер; на краях — OSD «Це остання / перша серія»), `openSidePanel(type)`, `selectEpisode(i)` у режимі серій веде в `remote.open`. `_bindRemote()`: `onSession` / `onEntry` наповнюють `playlistItems` синтетичними `remote://…` і виставляють заголовок, розділи (`currentChapters` з таймкодів), `onMessage` → `showOsd`. У потоках плеєра: тривалість → `remote.onDuration`, завершення → `onCompleted`, помилка → `onPlayerError`, тік → `tick`. Операції з чергою файлів (`persistQueue`, `addMediaToQueue`, `reorderQueue`, `removeFromQueue`, `clearQueueExceptCurrent`) для серій нічого не роблять; `remote.stop()` — у кожному `open*` і в `returnToHome`. Субтитри й звук: `_applyTrackDefaults(tracks)` (автовибір за мовами з налаштувань через `TrackDefaults.plan`; пропускається після ручного вибору `_trackChoiceManual` і для серій із сайтів; `_resetAutoTracks()` у кожному `open*` і при зміні елемента черги; OSD «Субтитри»), `setSubtitleTrack` / `setAudioTrack(track, {closeMenu})`, зовнішні субтитри `addExternalSubtitle(path)`, `handleDroppedFiles(paths)`, `pickSubtitleFile()`, `subtitleExtensions`, `isSubtitleFile`. `PlayerConfiguration(libass: true, libassAndroidFont: …)` — шрифт для субтитрів на Android. Журнал і орієнтація: тег `дія` у публічних методах; `PlayerDiagnostics` (`_diag`, контекст — шейдери / джерело / PiP, `_diagContext`); `PlayerConfiguration.logLevel` = `v` у детальному режимі, докладні рядки libmpv не потрапляють у `mpvLogs` (лише у файл); орієнтація — `_orientation` (`OrientationPolicy`), `rotationLocked` — геттер, `refreshOrientationPreference()`, `_syncSystemUi` викликає `enterPlayer` / `leavePlayer`. Знімки кадру лягають у `Зображення/MikiMiki` (`AppIdentity.shortName`). Затримка звуку: `audioDelayKey` (серії — `r|animeKey|озвучка`, файли — `l|тека`), `_applyAudioDelay()` викликається на першу тривалість нового файлу й повертає твору його `audio-delay` (mpv інакше тягне значення попередньої серії). `returnToHome()`: `isCollapsed = false` ставиться лише перед фінальним `notifyListeners()`, щоб «хрестик» мініплеєра не розгортав плеєр (і не мигала орієнтація).

- **PlayerStateController** (р.46)
  - `chromeSubtitle()` р.105
  - `setSeekDragging()` р.171
  - `collapsePlayer()` р.218
  - `expandPlayer()` р.228
  - `init()` р.236
  - `pointerInZone()` р.435
  - `refreshSettings()` р.451
  - `handleInteraction()` р.453
  - `toggleControlsByTouch()` р.456
  - `touchActivity()` р.471
  - `refreshOrientationPreference()` р.495
  - `notifyListeners()` р.520
  - `showOsdMessage()` р.681
  - `enterPip()` р.684
  - `toggleRotation()` р.702
  - `unlockRotation()` р.718
  - `handleBack()` р.729
  - `panelStepBack()` р.756
  - `onAppBackgrounded()` р.759
  - `persistQueue()` р.792
  - `openQueue()` р.799
  - `openFileOrPlaylist()` р.848
  - `openMultipleFiles()` р.875
  - `pickAndOpenFile()` р.906
  - `addMediaToQueue()` р.916
  - `reorderQueue()` р.937
  - `removeFromQueue()` р.950
  - `clearQueueExceptCurrent()` р.961
  - `selectEpisode()` р.974
  - `playNext()` р.989
  - `playPrevious()` р.999
  - `openRemote()` р.1011
  - `openDrawer()` р.1060
  - `openSongDrawer()` р.1078
  - `openSubDrawer()` р.1083
  - `backDrawer()` р.1089
  - `closeDrawers()` р.1095
  - `closeSidePanel()` р.1101
  - `toggleSidePanel()` р.1107
  - `openSidePanel()` р.1116
  - `setSpeed()` р.1123
  - `setSubtitleTrack()` р.1131
  - `setAudioTrack()` р.1138
  - `addExternalSubtitle()` р.1147
  - `isSubtitleFile()` р.1159
  - `handleDroppedFiles()` р.1166
  - `pickSubtitleFile()` р.1181
  - `changeHwdec()` р.1233
  - `toggleFullscreen()` р.1246
  - `enterMiniPlayer()` р.1287
  - `exitMiniPlayer()` р.1320
  - `returnToHome()` р.1341
  - `openStatsOverlay()` р.1365
  - `closeStatsOverlay()` р.1382
  - `setVolumeDelta()` р.1395
  - `toggleMute()` р.1411
  - `mpv()` р.1426
  - `mpvGet()` р.1437
  - `showOsd()` р.1449
  - `setKeyScheme()` р.1475
  - `toggleAlwaysOnTop()` р.1482
  - `takeScreenshot()` р.1494

### `lib/services/playlist_service.dart` (56 р.)
Побудова плейлиста з файлу/теки.

- **PlaylistService** (р.6)

### `lib/services/remote_driver.dart` (785 р.)
Драйвер перегляду серій із сайтів (чиста логіка; правило «Серії з сайтів у плеєрі»). `hikka` — що Hikka знає про серії (`HikkaEpisodeInfo`: вийшло / всього; панель «Перегляд» пише «28 з 28 серій»). `_markWatched` для `hikka:<slug>` ще й передає серію в списки Hikka (`_syncToHikka` → `HikkaMyList.syncEpisode`, правило «Акаунт Hikka»). `RemoteEngine` — що потрібно від плеєра (`openVideo(video, {start})`, `position`, `duration`, `playing`, `addSubtitle` / `addAudio`), `RemotePhase` (idle / resolving / opening / playing / failed). `RemoteDriver` (ChangeNotifier): `start(RemoteLaunch)`, `open(i, {hoster, height, startAt, saveCurrent})`, `next()` / `previous()`, `retry()`, `switchGroup` / `switchHoster` / `switchQuality`, `stop({save})`; події плеєра `onDuration`, `tick`, `onCompleted`, `onPlayerError`; стан: `phase`, `error`, `session`, `title`, `groupId`, `group`, `isSub`, `index`, `entry`, `stream`, `video`, `hoster`, `chapters`, `attempt`, `hasNext` / `hasPrevious`, `active`, `showsStatus` (екран стану поверх відео), `alternativeHoster`, `nowPlaying({withKind})`; зворотні виклики контролера `onEntry`, `onSession`, `onMessage`. Токен (`_token`) відсікає відповіді застарілих запитів; між запитом посилання й початком відео стоїть таймер-сторож; повторне відкриття серії, що закінчилась одразу після старту з середини, починає її спочатку. Також: `checkOf(group)` (звірка варіанта з Hikka за `RemoteLaunch.hikka`); `switchGroup` запам'ятовує вибір (`setPreferredGroup` для тайтлу + `setFavoriteChoice(choiceKeyOf(g))` для нових); зовнішні субтитри варіанта «Субтитри» вмикаються за мовою з налаштувань (`LangMatch.pickByLabel`, інʼєкція `subPriorities`), а не просто перша доріжка. Пропуск без таймкодів сайту: `skips` (`SkipService`) — `onDuration` передає серію (`SkipRequest`, номер для AniSkip — `_numberOf`), план приходить у `_onPlan` → `chapters` / `_stamps` (за ними й `episodeSeen`); `malNumbers` — номери MyAnimeList усієї черги за тим самим правилом (для назв у списку), `progress` — лічильник `tick` (поступ поточної серії в списку); `panelBack` — крок назад усередині відкритої панелі «Перегляд» (ставить `RemotePanelBody`); `skipPlan`, `shiftSkips`, `skipOpeningAt`, `resetSkipShift`; `open` / `stop` — `detach`. Пісні: `songs` (`SongService`) — `attach` в `onDuration`, `detach` в `open` / `stop`; зміни `songs.current` будять драйвер.

- **RemoteEngine** (р.31)
  - `openVideo()` р.33
  - `addSubtitle()` р.42
  - `addAudio()` р.45
- **NextOffer** (р.50)
- **RemotePhase** (р.66)
- **RemoteDriver** (р.83)
  - `Function()` р.139
  - `Function()` р.145
  - `Function()` р.148
  - `Function()` р.152
  - `shiftSkips()` р.200
  - `skipOpeningAt()` р.203
  - `resetSkipShift()` р.206
  - `dismissOffer()` р.216
  - `acceptOffer()` р.223
  - `nowPlaying()` р.252
  - `checkOf()` р.279
  - `start()` р.282
  - `open()` р.297
  - `next()` р.322
  - `previous()` р.328
  - `retry()` р.335
  - `switchGroup()` р.392
  - `switchHoster()` р.417
  - `switchQuality()` р.425
  - `onDuration()` р.438
  - `tick()` р.507
  - `onCompleted()` р.518
  - `onPlayerError()` р.549
  - `stop()` р.577
  - `toggleWatched()` р.649

### `lib/services/remote_engine.dart` (54 р.)
`MpvRemoteEngine implements RemoteEngine` — міст між драйвером і media_kit: `openVideo` відкриває `Media(url, httpHeaders:, start:)` (заголовки й місце початку — до завантаження, без «стрибка»), `addSubtitle` / `addAudio` — команди mpv `sub-add` / `audio-add` (мова коротким кодом, довільний підпис іде в назву). Приймає `Player` і функцію команд mpv (`PlayerStateController.mpv`); імпортує media_kit лише `show Media, Player` (інакше `Track` / `Video` конфліктують з `source_models.dart`).

- **MpvRemoteEngine** (р.9)
  - `openVideo()` р.21
  - `addSubtitle()` р.40
  - `addAudio()` р.44

### `lib/services/remote_playback.dart` (140 р.)
Чиста логіка відтворення серій із сайтів: `chaptersFromTimestamps(stamps, total)` (розділи з таймкодів Moon; проміжки — розділи «Episode», що не пропонуються до пропуску), `episodeSeen(position, total, stamps)` (≥ 85 % або дійшли до ендінґа), `RemoteLaunch` (озвучка, серія, назва, постер → `session`, `startIndex`) і `WatchLauncher` (`attach` / `detach` / `play`) — міст між сторінками застосунку й плеєром. `RemoteLaunch.hikka` (`HikkaEpisodeInfo?`) — що Hikka каже про кількість серій: за цим плеєр показує, де нумерація може не збігатися.

- `chaptersFromTimestamps()` (р.35)
- `episodeSeen()` (р.66)
- **RemoteLaunch** (р.79)
- **WatchLauncher** (р.119)
  - `Function()` р.122
  - `attach()` р.124
  - `detach()` р.126
  - `play()` р.133

### `lib/services/seek_preview_service.dart` (298 р.)
Прев'ю для перемотки: окремий «безголовий» плеєр робить малі кадри під курсором на смужці прогресу, кеш по «кошиках» часу. Плеєр звільняється після 30 с простою (кадри в кеші лишаються), `supports()` запам'ятовує перевірку файлу. Лог [SeekPrev].

- **SeekPreviewService** (р.13)
  - `supports()` р.48
  - `prepare()` р.69
  - `frame()` р.82
  - `hasExact()` р.96
  - `request()` р.98
  - `requestMany()` р.109

### `lib/services/shortcut_catalog.dart` (450 р.)
Каталог гарячих клавіш — єдине джерело правди: схеми `KeyScheme` (стандартна / як у mpv), групи, дії з комбінаціями (фізична клавіша + модифікатори, підписи для довідки, `KeyScope`), пошук комбінації `ShortcutCatalog.find()`.

- **KeyScheme** (р.4)
- **KeyScope** (р.24)
- **ShortcutGroup** (р.35)
- **KeyChord** (р.51)
- **ShortcutDef** (р.77)
- **ShortcutCatalog** (р.97)
  - `find()` р.436
  - `grouped()` р.442

### `lib/services/skips/anime_skip.dart` (284 р.)
Друга база таймкодів — Anime Skip (`api.anime-skip.com/graphql`, спільний `X-Client-ID` з його документації — `AnimeSkip.sharedClientId`, з обмеженням частоти). Шоу шукається за id AniList (`findShowsByExternalId(service: ANILIST)`; MAL → AniList через `graphql.anilist.co`, `Media(idMal:)`); в одного тайтлу AniList буває кілька шоу від різних людей. Позначки — початки частин (Branding, Intro, Canon, Credits, Preview…): частина триває до наступної позначки, остання — до кінця версії (`baseDuration`). `animeSkipKind` (Intro / New Intro → op, Mixed Intro → mixedOp, Credits / New Credits → ed, Mixed Credits → mixedEd, Recap → recap), `animeSkipTimes(json)` → `AniSkipTime` за номером серії (на версію й вид — найдовша частина; опенінґ / ендінґ 20–150 с; `id` з `as:` → `AniSkipTime.base` = «Anime Skip»), `AnimeSkip.times(malId, ep)` (порожньо — не позначено; null — недоступно й нічого не збережено), `AnimeSkip.names(malId)` / `animeSkipNames` — назви серій (те саме шоу, у кеші поруч із таймкодами під `names`; заглушки «Episode 1» відкинуто); кеш `<appBasePath>/anime_skip_cache.json` (id AniList — пів року, серії — тиждень, порожнє — день; старе служить без мережі); тести підміняють `post` і `now`.

- `animeSkipKind()` (р.25)
- `animeSkipNames()` (р.72)
- **AnimeSkip** (р.91)
  - `save()` р.263

### `lib/services/skips/aniskip.dart` (241 р.)
Клієнт AniSkip: `SkipKind` (op / ed / mixedOp / mixedEd / recap), `AniSkipTime` (час на версії довжиною `episodeLength`; `base` — з якої бази; `fromApi`, `toJson` / `fromJson`), `AniSkip.times(malId, ep, length:)` (404 → порожньо, збій → null або старе з кешу; однакові запити разом — один), `candidates` (довірене + найближче за довжиною, без повторів), `bucket` (довжина кроком 5 с), кеш на диску `save()`; тести підміняють `get` і `now`.

- **SkipKind** (р.18)
- **AniSkipTime** (р.20)
  - `kindOf()` р.36
  - `toJson()` р.45
  - `fromJson()` р.47
  - `fromApi()` р.58
- **AniSkip** (р.74)
  - `bucket()` р.110
  - `keyOf()` р.112
  - `save()` р.217

### `lib/services/skips/skip_align.dart` (296 р.)
Чиста логіка: як таймкоди AniSkip лягають на наше відео. `StartShift` (діапазон зсуву, `exact` ≤ 1 с, `intersect`), `SkipPlan`, `versionsOf` / `pickVersions` (версії, що можуть бути нашими: довше чи коротше до 75 с), `lengthShift` (що кажуть довжини), `fitsShift`, `shiftFromOpening` (зсув із виміряного опенінґу), `alignSkips` (відомий точний зсув → точно; інакше безпечно за всіма версіями й зсувами; `opBase` — для «Опенінґ почався тут»); для журналу — `describeTimes`, `describePlan`.

- **StartShift** (р.18)
  - `intersect()` р.38
- **SkipPlan** (р.51)
  - `copyWith()` р.77
- `versionsOf()` (р.111)
- `pickVersions()` (р.122)
- `lengthShift()` (р.128)
- `fitsShift()` (р.136)
- `alignSkips()` (р.199)
- `describeTimes()` (р.260)
- `withFallback()` (р.276)
- `basesOf()` (р.287)
- `describePlan()` (р.293)

### `lib/services/skips/skip_profiles.dart` (183 р.)
`SkipProfiles` (StorageService, розділ `skip_profiles`): `shiftFor` (вручну > звук > сайт; згода → точно, інакше діапазон), `teamHint`, `observe`, `setUser` / `userShift`, `setIntro` / `introFor`, `EpisodeListen` + `saveEpisode` / `episode` / `listened`.

- **EpisodeListen** (р.18)
  - `toJson()` р.29
  - `fromJson()` р.35
- **SkipProfiles** (р.45)
  - `dubKey()` р.73
  - `teamKey()` р.76
  - `shiftFor()` р.106
  - `teamHint()` р.123
  - `observe()` р.133
  - `userShift()` р.148
  - `setUser()` р.151
  - `introFor()` р.162
  - `setIntro()` р.164
  - `episode()` р.170
  - `saveEpisode()` р.172
  - `listened()` р.181

### `lib/services/skips/audio_print.dart` (329 р.)
Відбиток звуку (ізолят): `audioPrint(pcm)` (33 смуги 300–2000 Гц, кадр 2048, крок 128 при 8 кГц, порівняння з кроком 4 назад; тиша — випадкові слова), `AudioPrint.toBytes` / `fromBytes`, `commonRuns` (усі зсуви, порівняння через крок, вікно ~1 с, прощає ~1,5 с, краї звужує за власною якістю збігу), `PrintRun`, `listenRuns` → `Listened` (заставка з самого початку / опенінґ).

- **AudioPrint** (р.28)
  - `toBytes()` р.39
  - `fromBytes()` р.49
- `audioPrint()` (р.106)
- **PrintRun** (р.162)
- `commonRuns()` (р.193)
- **Listened** (р.281)
- `listenRuns()` (р.293)

### `lib/services/skips/audio_probe.dart` (81 р.)
`AudioProbe.decode(url, headers:, start:, length:)` — прихований media_kit `Player` (`vid=no`, `ao=pcm`, 8 кГц моно s16, `untimed`, `hls-bitrate=min`) пише звук у тимчасовий файл; по одному за раз; `PcmDecoder` — тип для підміни в тестах.

- **AudioProbe** (р.20)
  - `decode()` р.26

### `lib/services/skips/skip_service.dart` (479 р.)
`SkipService` (див. «Ключові правила»): `attach` / `detach` / `refresh` (пише план у журнал), `current`, `planFor` (`_plan` — план і рядок для журналу), `shiftBy` / `openingAt` / `resetShift`, `onDownloaded`; `SkipRequest`; запас `edgeIn` / `edgeOut` для почутого; аналіз звуку `_listen` (сусід: збережений відбиток поруч → наступна / попередня серія через `DownloadManager` або `StreamResolver` на 480p).

- **SkipRequest** (р.38)
- **SkipService** (р.67)
  - `attach()` р.134
  - `detach()` р.155
  - `refresh()` р.165
  - `shiftBy()` р.176
  - `openingAt()` р.188
  - `resetShift()` р.198
  - `planFor()` р.235
  - `onDownloaded()` р.439

### `lib/services/songs/theme_songs.dart` (554 р.)
Чиста логіка пісень: `SongKind`, `MusicApp` (Spotify / YouTube Music / Apple Music / YouTube), `ThemeSong` (назва, оригінальна назва, виконавці та їхні оригінальні імена `nativeArtists`, серії, посилання; `label`, `query`, `covers`, `span`, `copyWith` / `withLinks`, `toJson` / `fromJson`), `parseEpisodes`, `pickSong` (найвужчий діапазон; без серій — лише єдина), `musicAppOf` / `searchLink` / `musicAppName`; AnimeThemes GraphQL — `animeThemesGraphql`, `animeThemesQuery`, `songsOfAnimeThemes` (без тем із `group`), `linksOf`; MyAnimeList через Tenrai — `tenraiThemes`, `songOfMalLine`, `songsOfMal`; Hikka — `splitNative`, `songsOfHikka`; разом — `combineSongs`, `enrichSongs`; обкладинки — `SongArt`, `matchScore`, `artOfItunes`, `artOfDeezer`, `appleTrackId`, `appleCountry`, `coverOfItunesLookup`, `coverOfSpotify`.

- **SongKind** (р.11)
- **MusicApp** (р.14)
- **ThemeSong** (р.16)
  - `covers()` р.54
  - `copyWith()` р.66
  - `withLinks()` р.85
  - `toJson()` р.87
  - `fromJson()` р.98
- `parseEpisodes()` (р.126)
- `pickSong()` (р.144)
- `musicAppOf()` (р.158)
- `searchLink()` (р.168)
- `musicAppName()` (р.178)
- `animeThemesQuery()` (р.192)
- `songsOfAnimeThemes()` (р.200)
- `linksOf()` (р.272)
- `tenraiThemes()` (р.307)
- `songOfMalLine()` (р.316)
- `songsOfMal()` (р.349)
- `songsOfHikka()` (р.364)
- `combineSongs()` (р.395)
- `enrichSongs()` (р.405)
- **SongArt** (р.452)
  - `toJson()` р.457
  - `fromJson()` р.458
- `artOfItunes()` (р.487)
- `artOfDeezer()` (р.506)
- `appleTrackId()` (р.526)
- `appleCountry()` (р.538)
- `coverOfItunesLookup()` (р.544)
- `coverOfSpotify()` (р.553)

### `lib/services/songs/song_service.dart` (333 р.)
`SongService` (див. «Ключові правила»): `attach` / `detach`, `current` (`EpisodeSongs`), `songsOf(malId)` (AnimeThemes GraphQL, кеш `themes:<mal>`), `malSongsOf(malId)` (Tenrai, кеш `tenrai:<mal>`), `artOf`, `linksFor` (`SongLink`), диск — `save()`; тести підміняють `get` (GET або POST з `body`), `malId`, `ost` (пісні Hikka), `now`, `enabled`.

- **EpisodeSongs** (р.25)
  - `of()` р.36
  - `copyWith()` р.38
- **SongLink** (р.43)
- **SongService** (р.53)
  - `attach()` р.97
  - `detach()` р.143
  - `linksFor()` р.149
  - `artOf()` р.196
  - `save()` р.312

### `lib/services/source_prefs.dart` (69 р.)
Налаштування джерел (розділ `source_prefs`): `isEnabled` / `setEnabled(id)`, `mikaiKey`, `maxHeight` (0 — найвища; `heights`, `heightLabel`), `hoster` (бажаний плеєр); ChangeNotifier, `SourcePrefs.instance`.

- **SourcePrefs** (р.8)
  - `reload()` р.25
  - `isEnabled()` р.43
  - `setEnabled()` р.45
  - `mikaiKey()` р.55
  - `maxHeight()` р.61
  - `hoster()` р.66
  - `heightLabel()` р.68

### `lib/services/source_registry.dart` (68 р.)
Реєстр джерел: `SourceRegistry.standard()` (Mikai, UFDub, UAKino зі спільним `SourceHttp`), `all`, `enabled`, `byId`, `mikai`; ключ Mikai підхоплюється з `SourcePrefs`. `SourceRegistry.instance`.

- **SourceRegistry** (р.12)
  - `byId()` р.55
  - `isEnabled()` р.65

### `lib/services/sources/anime_source.dart` (94 р.)
Контракт джерела (`AnimeSource`: `id`, `name`, `lang`, `baseUrl`, `about`, `supportsLatest`, `nsfw`; `popular / latest / search / details / episodes / hosters / hosterVideos / videos`, `animeWebUrl`) і база для сайтів на HTML (`HttpAnimeSource`: `absoluteUrl`, `urlWithoutDomain`, `document`, `parseList`).

- **AnimeSource** (р.11)
  - `popular()` р.25
  - `latest()` р.26
  - `search()` р.27
  - `details()` р.30
  - `episodes()` р.33
  - `videos()` р.36
  - `hosters()` р.39
  - `hosterVideos()` р.41
  - `animeWebUrl()` р.44
- **HttpAnimeSource** (р.48)
  - `absoluteUrl()` р.56
  - `urlWithoutDomain()` р.63
  - `animeWebUrl()` р.75
  - `document()` р.77
  - `parseList()` р.83

### `lib/services/sources/episode_naming.dart` (43 р.)
Номер серії й сезону з людських назв («Серія 12 — …», «12 серія», «Сезон 2», «Episode 5»): `parseEpisodeNumber`, `parseSeasonNumber`, `looksLikeNumbered`; `siteEpisodeTitle` — власна українська назва серії після номера («Серія 13 - Нацу проти Юкі» → «Нацу проти Юкі»; не позначка OVA, не латиницею).

- `looksLikeNumbered()` (р.24)
- `siteEpisodeTitle()` (р.37)

### `lib/services/sources/extractors.dart` (531 р.)
Екстрактори плеєрів: `VideoExtractors.forUrl(url)` / `playerName(url)` / `plain(url)`, `AshdiExtractor` (`ashdi.vip/vod/<id>` → `index.m3u8`; серіальні сторінки), `MoonExtractor` (iframe `moonanime.art`: шаблони Video.js і PlayerJS, розшифровка двох шарів, субтитри, таймкоди `__skipSegments` / `__skipCtx`; Premium API — `fieldsOf` раз за запуск пише в журнал поля відповіді `video/{slug}`, чи є там назви серій), `EmbedLink(provider, url)` + `encodeEmbeds` / `embedsOf` / `hostersFor` / `hosterVideosOf` / `videosOfEpisode` — як серія зберігає перелік своїх плеєрів у `SEpisode.data`; `embedHeaders(referer)` (заголовки як у iframe), `parseBracketList` («[Назва]посилання, …»), `subtitleLang`. Не підтримуваний плеєр → `SourceException(unsupported)`.

- `embedHeaders()` (р.17)
- `parseBracketList()` (р.27)
- `subtitleLang()` (р.34)
- **VideoExtractor** (р.43)
  - `canHandle()` р.49
- **VideoExtractors** (р.55)
  - `forUrl()` р.61
  - `playerName()` р.70
  - `plain()` р.83
- **AshdiExtractor** (р.112)
  - `canHandle()` р.119
- **MoonExtractor** (р.153)
  - `canHandle()` р.160
  - `decodeLayer1()` р.179
  - `decodeXorString()` р.194
  - `parsePage()` р.216
  - `slugOf()` р.308
  - `fieldsOf()` р.339
- **EmbedLink** (р.453)
- `providerOf()` (р.464)
- `encodeEmbeds()` (р.467)
- `embedsOf()` (р.473)
- `hostersFor()` (р.490)

### `lib/services/sources/hls.dart` (134 р.)
Майстер-плейлист HLS: `parseHlsMaster(text, base)` → `HlsMaster` (варіанти якості `HlsVariant`: адреса, швидкість, роздільність; доріжки `HlsRendition` з EXT-X-MEDIA), `videosFromHls(master, url, {headers, withAuto})` → список `Video` («Авто» = сам майстер-плейлист, далі 1080p / 720p / 480p).

- **HlsVariant** (р.8)
- **HlsRendition** (р.19)
- **HlsMaster** (р.31)

### `lib/services/sources/hls_proxy.dart` (179 р.)
Локальний HLS-проксі для CDN, які не пускають TLS libmpv на Android: `HlsProxy.enabled`, `HlsProxy.instance.wrap(url, headers)` → локальна адреса списку; `HlsProxy.rewritePlaylist(text, base, local)` — чиста функція переписування адрес (сегменти, підсписки, `URI="…"`). Сегменти йдуть потоком з Range; помилки оригіналу (403) віддаються як є (початок сторінки захисту — у `SourceLog`); `HlsProxy.instance.blocked` / `blockedCount` — лічильник відмов сегментів: `RemoteDriver` (`_watchBlocked`) після 3 відмов під час відкриття одразу переходить на інший плеєр, не чекаючи 30 с.

- **HlsProxy** (р.15)
  - `wrap()` р.46
  - `rewritePlaylist()` р.76

### `lib/services/sources/html_select.dart` (187 р.)
Jsoup-подібні вибірки поверх `package:html` (парсери сайтів пишуться майже один в один із Kotlin-коду розширень Aniyomi): `parseHtml`, `select` / `selectFirst` (CSS-селектори з `:contains` / `:containsOwn` і неквотованими значеннями атрибутів `input[value*=https://x]`), `attrOf`, `textOf`, `elementText`, `ownText`, `scriptsOf` (текст усіх `<script>`), розширення `JsoupElement` / `JsoupElements` (`attr`, `select`, `selectFirst`, `text`).

- **JsoupElement** (р.163)
- **JsoupElements** (р.177)

### `lib/services/sources/source_http.dart` (379 р.)
HTTP для джерел: `SourceHttp` (`get`, `postForm`, ручні редиректи, куки між запитами, `User-Agent`, підстановний `sender` для тестів), `SourceRequest` / `SourceResponse`, `CookieJar` (`store`, `headerFor`), `IoSourceTransport` (`dart:io`), `SourceException(kind, detail, {status})` з українським `message` + `SourceErrorKind` (`network`, `timeout`, `notFound`, `blocked`, `rateLimited`, `server`, `badResponse`, `unsupported`).

- **SourceErrorKind** (р.11)
- **SourceException** (р.13)
- **SourceRequest** (р.41)
  - `copyWith()` р.55
- **SourceResponse** (р.64)
- **IoSourceTransport** (р.118)
  - `send()` р.121
- **CookieJar** (р.161)
  - `store()` р.164
  - `headerFor()` р.194
  - `clear()` р.205
  - `get()` р.207
- **SourceHttp** (р.222)
  - `encodeForm()` р.238
  - `parseUrl()` р.242
  - `get()` р.254
  - `postForm()` р.257
  - `resolve()` р.265
  - `send()` р.275
- `decodeWindows1251()` (р.366)

### `lib/services/sources/source_log.dart` (45 р.)
Журнал джерел перегляду для діагностики: `SourceLog.add(text)` (час від запуску + текст; значення token/key/apikey приховуються), `SourceLog.clear()`, `SourceLog.instance` (`ChangeNotifier`, `lines`, ≤400); кожен рядок дублюється в `AppLog` (тег `джерела`, збої — попередження).

- **SourceLog** (р.10)
  - `clean()` р.21
  - `add()` р.24
  - `clear()` р.41

### `lib/services/sources/title_match.dart` (123 р.)
Зіставлення назв із різних сайтів: `normalizeTitle`, `seasonOfTitle`, `titleSimilarity` (біграми Діса; розбіжність сезону ×0.35, типу OVA / фільм ×0.6), `bestAnimeMatch(wanted, candidates, {year, threshold: 0.74})` → `TitleMatch`.

- **_Norm** (р.34)
- **TitleMatch** (р.98)

### `lib/services/sources/ua/mikai_source.dart` (547 р.)
Mikai (api.mikai.me/public/v1, без ключа 60 запитів/хв; ключ — заголовок `X-API-Key`): каталог (`popular` / `latest` / `search`), `byHikka(slug)` / `byMal(id)`, `player(anime)` → `MikaiPlayer` (релізи `MikaiRelease` по командах `MikaiTeam`, озвучення чи субтитри, `licensed` + `MikaiLicense`), `episodesOfRelease(release)` (серії лише з підтримуваними плеєрами; `voice` = підпис релізу), `teamInfo(team)` (опис і посилання команди). Кеш відповідей з TTL, 429 → `rateLimited`. `User-Agent` — `AppIdentity.userAgent`.

- **MikaiTeam** (р.15)
- **MikaiTeamInfo** (р.25)
- **MikaiEmbed** (р.51)
- **MikaiEpisode** (р.58)
- **MikaiRelease** (р.71)
- **MikaiLicense** (р.99)
- **MikaiPlayer** (р.106)
- **_Cached** (р.114)
- **MikaiSource** (р.120)
  - `clearCache()` р.147
  - `api()` р.149
  - `animeFromJson()` р.226
  - `teamFromJson()` р.259
  - `playerFromJson()` р.268
  - `popular()` р.346
  - `latest()` р.349
  - `search()` р.352
  - `details()` р.355
  - `byHikka()` р.363
  - `byMal()` р.376
  - `animeWebUrl()` р.388
  - `teamInfo()` р.463
  - `player()` р.489
  - `episodesOfRelease()` р.505
  - `flatten()` р.525
  - `episodes()` р.528
  - `hosters()` р.539
  - `hosterVideos()` р.542
  - `videos()` р.546

### `lib/services/sources/ua/uakino_source.dart` (258 р.)
UAKino (uakino.best, DLE): список / пошук, сторінка аніме, плейлист серій AJAX `playlists.php` (озвучки через `data-voice`), серіали Ashdi (JSON «озвучка → сезон → серія»), одиночні фільми з `iframe#pre`. За Cloudflare з деяких IP відповідає блокуванням (потрібне проходження перевірки в WebView — ще не зроблено); перевірено лише на збережених сторінках.

- **UaKinoSource** (р.17)
  - `popular()` р.44
  - `latest()` р.50
  - `search()` р.56
  - `parsePage()` р.69
  - `fromElement()` р.72
  - `details()` р.88
  - `parseDetails()` р.93
  - `newsId()` р.110
  - `parsePlaylist()` р.124
  - `parseAshdiSerial()` р.156
  - `episodes()` р.206
  - `videos()` р.248

### `lib/services/sources/ua/ufdub_source.dart` (243 р.)
UFDub (ufdub.com, DLE): список / пошук POST-формою, сторінка аніме → плеєр V2 (`video.ufdub.com/AT/VP.php`) → масив серій; відео — mp4 через редирект на api.ufdub.com (Dropbox-посилання → `?raw=1`).

- **UfDubSource** (р.15)
  - `popular()` р.41
  - `latest()` р.52
  - `search()` р.58
  - `parsePage()` р.71
  - `fromElement()` р.73
  - `details()` р.112
  - `parseDetails()` р.117
  - `playerUrl()` р.158
  - `parsePlayer()` р.175
  - `episodes()` р.210
  - `videos()` р.221

### `lib/services/storage_service.dart` (510 р.)
Збереження налаштувань, історії, позицій відтворення, черги й плейлистів. Ключі Anime4K: `getAnime4kEnabled/Mode/Quality/SkipHeight` + `save…`; схема клавіш: `getKeyScheme/saveKeyScheme`; `getHwdec()` за замовчуванням бере `AppPlatform.defaultHwdec`. Файл стану: Windows — `%APPDATA%/MikiMiki`, Android — `files/MikiMiki` (правило «Назва застосунку»). Каталог Hikka: `getHikkaTitleLang/saveHikkaTitleLang` (мова назв: ua / en / ja), `getHikkaAllowAdult/saveHikkaAllowAdult` (18+, типово вимкнено). Розділи для даних джерел перегляду: `getSection(key)` / `saveSection(key, map)` (типи `SectionLoader` / `SectionSaver`); їх використовують `SourcePrefs` і `WatchStore`. `getPlayerOrientation` / `savePlayerOrientation` ('system' | 'landscape' | 'portrait'), `getDetailedLog` / `saveDetailedLog` (типово true). Перейменування: теки даних — `AppIdentity.dataDirName` (`_basePathFor`), на ПК при старті `AppIdentity.migrateLegacyData` переносить `MyPlayerFork` → `MikiMiki`. Банери: `getTmdbKey` / `saveTmdbKey` (ключ TheMovieDB; запасне значення — `--dart-define=TMDB_KEY`). Приховане: `getLocalLibrary` / `saveLocalLibrary` / `localLibraryListenable` (локальна медіатека). Кнопки перемотки на телефоні: `getMobileSeekButtons/saveMobileSeekButtons` (ключ `mobile_seek_buttons`, типово true; вимикач у Налаштування → Відтворення, `MobileControls.seekButtons`). Затримка звуку твору: `getAudioDelay/saveAudioDelay(key, ms)` (мапа `audio_delays`, нуль видаляє запис). `getHikkaListRows` / `saveHikkaListRows` — «Списки» рядками замість сітки.

- **StorageService** (р.13)
  - `init()` р.19
  - `flush()` р.75
  - `getAudioDelay()` р.86
  - `saveAudioDelay()` р.91
  - `getPlaybackPosition()` р.103
  - `savePlaybackPosition()` р.108
  - `readRaw()` р.122
  - `writeRaw()` р.125
  - `allPlaybackPositions()` р.135
  - `writePlaybackPosition()` р.141
  - `getSection()` р.153
  - `saveSection()` р.158
  - `getTmdbKey()` р.166
  - `saveTmdbKey()` р.168
  - `getLocalLibrary()` р.172
  - `saveLocalLibrary()` р.173
  - `getThemeMode()` р.185
  - `saveThemeMode()` р.186
  - `getAccentColorHex()` р.188
  - `saveAccentColorHex()` р.189
  - `getUiRadius()` р.191
  - `saveUiRadius()` р.192
  - `getPhoneUiScale()` р.196
  - `savePhoneUiScale()` р.197
  - `getAutoplayNext()` р.200
  - `saveAutoplayNext()` р.201
  - `getDefaultPlaybackSpeed()` р.203
  - `saveDefaultPlaybackSpeed()` р.204
  - `getSeekStep()` р.206
  - `saveSeekStep()` р.207
  - `getSeekButtons()` р.209
  - `saveSeekButtons()` р.210
  - `getMobileSeekButtons()` р.213
  - `saveMobileSeekButtons()` р.214
  - `getDoubleTapSeek()` р.216
  - `saveDoubleTapSeek()` р.217
  - `getHoldToSpeedEnabled()` р.219
  - `saveHoldToSpeedEnabled()` р.220
  - `getHoldToSpeedRate()` р.222
  - `saveHoldToSpeedRate()` р.223
  - `getAutoSkipChapters()` р.225
  - `saveAutoSkipChapters()` р.226
  - `getShowSkipButton()` р.229
  - `saveShowSkipButton()` р.230
  - `getListenForSkips()` р.233
  - `saveListenForSkips()` р.234
  - `getShowThemeSongs()` р.237
  - `saveShowThemeSongs()` р.238
  - `getAnime4kEnabled()` р.241
  - `saveAnime4kEnabled()` р.242
  - `getAnime4kMode()` р.245
  - `saveAnime4kMode()` р.246
  - `getAnime4kQuality()` р.249
  - `saveAnime4kQuality()` р.250
  - `getAnime4kSkipHeight()` р.253
  - `saveAnime4kSkipHeight()` р.254
  - `getHikkaTitleLang()` р.258
  - `saveHikkaTitleLang()` р.259
  - `getHikkaShowSecondary()` р.262
  - `saveHikkaShowSecondary()` р.263
  - `getHikkaListRows()` р.265
  - `saveHikkaListRows()` р.266
  - `getHikkaSecondaryLang()` р.267
  - `saveHikkaSecondaryLang()` р.268
  - `getWatchTeamPriority()` р.271
  - `saveWatchTeamPriority()` р.272
  - `getPreferFullDub()` р.277
  - `savePreferFullDub()` р.278
  - `getWatchedPercent()` р.281
  - `saveWatchedPercent()` р.282
  - `getWatchedByEnding()` р.285
  - `saveWatchedByEnding()` р.286
  - `getKnownTeams()` р.289
  - `clearKnownTeams()` р.291
  - `rememberTeams()` р.292
  - `getHikkaAllowAdult()` р.310
  - `saveHikkaAllowAdult()` р.311
  - `getKeyScheme()` р.315
  - `saveKeyScheme()` р.316
  - `getHwdec()` р.319
  - `saveHwdec()` р.320
  - `getVolume()` р.322
  - `saveVolume()` р.323
  - `getSpeed()` р.325
  - `saveSpeed()` р.326
  - `getPitchCorrection()` р.328
  - `savePitchCorrection()` р.329
  - `getPlayerOrientation()` р.332
  - `savePlayerOrientation()` р.333
  - `getDetailedLog()` р.336
  - `saveDetailedLog()` р.337
  - `getDefaultAudioLang()` р.339
  - `saveDefaultAudioLang()` р.340
  - `getAudioLangPriorities()` р.342
  - `saveAudioLangPriorities()` р.350
  - `getSubLangPriorities()` р.357
  - `saveSubLangPriorities()` р.366
  - `getDefaultSubLang()` р.372
  - `saveDefaultSubLang()` р.373
  - `getSubFont()` р.375
  - `saveSubFont()` р.376
  - `getSubFontSize()` р.378
  - `saveSubFontSize()` р.379
  - `getSubTextColor()` р.381
  - `saveSubTextColor()` р.382
  - `getSubBorderSize()` р.384
  - `saveSubBorderSize()` р.385
  - `getSubBorderColor()` р.387
  - `saveSubBorderColor()` р.388
  - `getSubShadowOffset()` р.390
  - `saveSubShadowOffset()` р.391
  - `getSubMarginY()` р.393
  - `saveSubMarginY()` р.394
  - `getSubBgOpacity()` р.396
  - `saveSubBgOpacity()` р.397
  - `getSubAssMode()` р.399
  - `saveSubAssMode()` р.400
  - `getCustomFonts()` р.402
  - `addCustomFont()` р.403
  - `getRecentFiles()` р.412
  - `addRecentFile()` р.413
  - `clearRecentFiles()` р.422
  - `getLastQueue()` р.440
  - `saveLastQueue()` р.449
  - `clearLastQueue()` р.456
  - `createPlaylist()` р.486
  - `updatePlaylist()` р.495
  - `deletePlaylist()` р.506

### `lib/services/stream_resolver.dart` (86 р.)
Відео для серії в момент відтворення: `StreamResolver({maxHeight, preferredHoster}).resolve(source, episode, {hoster, height})` → `ResolvedStream` (відео, усі якості, обраний плеєр, усі плеєри); плеєри перебираються за порядком, перший робочий виграє, помилка зведена (один плеєр — його власна).

- **ResolvedStream** (р.11)
- **StreamResolver** (р.28)
  - `withoutAshdiWhereMoon()` р.36
  - `resolve()` р.48

### `lib/services/system_controls.dart` (231 р.)
Міст до Android через `MethodChannel('miki_miki/system')` (реалізація — `MainActivity.kt`): `pipSupported`, `enterPip`, `setPipAuto`, `inPip` (нотифікатор; шле Android), `getBrightness/setBrightness/resetBrightness/restoreBrightness` (`userBrightness` — вибір жестом), `getVolume/setVolume`, `exits(since)` (як завершувались минулі процеси — Android 11+ `ApplicationExitInfo`, канал `exits`: причина, статус, опис, важливість, памʼять, сирий трейс нативної аварії / ANR до 512 КБ). Поза Android усі методи безпечні (нічого не роблять); `debugEnabled` — для тестів. `openUrl(url)` — відкриває http(s)-посилання у браузері (Android — канал `openUrl`, десктоп — системна команда); потрібен каталогу Hikka. Події звуку з Android: `onAudioRoute({change, devices, route})` (пристрої виводу прийшли / пішли) і `onAudioNoisy` (навушники зняли). `deviceInfo()` → `Map` (модель, Android, RAM, енергозбереження, нагрів, частота екрана, маршрут звуку) з `MainActivity.kt` (метод `deviceInfo`); поза Android — `null`. `installApk(path, {askPermission})` → `started` / `permission` / `denied` / причина (метод `installApk` у `MainActivity.kt`: `canRequestPackageInstalls`, `ACTION_MANAGE_UNKNOWN_APP_SOURCES`, FileProvider `${applicationId}.updates` з `res/xml/update_paths.xml` → `ACTION_INSTALL_PACKAGE`; маніфест: `REQUEST_INSTALL_PACKAGES`). Канал — `miki_miki/system`.

- **SystemControls** (р.12)
  - `Function()` р.21
  - `Function()` р.24
  - `Function()` р.28
  - `Function()` р.31
  - `Function()` р.34
  - `Function()` р.37
  - `init()` р.48
  - `pipSupported()` р.85
  - `enterPip()` р.88
  - `setPipAuto()` р.93
  - `setPipPlaying()` р.97
  - `setAudioFocus()` р.101
  - `getBrightness()` р.109
  - `setBrightness()` р.110
  - `resetBrightness()` р.116
  - `restoreBrightness()` р.119
  - `openUrl()` р.141
  - `installApk()` р.166
  - `networkState()` р.178
  - `downloadService()` р.186
  - `storageInfo()` р.190
  - `pushToken()` р.197
  - `pushInbox()` р.213
  - `pushDiagnose()` р.216
  - `requestPushPermission()` р.222
  - `initialLink()` р.225
  - `getVolume()` р.228
  - `setVolume()` р.229

### `lib/services/thumbnail_service.dart` (297 р.)
Прев'юшки: дисковий кеш PNG, watch/unwatch (ValueNotifier), черга фонової генерації, live-збереження. Логи з префіксом [Thumb]. Кеш прев'ю лежить у `<тека даних>/thumbnails` (`AppIdentity.dataDirName`).

- **ThumbnailService** (р.18)
  - `holdFor()` р.33
  - `init()` р.40
  - `getCachedThumbnail()` р.115
  - `watch()` р.131
  - `unwatch()` р.148
  - `saveLiveThumbnail()` р.287

### `lib/services/touch_gestures.dart` (56 р.)
Чиста математика жестів на відео (телефон): діапазон перемотки (10 % тривалості, 60…240 с на ширину екрана), цільова позиція, рівень яскравості/гучності від вертикального зсуву (85 % висоти = увесь діапазон), ліва/права половина, системні краї (22/30/30 dp), підпис зсуву `+0:23`. Без віджетів — покрито тестами.

- **TouchGestureMath** (р.8)
  - `seekSpanSeconds()` р.12
  - `seekTarget()` р.20
  - `levelAfterDrag()` р.34
  - `isBrightnessSide()` р.40
  - `inSystemEdge()` р.43
  - `deltaLabel()` р.48

### `lib/services/touch_hide_timer.dart` (37 р.)
Автоприховування панелей керування на сенсорному екрані: `arm()` (на кожен дотик) перезапускає відлік 4 с, `cancel()`; не ховає, якщо `shouldStayVisible()` (пауза, меню).

- **TouchHideTimer** (р.8)
  - `arm()` р.25
  - `cancel()` р.33

### `lib/services/track_defaults.dart` (89 р.)
Автовибір доріжок для щойно відкритого файлу: `TrackDefaults.plan(tracks, {subtitlesEnabled, subPriorities, audioPriorities})` → `TrackPlan` (`subtitle`: `null` — нічого не чіпати, `SubtitleTrack.no()` — вимкнути; `audio`), `pickSubtitle`, `pickAudio` (перша мова зі списку, для якої є доріжка; повні субтитри перед «Signs & Songs» / «Forced», текстові перед зображеннями, «за замовчуванням» перед рештою; коментарі режисера останніми). Без цього mpv вмикає лише доріжку з позначкою «за замовчуванням».

- **TrackPlan** (р.6)
- **TrackDefaults** (р.22)
  - `pickSubtitle()` р.47
  - `pickAudio()` р.57
  - `plan()` р.68
- **_Cand** (р.80)

### `lib/services/ui_theme_service.dart` (281 р.)
uiTheme (синглтон): палітри light/dark, акцент (adaptAccent/contrast), радіуси, кольори поверхонь/тексту.

- **AppThemePalette** (р.6)
- **UiThemeService** (р.78)
  - `init()` р.109
  - `contrastRatio()` р.186
  - `readableOn()` р.195
  - `adaptAccent()` р.201
  - `radius()` р.252
  - `borderRadius()` р.253
  - `setAccentHex()` р.255
  - `setRadiusKey()` р.262
  - `setThemeMode()` р.268
  - `reset()` р.274

### `lib/services/watch_models.dart` (436 р.)
Моделі «Дивитись»: `episodeKey(episode, index)` («3», «3.5», «s2e5», «i7»), `WatchGroup` (озвучка / субтитри: `id` = `джерело|аніме|реліз`, `label`, `isSub`, `teams`, `episodes`), `WatchOffer` (що знайшло джерело), `WatchTitle` (пропозиції + `licensed` / `license` + `errors`), `RemoteEntry` / `RemoteSession` (черга плеєра: ключ `hikka:<slug>#<серія>` для позиції й «переглянуто»; однакові номери в одному варіанті отримують суфікс `~2`). Також: `episodeLabel(episode, index)` (підпис кнопки серії), `episodesOfList(episodes, total:)` («з N» під назвою в плеєрі: за номерами серій і кількістю на Hikka, а не за довжиною списку — «Серія 14 з 19» для озвучки 10–19), `episodeKeysOf(group)` (ключі серій варіанта; повтори отримують `~2`, `~3`), `ContinuePoint` + `continuePoint(keys, watched, lastKey)` (звідки продовжити: остання відкрита, а якщо вона переглянута — наступна; усе переглянуто → `allWatched`). Також: `WatchGroup.fullLabel` («Озвучення: Inari» / «Субтитри: Inari»), `choiceKeyOf(group)` (стійка ознака варіанта поза тайтлом: вид + команди), `pickGroup(groups, {preferredId, favorites, safe})` (який варіант відкриває «Дивитись»).

- `episodeKey()` (р.12)
- `episodeLabel()` (р.20)
- `episodesOfList()` (р.28)
- **WatchGroup** (р.38)
  - `hasEpisode()` р.74
  - `hasEpisodeAfter()` р.83
  - `ranges()` р.93
  - `isIncomplete()` р.131
- `choiceKeyOf()` (р.149)
- `pickGroup()` (р.163)
- `teamMatches()` (р.196)
- `maxEpisodeOf()` (р.205)
- `sortGroups()` (р.217)
- **WatchOffer** (р.247)
- **WatchTitle** (р.258)
  - `offerOf()` р.287
  - `groupById()` р.294
  - `offerOfGroup()` р.301
- **RemoteEntry** (р.305)
- `episodeKeysOf()` (р.326)
- **ContinuePoint** (р.344)
- `continuePoint()` (р.361)
- **RemoteSession** (р.389)
  - `indexOfKey()` р.428
  - `displayTitle()` р.431

### `lib/services/watch_service.dart` (361 р.)
`WatchService.start(HikkaAnime, {searchOthers})` → `WatchLoad` (див. правило «Потік Дивитись»); `searchOffer(source, anime)` (збережене зіставлення → пошук за назвами → `bestAnimeMatch`), `offerFor`, `groupEpisodes`, `titlesOf` / `queriesOf`, `infoOf` (дані Hikka для звірки), `keyOf`. `WatchLoad.defaultGroup(store)` — варіант за кнопкою «Дивитись» (`pickGroup`).

- **MissingNext** (р.23)
- **WatchLoad** (р.36)
  - `addOfferForTest()` р.68
  - `checkOf()` р.70
  - `defaultGroup()` р.79
  - `missingNext()` р.118
- **WatchService** (р.177)
  - `keyOf()` р.187
  - `infoOf()` р.189
  - `titlesOf()` р.196
  - `queriesOf()` р.207
  - `start()` р.217
  - `downloadedOffer()` р.253
  - `searchOffer()` р.292
  - `offerFor()` р.322
  - `groupEpisodes()` р.328

### `lib/services/watch_store.dart` (209 р.)
Що переглянуто й де зупинилися (розділ `watch_store`): `watched` / `isWatched` / `setWatched` / `markUpTo(animeKey, order, upTo)`, `last` / `setLast` (до 400 тайтлів), `recentTitles`, `preferredGroup` / `setPreferredGroup`, зіставлення Hikka ↔ сайт `link` / `setLink`; ChangeNotifier, інʼєкція `load` / `save` для тестів. `favoriteChoices` / `setFavoriteChoice(key)` — озвучки й субтитри (`choiceKeyOf`), які людина свідомо обирала в плеєрі: до 8, найновіші першими.

- **WatchLast** (р.11)
- **WatchStore** (р.19)
  - `reload()` р.45
  - `watched()` р.59
  - `isWatched()` р.61
  - `setWatched()` р.63
  - `markUpTo()` р.75
  - `last()` р.85
  - `setLast()` р.94
  - `recentTitles()` р.115
  - `preferredGroup()` р.153
  - `setPreferredGroup()` р.169
  - `setFavoriteChoice()` р.181
  - `link()` р.195
  - `setLink()` р.200

### `lib/utils/formatters.dart` (220 р.)
Форматування часу/розміру/назв. `formatSpeed` — «1×», «1.25×» (знак множення, як на пігулці плеєра). `translateChapterTitle` запам'ятовує результати (викликається часто).

- **AppFormatters** (р.5)
  - `clearTrackCache()` р.9
  - `formatTime()` р.14
  - `formatSpeed()` р.22
  - `getSpeedIcon()` р.26
  - `cleanMediaTitle()` р.33
  - `translateChapterTitle()` р.65
  - `formatTrackTitle()` р.142

### `lib/utils/platform_info.dart` (46 р.)
Платформа: `AppPlatform.isDesktop` / `isMobile` (+ `debugMobile` для тестів), `isAndroid`, `defaultHwdec`, `mobileScale`, `touchTarget` (48 dp). `AppLayout(Size)` — portrait / landscape, `isCompactWidth` (< 640), `isShortHeight` (< 520).

- **AppPlatform** (р.8)
- **AppLayout** (р.34)

### `lib/widgets/app_animation_kit.dart` (768 р.)
Анімації (AppAnim.*) + AppSmoothScrollController (плавне колесо миші).

- **AppAnim** (р.5)
- **AppFadeSlideSwitcher** (р.17)
- **AppFadeSwitcher** (р.55)
- **AppPresence** (р.95)
- **AppAnimatedContainer** (р.142)
- **AppFade** (р.204)
- **AppRotate** (р.225)
- **AppAnimatedSize** (р.246)
- **AppAnimatedPositioned** (р.267)
- **AppSlideReveal** (р.309)
- **AppAnimatedValue** (р.342)
- **AppDialogs** (р.368)
- **AppVerticalCollapse** (р.387)
- **_AppVerticalCollapseState** (р.405)
- **AppSlideDownCollapse** (р.456)
- **_AppSlideDownCollapseState** (р.474)
- **AppActivePillIndicator** (р.535)
- **AppDialogTransition** (р.567)
- **AppSmoothScrollView** (р.590)
- **_AppSmoothScrollViewState** (р.608)
- **AppSmoothScrollController** (р.703)
  - `createScrollPosition()` р.711
- **_AppSmoothScrollPosition** (р.727)
  - `pointerScroll()` р.747

### `lib/widgets/app_dock_widgets.dart` (627 р.)
Віджети доку: колесо миші над елементом (`AppWheelRegion`), гучність (`AppVolumeControl`: лінійна іконка (клік — вимкнути звук, `volume-mute`) і завжди видимий тонкий білий повзунок `volume-slider`; під курсором потовщується й має кругле «вушко»), смужка прогресу з розділами (`AppSeekBar`: розриви між розділами, жовтий лише прогрес, суцільне жовте «вушко» з м’яким ореолом; власний шар малювання, перемальовується лише при зсуві на піксель, `live`; під курсором `seek-preview` — кадр (локальний файл) у тонкій світлій рамці й під ним «8:40 · Частина А» на темній плашці), `AppClockBuilder` (будує за значенням годинника, лише поки `live`), `AppProgressLine` (тонка смужка прогресу з `PlaybackClock.permille`).

- **AppWheelRegion** (р.17)
- **AppClockBuilder** (р.43)
- **_AppClockBuilderState** (р.54)
- **AppProgressLine** (р.86)
- **AppVolumeControl** (р.124)
- **_AppVolumeControlState** (р.144)
- **_VolumePainter** (р.209)
- **AppSeekBar** (р.245)
- **_AppSeekBarState** (р.277)
- **_SeekPainter** (р.535)

### `lib/widgets/app_media_thumbnail.dart` (116 р.)
AppMediaThumbnail(uri,…) — віджет прев'ю через ThumbnailService.

- **AppMediaThumbnail** (р.10)
- **_AppMediaThumbnailState** (р.40)

### `lib/widgets/settings_kit.dart`
Пласкі рядки налаштувань (без блоків-карток), придатні й для інших екранів: SettingsGroup (підпис + рядки + підказка; від `settingsWideWidth` = 720 підпис і підказка стоять колонкою ліворуч), SettingsRow (`icon`/`leading`, `subtitle` — сірий рядок, `subtitleIsValue`, `below` — вміст під назвою, `highlight` — підсвітка збігу), SettingsToggleRow (+ SettingsSwitch), SettingsRadioRow (радіо-позначка в колонці іконок) / SettingsRadioGroup, SettingsChoiceRow (поточне значення під назвою, `subtitle` — підказка у вікні вибору `showSettingsPicker`), SettingsSliderRow, SettingsPad (відступи для довільного вмісту), SettingsStorageBar (смуга зайнятого місця), SettingsSectionTile (розділ на першому екрані), SettingsTabStrip (доріжка вкладок-пігулок з іконками, активна по центру; ключі `settings-tab-<n>`), SettingsSearchBar, SettingsFont (піддерево з `fontFamilyFallback: kUiFontFallback` — на Android, де немає Arial, текст іде вбудованим `MikiSans` = Liberation Sans із `pubspec.yaml`; полям вводу fallback треба вказати в їхньому стилі). Іконки рядків — Material Symbols `weight: 300`. Підсвітка знайденого: SettingsSpotlight (InheritedWidget: `target`, `seq`, `onShown`) + SettingsSpot (прокручує до себе й блимає акцентом; є в кожному рядку за назвою та в підписі групи). `showSettingsPicker` — вибір значення шторкою (`showAppPicker` з `design_kit.dart`: на телефоні знизу, на ПК вікном; рядки з жовтою галочкою).

Масштаб на телефоні: `StorageService.getPhoneUiScale()` (типово 1.0, 0.8–1.15, не синхронізується) замість `widget.scale`; повзунок «Масштаб налаштувань» у «Вигляді» (`SettingsSliderRow.onChangeEnd`).

### `lib/widgets/design_kit.dart` (1045 р.)
Будівельні блоки нового дизайну для головних вкладок і їхніх вікон (розміри до масштабу, як у концептах): `AppGroupCaption` (сірий підпис групи), `AppLineRow` (плаский рядок: лінійна іконка або `leading`, назва 15, сірий рядок під нею, `trailing` / `value` / `chevron`, `below`, `danger` — червоний, `singleLine`; дотиковий ≥ 48 dp на телефоні), `AppPlate` (м’яка плашка: вибрана світліша з обведенням і жирним текстом; `check` — жовта галочка, `expand`), `AppPillTab` (вкладка-пігулка з іконкою й сірим лічильником; вибрана — жовтий відтінок і обведення), `AppMediaRow` (рядок із картинкою замість іконки: кругле фото, постер, кадр; назва 15 — `bold` для непрочитаного, сірий рядок або `below`, `trailing`/`chevron`, `onLongPress`/`onSecondaryTap`; озвучення, автори, нещодавні файли). Шторки: `showAppSheet(context, scale, title, hint, builder)` — на телефоні знизу (`AppSheetFrame`: ручка, назва з хрестиком `AppSheetClose`, сіра підказка, прокрутка), на ПК — вікно по центру; `AppCheckRow` (рядок вибору з жовтою галочкою; `leading` перед назвою — обкладинка пісні розділу, `trailing` перед галочкою, `padH` / `minHeight` — тісніше меню плеєра), `showAppPicker` (вибір значення шторкою; через нього `showSettingsPicker`). Меню: `showAppMenu(context, scale, anchor, entries, caption/title, width, lift)` — одна темна плитка для всіх випадних меню (`AppMenuEntry` значення/підпис/іконка/`selected`/`danger` або `.divider()`), відкривається під якорем (над ним, якщо внизу тісно); `lift` — картка, піднята над затемненням (довге натискання); `appRectOf(context)` — прямокутник віджета для якоря. `showAppConfirm(context, scale, title, message, action, destructive)` — питання з двома рівними кнопками («Скасувати» сіра, дія жовта або червона), повертає `bool`. `AppRangeStrip(scale, labels, selected, onSelect)` — діапазони довгого серіалу («1–100», «101–200»…) плашками в рядку, що гортається вбік (ключ `episode-ranges`); вибраний сам стає посередині, гортається лише смуга (сторінка тайтла й «Перегляд» у плеєрі).

- **AppGroupCaption** (р.24)
- **AppLineRow** (р.41)
- **AppMediaRow** (р.145)
- **AppPlate** (р.253)
- **AppPillTab** (р.332)
- **AppSheetClose** (р.390)
- **AppSheetFrame** (р.414)
- **_SheetTitle** (р.452)
- **_SheetWindow** (р.484)
- `showAppSheet()` (р.522)
- **AppCheckRow** (р.550)
- `showAppPicker()` (р.626)
- **AppMenuEntry** (р.651)
- `appRectOf()` (р.671)
- `showAppMenu()` (р.682)
- **_AppMenuRoute** (р.703)
- **_MenuPlacement** (р.778)
- **_MenuTile** (р.804)
- `showAppConfirm()` (р.894)
- **AppRangeStrip** (р.972)
- **_AppRangeStripState** (р.984)

### `lib/widgets/app_tones.dart` (59 р.)
`AppTones` — кольори нового дизайну, яких немає в темі: `plate` / `plateOn` / `plateOutline` / `plateText` (м’які плашки), `menu` / `menuLine` / `menuIcon` (плитка меню), `caption` (підписи груп), `rowSub`, `rowIcon`, `chevron`, `danger` / `dangerPlate` / `dangerText`, `track` (доріжка смужки прогресу), `dot` (неактивна крапка, ручка шторки), `playCircle`, `accentWash`; для світлої теми — свої відповідники.

- **AppTones** (р.8)

### `lib/widgets/line_icons.dart` (217 р.)
`LineIcon` — лінійні іконки з SVG-контурів концептів (сітка 24, круглі кінці): блок «Дивитись» і «Перегляд» (mic, subtitles, warning, list, hd, monitor, sliders, groups, openOut, refresh, clock, chevronRight, close, back, check, play), навігація (home, search, bookmark, person) і головні вкладки (bell, chevronDown, chevronUp, grid, rows, calendar, stack, doc, face, gear, folder, arrowUp, comment, heart, trash, star, minus, plus, logout, sync, info, link, send, login, eye), сторінки (pin, megaphone, download, checks, history, playlist), плеєр (pause — заповнений, pictureInPicture, rotate, skipPrevious, skipNext, replay, forward, sparkle, musicNote, volume, volumeLow, volumeOff, fullscreen, fullscreenExit, speed, chapters, skipForward, chip, chart, repeat, grip). `LineIconView(icon, size:, color:, stroke: 1.6)` (галочка меню — `stroke: 2`), `parseSvgPath` (M L H V A C S Z, абсолютні й відносні).

- **LineIcon** (р.5)
- **LineIconView** (р.101)
- **_LinePainter** (р.116)
- `parseSvgPath()` (р.149)

### `lib/widgets/downloads/download_kit.dart` (224 р.)
Спільні дрібниці завантажень: `DownloadText` (`status` — «45 % · 120 з 300 МБ · 2 МБ/с», «У черзі», причина очікування; `amount`, `episodes`), `downloadsSummary` (рядок «Профілю»), `DownloadPlateMark` (стрілка в куті плашки серії / смужка прогресу / жовта крапка збою), `DownloadRing` (кругла кнопка з прогресом: пауза / продовжити / повторити).

- **DownloadText** (р.16)
  - `episodes()` р.19
  - `amount()` р.22
  - `status()` р.31
- `downloadsSummary()` (р.61)
- **DownloadPlateMark** (р.87)
- **DownloadRing** (р.141)
- **_RingPainter** (р.186)

### `lib/widgets/downloads/download_picker.dart` (461 р.)
«Завантажити серії» (шторка на телефоні, вікно на ПК): `DownloadPicker.show(context, …, group, watched, from)` — наступні 3 / усі непереглянуті / усі / вручну (плашки, як у «Перегляді», діапазони по 100 для довгих серіалів), якість, орієнтовний розмір (`estimate`) і вільне місце, коли почнеться (Wi-Fi, офлайн); `ranges` — «1–3, 5, 8–9».

- **_Pick** (р.29)
- **DownloadPicker** (р.31)
  - `show()` р.39
  - `ranges()` р.79
  - `estimate()` р.103
- **_PickerBody** (р.117)
- **_PickerBodyState** (р.140)

### `lib/widgets/downloads/downloads_page.dart` (957 р.)
`DownloadsPage` (черга з `DownloadRing` і причиною очікування, «На пристрої» з «Продовжити · серія N», місце `SettingsStorageBar`, налаштування завантажень рядками з перемикачами, «Видалити всі завантаження»), `DownloadShelfPage` (тайтл + озвучка: «Продовжити», «Завантажити ще серії», серії з розміром і кошиком, «Видалити всі серії»), `DownloadsHomeShelf` + `DownloadContinueCard` (полиця «Завантажене» на «Головній»), `OfflineStrip` (смужка «Немає інтернету» з «Завантажене»), `downloadsStart`, `playDownloaded`.

- `playDownloaded()` (р.54)
- **DownloadsPage** (р.59)
- **_DownloadsPageState** (р.73)
- **_ContinueChip** (р.489)
- **DownloadShelfPage** (р.532)
- **_DownloadShelfPageState** (р.544)
- **DownloadsHomeShelf** (р.784)
- **DownloadContinueCard** (р.817)
- **OfflineStrip** (р.903)

### `lib/widgets/hikka/hikka_list_sheet.dart` (253 р.)
`showHikkaListSheet(context, anime:, scale:)` — «Мій список» шторкою (на ПК вікно; гостя веде до входу): «Статус» плашками зі значками `HikkaListMark` (ключі `list-status-<name>`), «Перегляд» (лише коли тайтл у списку): «Серії» кроками −/+ (зберігаються разом за 600 мс після останнього дотику; семантика «Менше серій» / «Більше серій»), «Оцінка» плашками 1–10 (`list-score-N`, повторний дотик скидає), «В улюблене» перемикачем, червоне «Видалити зі списку» (закриває шторку). Усе зберігається одразу через `HikkaMyList`, помилка мережі — червоним рядком у шторці. Вміст — `HikkaListSheetBody`.

- `showHikkaListSheet()` (р.22)
- **HikkaListSheetBody** (р.31)
- **_HikkaListSheetBodyState** (р.41)

### `lib/widgets/hikka/hikka_continue_card.dart` (146 р.)
`HikkaContinueCard(item, scale)` — картка «Продовжити перегляд» 262×96 (×scale): мініатюра 56×80, назва у два рядки, «Серія N з M · озвучка», рядок «Нова серія» / «Не в списку», сіра кругла кнопка ▶ (під час запуску — коло), тонка жовта смужка переглянутого внизу. Дотик — `QuickPlay.resume` (або сторінка тайтла), довге натискання — `showHikkaCardMenu` («Відкрити», «Мій список…», «Прибрати з «Продовжити»»).

- **HikkaContinueCard** (р.21)
  - `width()` р.28
  - `height()` р.29
- **_HikkaContinueCardState** (р.35)

### `lib/widgets/settings_search.dart` (138 р.)
Пошук налаштувань: `settingsSearchIndex` (SettingsSearchEntry: вкладка, група, назва як на екрані, іконка, `keywords`, `spot` — що підсвітити, якщо рядок прихований, `when` — платформа), `searchSettings(query)` (початок назви → входження → група/ключові слова; ґ = г), `settingsResultsLabel(n)`. Тест `test/settings_search_test.dart` перевіряє, що кожен запис є на своїй вкладці — при додаванні чи перейменуванні рядка онови індекс.

- **SettingsSearchEntry** (р.10)
- `searchSettings()` (р.106)
- `settingsResultsLabel()` (р.129)

### `lib/widgets/app_settings_dialog.dart` (2295 р.)
Діалог налаштувань. Вкладки (`_tabs`): Вигляд, Субтитри, Каталог, Відтворення, Відео & GPU, Anime4K, Звук, Гарячі клавіші (лише ПК), Розробник, Про програму; чернетка з «Скасувати» / «Скинути» / «Застосувати». «Розробник»: секція «Журнал і діагностика» (`_setDetailedLog`, `_saveLogToFile` → `LogExport.save`, `_clearLogs`, `_buildLogStatusLine`); «Відтворення»: «Орієнтація плеєра» лише на телефоні (`_playerOrientation`, у знімку змін). `tabDeveloper` (5) / `tabAbout` (6) / `tabCatalog` (9) — відкрити відразу на потрібній вкладці; «Розробник» → «Приховані можливості» (перемикач «Локальна медіатека») і «Банери на головній» (ключ TheMovieDB, `_tmdbKey`); «Про програму» бере назву, версію й збірку з `AppIdentity` / `AppDiagnostics.build` і називає джерела (Hikka, AniList, TheMovieDB).

- **AppSettingsDialog** (р.38)
  - `show()` р.62
- **_AppSettingsDialogState** (р.78)

### `lib/widgets/app_ui_kit.dart` (2918 р.)
UI KIT: AppPressable (підсвітка при натисканні поверх будь-якого фону), AppOverlayButton, AppPanelSurface/Header (у стилі шторок застосунку: колір сторінки, тонка лінія; заголовок жирний з лінійними «Назад» / «Закрити», 48 dp на телефоні), AppSelectableSurface, AppSelectableTile (з необов'язковими subtitle/trailing), AppSecondaryButton, AppEmptyState, AppModalShell, AppSidebar, AppNavItem, AppPaneHeader, AppSectionHeader (`titleSize`), AppAccentButton (`compact` — головна кнопка сторінки тайтла: 44, радіус 14, текст `onAccent(accent)`; `leading` — свій малюнок замість іконки), AppCard, AppStatTile, AppKeyCap / AppKeyCombo (кнопки клавіатури), AppSearchField, AppScrollEdgeFade, AppScrollbar + базові віджети. Нові UI будувати з цього. На телефоні сегменти `AppSegmentedBar` ≥ 48 dp, `AppOverlayButton` має `onLongPress`. `AppSearchField(icon:)` — з іншою іконкою й підказкою це звичайне однорядкове поле (ключ API). `AppSectionHeader(calm:)` — підпис нового дизайну (12,5, сірий). Випадні списки `AppDropdown` / `AppSearchDropdown` — спільна темна плитка (`appMenuTileDecoration`, `appMenuText`: вибране жирним із жовтою галочкою праворуч).

- **EdgeToEdgeSliderTrackShape** (р.14)
  - `getPreferredRect()` р.16
- **DotSliderThumbShape** (р.31)
  - `getPreferredSize()` р.41
- **DotRangeSliderThumbShape** (р.72)
  - `getPreferredSize()` р.79
- **AppSegmentOption** (р.101)
- **AppSegmentedBar** (р.107)
- `appMenuTileDecoration()` (р.190)
- `appMenuText()` (р.198)
- **AppDropdownOption** (р.206)
- **_OptionBody** (р.225)
- **AppDropdown** (р.274)
- **_AppDropdownState** (р.296)
- **AppSearchDropdown** (р.430)
- **_AppSearchDropdownState** (р.472)
  - `didChangeMetrics()` р.497
- **AppLanguagePriorityList** (р.818)
- **_AppLanguagePriorityListState** (р.834)
- **AppDragHandle** (р.1160)
- **AppRowIconButton** (р.1189)
- **AppSelectableTile** (р.1226)
- **AppOverlayButton** (р.1341)
  - `foreground()` р.1374
- **_AppOverlayButtonState** (р.1380)
- **AppPanelSurface** (р.1466)
- **AppPanelHeader** (р.1510)
- **AppSelectableSurface** (р.1575)
- **AppSecondaryButton** (р.1637)
- **AppEmptyState** (р.1715)
- **AppMenuRow** (р.1750)
- **AppModalShell** (р.1819)
- **AppSidebar** (р.1863)
- **AppNavGroupLabel** (р.1903)
- **AppNavItem** (р.1927)
- **AppPaneHeader** (р.2010)
- **AppSectionHeader** (р.2092)
- `onAccent()` (р.2149)
- **AppAccentButton** (р.2152)
- **AppCard** (р.2238)
- **AppStatTile** (р.2284)
- **AppKeyCap** (р.2360)
- **AppKeyCombo** (р.2401)
- **AppSearchField** (р.2425)
- **_AppSearchFieldState** (р.2447)
- **AppScrollEdgeFade** (р.2546)
- **AppScrollbar** (р.2587)
- **AppScrollBehavior** (р.2599)
  - `buildOverscrollIndicator()` р.2607
- **AppHeaderInset** (р.2616)
  - `of()` р.2625
  - `maybeOf()` р.2628
  - `updateShouldNotify()` р.2631
- **AppPullToRefresh** (р.2634)
- **_AppPullToRefreshState** (р.2646)
- **_LockPhysics** (р.2800)
  - `applyPhysicsToUserOffset()` р.2814
  - `createBallisticSimulation()` р.2822
- **_TopEdgeToRefreshBehavior** (р.2829)
  - `buildScrollbar()` р.2839
  - `getScrollPhysics()` р.2842
  - `buildOverscrollIndicator()` р.2848
- **AppPressable** (р.2868)
- **_AppPressableState** (р.2879)

### `lib/widgets/bottom_dock.dart` (330 р.)
Нижня панель плеєра на ПК (концепт П5): `AppSeekBar` на всю ширину, під ним ліворуч пауза (`dock-play`), попередня, наступна (з налаштуванням «Кнопки перемотки» ще ±N с), гучність (`AppVolumeControl`), «8:12 / 24:00» (`dock-time`, коробка за довжиною тривалості) і «· Частина А» (`dock-chapter`, клік — розділи; на вузькому вікні прихована); праворуч Anime4K (крапка — увімкнено; клік — меню, права кнопка — перемкнути), субтитри (крапка — увімкнено), звук, «1×» (`PlayerPill(plain)`, жовта, коли меню відкрите або швидкість не 1×; права кнопка — наступна швидкість), «Серії» (`dock-episodes`, вузьке вікно — лише значок), міні-плеєр, повний екран. Ключі `anime4kKey` / `subsKey` / `audioKey` / `speedKey` / `volumeKey` — прив’язка меню до кнопок. Дуже вузьке вікно — ряд стискається цілим (`FittedBox`). `live` (false — панель прихована: час, прогрес і розділ не стежать за відтворенням); `volume` — `ValueListenable<VolumeState>`. Параметри `onPrevious` / `onNext` (типово — `player.previous/next`; для серій із сайту їх задає `PlayerStateController.playPrevious/playNext`).

- **BottomDock** (р.15)
- **_BottomDockState** (р.91)

### `lib/widgets/center_flash.dart` (74 р.)
`CenterFlash` — коротка (650 мс) велика іконка пауза/пуск посередині відео при зміні стану відтворення (замість постійних центральних кнопок): те саме напівпрозоре коло, що пауза в керуванні (`PlayerTones.circleBig`, лінійний знак), ключ `center-flash`.

- **CenterFlash** (р.10)
- **_CenterFlashState** (р.20)

### `lib/widgets/center_hub.dart` (78 р.)
Центральні кнопки play/seek.

- **CenterHub** (р.6)

### `lib/widgets/collapsed_player.dart` (179 р.)
Згорнутий плеєр (смужка внизу вікна): підпис часу й тонка смужка прогресу з `PlaybackClock`. `width` — на телефоні в портреті картка на всю ширину.

- **CollapsedPlayer** (р.14)

### `lib/widgets/controls_overlay.dart` (250 р.)
Збирає top/bottom/center + випадні меню (settings/subs/audio/speed/Anime4K/quality). Прихована панель передає в док `live:false`; гучність — `volume: ValueListenable<VolumeState>`. Передає `onPrevious` / `onNext` у `BottomDock`, `currentSubtitle` у `TopDock`; у `SettingsDrawer` — необовʼязкові `onAddSubtitleFile`, `onOpenAppSettings` («Усі налаштування») і `remote` (якість серій із сайтів).

- **ControlsOverlay** (р.12)

### `lib/widgets/frosted_tile.dart` (84 р.)
Застаріла «скляна» плитка (майже не використовується).

- **FrostedTile** (р.4)

### `lib/widgets/hikka/hikka_account_ui.dart` (235 р.)
`HikkaLoginDialog.show(context, scale:)` — вікно входу (одразу запускає `HikkaAuth.startLogin()`; стани «Чекаю на підтвердження…» / «Завершую вхід…» / помилка з «Спробувати ще раз»; без локального порту або за кнопкою «Не спрацювало? Вставити адресу» — поле для адреси чи коду; «Відкрити знову»; закривається саме після входу, закриття вікна скасовує вхід). `HikkaLoginButton(scale)` — одна жовта кнопка «Увійти через Hikka» (гість у «Списках» і «Профілі»).

- **HikkaLoginDialog** (р.23)
  - `show()` р.29
- **_HikkaLoginDialogState** (р.38)
- **HikkaLoginButton** (р.197)

### `lib/widgets/hikka/hikka_airing_strip.dart` (161 р.)
Рядок «сьогодні» на «Головній»: `HikkaAiringStrip` вантажить розклад (`limit` 24), `HikkaTodayRow` — тихий рядок (`today-row`: годинник, «назва · серія N», «Сьогодні о 10:00 · ще N серій до кінця дня» / «Завтра о …», шеврон; дотик відкриває «Календар»). `HikkaTodayRow.pick(entries, now)` (серія цієї години → найближча → остання) і `subtitleOf` — чиста логіка з тестами; `HikkaAiring.of(entry, now)` → `text` + `live` (лишився для календаря й тестів).

- **HikkaAiring** (р.14)
  - `isCurrent()` р.26
  - `of()` р.31
- **HikkaAiringStrip** (р.46)
- **HikkaTodayRow** (р.75)
  - `pick()` р.84
  - `subtitleOf()` р.95
- **_StripSkeleton** (р.131)

### `lib/widgets/hikka/hikka_anime_characters_page.dart` (94 р.)
Усі персонажі аніме сіткою з підвантаженням: над нею `HikkaLeadLine` (назва тайтлу · кількість), сірі підписи груп «Головні · N» / «Другорядні · N» (`_sectionOf`), картки без сірого рядка (`subtitle: false`).

- **HikkaAnimeCharactersPage** (р.15)
- **_HikkaAnimeCharactersPageState** (р.26)

### `lib/widgets/hikka/hikka_anime_page.dart` (799 р.)
Сторінка аніме: шапка зі списку одразу, повні дані з API; постер, назви, статус, жанри (→ каталог із жанром), оцінки MAL / Hikka, згортуваний опис, таблиця інформації, полиці персонажів / франшизи / рекомендацій, автори, посилання (дивитись — першими), відео, музика; заглушка 18+. `_wideLayout` (ширина ≥ `hikkaWideBreakpoint`) вирішує розкладку для шапки й секцій. ПК / телефон боком: постер з «Інформацією» ліворуч, праворуч назва, `_scores`, «Дивитись», жанри, опис. Телефон (`_phoneTop`, за дизайном; уся сторінка в `SettingsFont`): `HikkaTitleBackdrop(soft: true)` від верху екрана до «рядок стану + 120», постер 128×180 (×scale) з «рядок стану + 24», назва 21, друга назва 13, `_phoneGenres` (плашки 32), кнопка, `_phoneSynopsis` (15 / 13, `HikkaMarkdownView(maxLines: 4)`, дотик — `memo['synopsis']`), «Персонажі» (`HikkaCharacterCard(plain)` 84×118, `calm`), `_phoneInfo` («Інформація» з оцінками MAL / Hikka — `_info(scores: true)`), далі полиці із заголовком 15 (`_headSize`). Закладка списку `_bookmark` → `HikkaMyListBar` на куті банера (`floatingButtonInset/Top` — на одній висоті з «Назад» хабу).

- **HikkaAnimePage** (р.28)
- **_HikkaAnimePageState** (р.39)
- **HikkaLinksDialog** (р.737)
- **_OstCard** (р.767)

### `lib/widgets/hikka/hikka_article_page.dart` (252 р.)
`HikkaArticlePage(scale, route, pad)` — стаття: «категорія · дата» сірим, назва 22, `HikkaAuthorLine` з лічильниками праворуч, тайтл статті тихою карткою `_AnimeLink` (`article-anime`, коли є `HikkaArticle.content`), текст — лінивий список шматків `HikkaSlateView.pieces` у `HikkaPageFrame.itemBuilder` (довга стаття не будує всіх абзаців і картинок одразу), останнім — теги плашками; шапка зʼявляється одразу з `route.seed`, повний текст вантажиться окремо (`HikkaApi.article`).

- **HikkaArticlePage** (р.20)
- **_HikkaArticlePageState** (р.31)
- **_AnimeLink** (р.181)

### `lib/widgets/hikka/hikka_articles_page.dart` (134 р.)
`HikkaArticlesPage` — розділ «Статті»: категорії круглими плашками `AppPlate` (Усі · Новини · Огляди · Авторські, ключі `articles-category-<key|all>`), порядок `HikkaSortLine` («Спершу нові» / «Спершу найкращі»), `HikkaPagedList(flush)` із `HikkaArticleRow`.

- **HikkaArticlesPage** (р.16)
- **_HikkaArticlesPageState** (р.27)

### `lib/widgets/hikka/hikka_banner.dart` (482 р.)
`HikkaBannerCarousel(items, scale, pad, autoAdvance = 7 с, artLoader)` — банери поточних онґоїнґів (`_Banner`): широке світле зображення (`_WideBackdrop` із TMDB / AniList; без нього — постер на всю картку, щойно відомо, що банера немає: `_artKnown`) під затемненням донизу, сезон і вийшла серія, назва 20, одна жовта «Дивитись» і оцінка сірим; на телефоні один банер на всю ширину з полями сторінки (`HikkaBannerCarouselMetrics.phoneHeight` = 198×scale), на широкому вікні — банер фіксованої ширини з сусідами (`heightFor`); самогортання таймером (дотик зупиняє; не крутиться у фоні, прокрученим за межі сторінки — `_onScreen` — і під відкритим вікном), крапки `_Dots` (активна — жовта довша). `HikkaBannerArtLoader` (у тестах підміняється). `HikkaTitleBackdrop(soft:)` — тло сторінки тайтла.

- **HikkaBannerCarouselMetrics** (р.22)
  - `heightFor()` р.26
  - `phoneHeight()` р.29
- **HikkaBannerCarousel** (р.39)
- **_HikkaBannerCarouselState** (р.61)
- **_Dots** (р.234)
- **_Banner** (р.265)
- **_WideBackdrop** (р.379)
- **HikkaTitleBackdrop** (р.408)
- **_HikkaTitleBackdropState** (р.422)

### `lib/widgets/hikka/hikka_cards.dart` (501 р.)
Картки: `HikkaAnimeCard(anime, scale, caption, progress, onTap, onRemove, removeLabel, seen)` — чистий постер (радіус 12, 18+ у куті, `progress` 0…1 — тонка жовта смужка `HikkaProgressBar` унизу), назва у два рядки (13) і сірий рядок `HikkaMetaLine` («рік · ★ оцінка» — `metaOf`; «TV Серіал · 2023» — `typeYearOf`; «★» малюється лінійною зіркою). Довге натискання піднімає картку й відкриває `showHikkaCardMenu` (назва тайтла, «Продовжити · серія N», коли почато, інакше «Відкрити»; «Мій список…» → шторка; `removeLabel` червоним за `onRemove`), права кнопка — те саме меню біля курсора. `hikkaSeenEpisodes(a)` — більше з лічильника списку й локальних позначок; `hikkaContinue(context, a, scale)` — `QuickPlay.resume` або сторінка тайтла. `HikkaCharacterCard` (портрет радіусом 12, ім’я 13 звичайним шрифтом, сірий рядок 12 — аніме ролі; `plain` — портрет 84×118 і лише ім’я), `HikkaPersonCard`, `HikkaAnimeRow` (рядок франшизи: постер 52×74, сіра роль над назвою, назва 15, «тип · сезон · серії · ☆ оцінка»; `highlighted` — рамка й «Ви тут», ключ `franchise-here`).

- `hikkaSeenEpisodes()` (р.22)
- `hikkaContinue()` (р.34)
- `showHikkaCardMenu()` (р.45)
- **HikkaMetaLine** (р.96)
- **HikkaAnimeCard** (р.135)
  - `metaOf()` р.166
  - `typeYearOf()` р.172
- **HikkaProgressBar** (р.254)
- **HikkaCharacterCard** (р.281)
- **HikkaPersonCard** (р.333)
- **HikkaAnimeRow** (р.383)

### `lib/widgets/hikka/hikka_catalog_page.dart` (247 р.)
Вкладка «Аніме» (розділ «Каталог» в «Огляді»): пошук із паузою 450 мс, підсумок («Оцінка MAL ↓ · N знайдено») і кнопка фільтрів `HikkaLineButton` (жовта крапка, коли вибрано), сітка з підвантаженням, панель фільтрів із лічильником (`countOf` → `HikkaApi.searchAnime(size: 1)`; охоронець «Назад» її закриває). `search` / `searchFocus` — поле «Огляду» (тоді власного поля немає, а підсумок із фільтром стоять рядком); пошукова панель «Головної» (`HikkaNav.openSearch`) ставить курсор у поле (`HikkaNav.takeFocusSearch`); панель фільтрів закривається, коли людина йде з розділу.

- **HikkaCatalogPage** (р.21)
- **_HikkaCatalogPageState** (р.36)

### `lib/widgets/hikka/hikka_character_page.dart` (308 р.)
Сторінка персонажа: портрет 112×158 і імена, тихі лічильники «5 аніме» / «6 озвучень» (`hikkaCountLine`), опис `HikkaSynopsis`, «Озвучення» — рядки `AppMediaRow` з фото, мовою й кількістю аніме (`HikkaCharacterVoice.actors`, ключі `voice-<slug>-<мова>`; дотик → `openPerson(roles: true)`), аніме персонажа сіткою з підписом «Головна / Другорядна · рік».

- **HikkaCharacterPage** (р.20)
- **_HikkaCharacterPageState** (р.31)

### `lib/widgets/hikka/hikka_characters_page.dart` (129 р.)
Розділ «Персонажі»: пошук за іменем (пауза), без запиту — найпопулярніші (сірий рядок над сіткою «Найпопулярніші» / «Знайдено N»); картки лише з іменем (`subtitle: false`); `search` — поле «Огляду» (тоді власного поля немає).

- **HikkaCharactersPage** (р.16)
- **_HikkaCharactersPageState** (р.30)

### `lib/widgets/hikka/hikka_collection_page.dart` (401 р.)
`HikkaCollectionPage(scale, route, pad)` — колекція: назва 22, `HikkaAuthorLine`, лічильники `HikkaStat`, позначки й теги сірим, опис `HikkaSynopsis`; рядок «N тайтлів» із перемикачем «Сіткою / Списком» (`memo['rows']`; без вибору — списком, якщо автор писав коментарі); записи рядками (`_EntryRow`: постер 52×74, назва, тип · сезон · ☆ оцінка, коментар `HikkaSynopsis` на три рядки) або сіткою постерів; групи записів — окремими блоками; колекція 18+ закрита заглушкою «Контент 18+ прихований» (кнопка показу діє лише для цієї колекції — `_revealed`), поки вимкнено `allowAdult`.

- **HikkaCollectionPage** (р.22)
- **_HikkaCollectionPageState** (р.33)
- **_EntryRow** (р.323)

### `lib/widgets/hikka/hikka_collections_page.dart` (97 р.)
`HikkaCollectionsPage` — розділ «Колекції»: порядок тихим рядком `HikkaSortLine` («Популярні» / «Нові», ключ `collections-sort`), `HikkaPagedList(flush)` із `HikkaCollectionRow`.

- **HikkaCollectionsPage** (р.15)
- **_HikkaCollectionsPageState** (р.26)

### `lib/widgets/hikka/hikka_common.dart` (1414 р.)
Спільні будівельні блоки каталогу: `HikkaLayout` (розміри, `compact`), круглі кнопки над банером сторінки тайтла (`floatingButtonSize` 40×scale на телефоні, `floatingButtonHit` ≥ 48, `floatingButtonInset`, `floatingButtonTop` — 8 під рядком стану), `HikkaPoster`, `HikkaAvatar(url, size, scale)` (кругле фото людини чи автора; без фото — сіре коло з силуетом), `HikkaAsync` (завантаження → вміст / помилка з «Повторити»), `HikkaLoading`, `HikkaErrorView`, `HikkaChip`, `HikkaPill`, `HikkaLinkButton` (`calm` — сірий і низький), `HikkaIconButton`, `HikkaLineButton` (кругла кнопка з лінійною іконкою для заголовків вкладок; `dot` — жовта крапка, `dotKey`), `HikkaBackBar` (смуга відкритої сторінки: лінійна «Назад», назва 17 на телефоні, дії праворуч — `HikkaLineButton`), `HikkaPagedGrid` (сітка з підвантаженням; картки, вже зроблені `itemBuilder` цього віджета, повертаються як є, а сліви — поки ті самі елементи й розміри: нова сторінка чи індикатор унизу не перебудовують видимі картки; `header`, `empty` — свій порожній стан, `subtitle: false` — картки лише з назвою, `sectionOf` — сірі підписи груп «Головні · 3»), `HikkaToggleRow`, `HikkaInfoTable`, `HikkaSearchPill` (кнопка-пошук 44, лінійна лупа, сіра підказка), `HikkaSearchField` (справжнє поле в тій самій плашці; лупа жовтіє під час набору, хрестик очищає; `onTap`), `HikkaSearchBar` (поле + кнопка праворуч), `hikkaStyle(...)`, `hikkaCardTextHeight` (назва 13 у два рядки + сірий рядок 12).

- **HikkaLayout** (р.20)
  - `compact()` р.24
  - `sidePad()` р.28
  - `barHeight()` р.34
- `floatingButtonSize()` (р.40)
- `floatingButtonHit()` (р.43)
- `floatingButtonInset()` (р.46)
- `floatingButtonTop()` (р.50)
- `hikkaStyle()` (р.54)
- **HikkaPoster** (р.66)
- **HikkaAvatar** (р.161)
- **HikkaAsync** (р.186)
- **_HikkaAsyncState** (р.220)
- **HikkaLoading** (р.272)
- **HikkaErrorView** (р.295)
  - `messageOf()` р.303
- **HikkaChip** (р.340)
- **HikkaPill** (р.427)
- **HikkaLinkButton** (р.455)
- **HikkaIconButton** (р.510)
- **HikkaLineButton** (р.557)
- **HikkaBackBar** (р.624)
- **HikkaGridDelegate** (р.683)
  - `getLayout()` р.701
- `hikkaCardTextHeight()` (р.725)
- **HikkaCardSkeleton** (р.733)
- `hikkaSkeletonBar()` (р.765)
- **HikkaListSkeleton** (р.771)
- **HikkaPagedGrid** (р.839)
- **_HikkaPagedGridState** (р.887)
- **HikkaToggleRow** (р.1078)
- **HikkaInfoTable** (р.1145)
- **HikkaSearchPill** (р.1229)
- **HikkaSearchField** (р.1274)
- **_HikkaSearchFieldState** (р.1290)
- **HikkaSearchBar** (р.1382)

### `lib/widgets/hikka/hikka_community_cards.dart` (420 р.)
Картки спільноти: `HikkaCollectionFanCard` (віяло з трьох постерів на всю ширину темної картки 232 — постер 86 завширшки, крок 61, ключі `fan-<i>`; менше трьох — по центру, без жодного — заглушка; назва, «@автор · N тайтлів», голоси й коментарі сірим; «Огляд» → «Усе»), `HikkaArticleRow` (стаття рядком: категорія · дата, назва у два рядки, автор із лічильниками, обкладинка праворуч), `HikkaCollectionRow` (колекція рядком: віяло з трьох постерів 52×74, назва, «@автор · N тайтлів», голоси й коментарі), `HikkaAuthorLine(author, date, scale, trailing)` (аватар 26, «@ім’я · дата», дотик → профіль автора), `HikkaStat` (лінійна іконка `LineIcon` + число сірим, `HikkaText.compact`; підказка `Tooltip` лише на ПК, на телефоні — `Semantics`), `HikkaChipRow` (рядок міток, що гортається вбік; `selectedIndex` — вибрана сама прокручується в поле зору).

- **HikkaStat** (р.16)
- **HikkaChipRow** (р.45)
- **_HikkaChipRowState** (р.56)
- **HikkaAuthorLine** (р.110)
- **HikkaCollectionFanCard** (р.169)
  - `width()` р.183
  - `height()` р.184
- **HikkaCollectionRow** (р.272)
- **HikkaArticleRow** (р.357)

### `lib/widgets/hikka/hikka_discover_page.dart` (232 р.)
`HikkaDiscoverPage(scale, bottomInset, onRefresh)` — вкладка «Огляд»: заголовок «Огляд» із підписом, одне поле пошуку `HikkaSearchField` для всієї вкладки (`_search`: у «Каталозі» шукає аніме, у «Персонажах» — персонажів; в інших розділах дотик веде до «Каталогу» з курсором; контролери й фокус живуть тут і передаються в `HikkaCatalogPage` / `HikkaCharactersPage`, підказка — `searchHint(tab)`), вкладки-пігулки `AppPillTab` з лінійними іконками (`lineIconOf`) у порядку `HikkaDiscoverPage.order` (Усе, Календар, Колекції, Статті, Каталог, Персонажі; у цьому ж порядку свайп), вміст розділу (`_sections`); відкриті розділи не руйнуються (і не перебудовуються: `_section` кешує їх за масштабом, відступом і оновленням); сторінка слухає `HikkaNav`, але перебудовується лише при зміні розділу (`_shownTab`) — не на кожне відкриття сторінки чи перемикання головних вкладок; потяг вниз оновлює. `iconOf` (Material) лишився для інших місць.

- **HikkaDiscoverPage** (р.21)
  - `iconOf()` р.31
  - `lineIconOf()` р.41
  - `searchHint()` р.55
- **_HikkaDiscoverPageState** (р.65)

### `lib/widgets/hikka/hikka_filter_sheet.dart` (497 р.)
Панель фільтрів: сортування (напрямок — написом «за спаданням ⌄» біля назви групи), тип, статус виходу, сезон, роки (повзунок із білими ручками й підписами кінців), жанри, оцінка, вікова категорія, «лише з перекладом»; круглі плашки (36, вибрана світліша з жовтою галочкою), що переносяться в рядки. `title` («Сортування й фільтри» у списках), `countOf(filters)` — кнопка «Показати N тайтлів» (рахує за 500 мс після останньої зміни; без лічильника — «Показати результати»; число — `ValueNotifier`, відповідь перебудовує лише кнопку). «Скинути» з’являється, коли щось змінено. На ПК бічна панель, на телефоні — `MobileSheetFrame`.

- **HikkaFilterSheet** (р.19)
- **_HikkaFilterSheetState** (р.56)
- **_ShowButton** (р.450)

### `lib/widgets/hikka/hikka_franchise_page.dart` (210 р.)
Франшиза: сірий підсумок «N тайтлів · основна історія: M» (`HikkaLeadLine`), «За роками» / «За групами» круглими плашками `AppPlate` (`franchise-mode-years/groups`), роки й групи сірими підписами, рядки `HikkaAnimeRow` (поточний — у рамці з «Ви тут»), 18+ вузли приховано. Підписи й рядки — шматками лінивого списку (`_byYears` / `_byGroups` → `HikkaPageFrame.itemBuilder`).

- **HikkaFranchisePage** (р.18)
- **_HikkaFranchisePageState** (р.29)

### `lib/widgets/hikka/hikka_home_page.dart` (259 р.)
`HikkaHomePage(scale, bottomInset, onRefresh)` — «Головна»: `_TopBar` (`HikkaSearchPill` «Пошук аніме…» → `HikkaNav.openSearch`, «Оновити» на ПК, дзвіночок `HikkaLineButton` з жовтою крапкою `bell-badge`, коли є непрочитані → `HikkaNav.openNotifications`), `HikkaBannerCarousel` (скелет `_BannerSkeleton`), рядок «сьогодні» `HikkaAiringStrip`, полиці «Продовжити перегляд» (`ContinueWatching.load`, порожню не показує), «Рекомендації», «Зараз виходить», «Анонси», «Найпопулярніші», «Найкращі за оцінкою» (сірий «Усі ›» → `HikkaNav.openCatalog` з готовими умовами); кожна полиця завантажується окремо (`HikkaShelfAsync`) і має «Повторити».

- **HikkaHomePage** (р.29)
- **_HikkaHomePageState** (р.48)
- **_TopBar** (р.190)
- **_BannerSkeleton** (р.234)

### `lib/widgets/hikka/hikka_hub.dart` (438 р.)
`HikkaHub(scale, onOpenSettings, localLibraryBuilder, bottomInset)` — вміст застосунку: чотири головні вкладки (`_root(MainTab)`: `HikkaHomePage` / `HikkaDiscoverPage` / `HikkaListsPage` / `HikkaProfilePage`; ліниво, у `Offstage` + `TickerMode`, `_mounted`) і шар відкритих сторінок (`_page(HikkaRoute)`: аніме, персонаж, франшиза, персонажі аніме, колекція, стаття, локальна медіатека, адмін-панель; `_local(r)` — сторінки самого застосунку (медіатека, налаштування, адмін-панель): звичайна смуга «Назад» без «Оновити», без потягу вниз) з плавною зміною (`AppFadeSwitcher`) і `HikkaBackBar` (`_routeTitle` / `_routeUrl`, лише назва розділу без другого рядка; лінійні «Оновити» → `_refreshRoute` (ПК) і «Відкрити на hikka.io»; для локальної медіатеки без цих дій). `_refreshAll` / `_pullRefresh` перезавантажують вкладки (`_refresh`), `_cachedRoot` — сторінки вкладок кешуються за `_rootKey` (масштаб, відступ, оновлення, налаштування каталогу, тема): відкриття сторінки чи перемикання вкладок не перебудовують приховані вкладки. `_forget` скидає запам'ятований стан сторінки (розкрите 18+ лишається — `memo['revealed']`), `_openCatalogSettings` → `HikkaSettingsDialog`. Мишача кнопка «Назад». На сторінці тайтла на телефоні (`HikkaNav.immersive`) — кругла «Назад» `_floatingBack` (коло `floatingButtonSize`, дотик `floatingButtonHit`) і смуга під годинником, що проявляється з прокруткою (`_immersiveScroll` з `ScrollMetricsNotification`/`ScrollUpdateNotification`).

- **HikkaHub** (р.34)
- **_HikkaHubState** (р.62)

### `lib/widgets/hikka/hikka_lists_page.dart` (749 р.)
`HikkaListsPage` — вкладка «Списки». Гість: талісман, «Увійдіть через Hikka», одна жовта `HikkaLoginButton`, «Що з’явиться після входу» рядками (`HikkaListsPage.planned`). Після входу: заголовок з ім’ям і кнопкою фільтрів (жовта крапка, коли змінено), вкладки-пігулки `AppPillTab` зі значками `HikkaListMark` і сірими лічильниками (`HikkaWatchStats`; «Улюблене» — серце, число з першої сторінки), рядок сортування (`_sortRow`: «Оновлені нещодавно ⌄» → `showAppMenu` з `HikkaListsPage.sortLabel`; в «Улюбленому» — «N тайтлів») і перемикач «Сіткою» / «Списком» (`StorageService.getHikkaListRows`). Сітка — `HikkaAnimeCard(caption: _metaOf — «6 з 25 · ★ 8», «Анонс · Зима 2027», «Онґоїнґ · 7 з 12», «TV Серіал · 2023 · ★ 9»; progress — смужка для «Дивлюсь» / «Відкладено» / «Кинуто»; seen; onRemove)`; списком — `_ListRow` (мініатюра 48×68, назва, сірий рядок, власна оцінка праворуч або «без оцінки»). Довге натискання — `showHikkaCardMenu` з піднятою карткою. Порожня вкладка — `_empty` (великий значок, `HikkaListsPage.emptyOf`, «Перейти до огляду»; з фільтрами — «Нічого не знайдено»). Фільтри — `HikkaFilterSheet(title: «Сортування й фільтри», countOf)`. Перезавантажується за `HikkaMyList.version` і зміною акаунта; 18+ ховається за `HikkaPrefs.allowAdult`.

- **HikkaListsPage** (р.36)
  - `sortLabel()` р.51
  - `emptyOf()` р.62
- **_HikkaListsPageState** (р.75)
- **_ListRow** (р.655)

### `lib/widgets/hikka/hikka_markdown_view.dart` (453 р.)
Віджети описів: `HikkaMarkdownView` (абзаци, списки, цитати, спойлери, посилання → `HikkaNav.openLink`; `linkColor`, `linkUnderline`; `maxLines` — згорнутий вигляд). `HikkaMarkdownView.baseStyle` — один шрифт для обох виглядів (`fontFamilyFallback: MikiSans`), `collapsedSpan` — згорнутий текст одним абзацом, посилання як звичайний текст. `HikkaSynopsis(source, scale, fontSize, lines, color, open, onOpen, onLink)` — опис за варіантом А: `lines` рядків, останній згасає (`ShaderMask`), «Читати далі ⌄»; дотик будь-де розгортає (посилання в згорнутому не діють); розгорнутий — світлі підкреслені посилання й «Згорнути ⌃», висота плавно (`AppAnimatedSize`); короткий текст — одразу повністю. Стан відкриття сторінки тримають у `route.memo['synopsis']` (тайтл, персонаж, людина, колекція; коментарі колекції — `memo['comment-<slug>']`). `HikkaSpoilerBox` — спойлер, спільний для описів і статей.

- **HikkaMarkdownView** (р.16)
  - `baseStyle()` р.49
  - `collapsedSpan()` р.59
- **_HikkaMarkdownViewState** (р.83)
- **HikkaSynopsis** (р.240)
- **_HikkaSynopsisState** (р.270)
- **HikkaSpoilerBox** (р.383)
- **_HikkaSpoilerBoxState** (р.394)

### `lib/widgets/hikka/hikka_my_list_bar.dart` (264 р.)
`hikkaStatusColor(status)` — приглушені кольори статусів (смужка «Списку» в профілі). `HikkaMyListBar(anime, scale)` — кругла закладка на банері сторінки тайтла: гість — «Додати в список» (веде до входу), ввійшов — сіра з плюсом або жовта зі значком статусу й прогресом «N/M» для «Дивлюсь»; дотик відкриває шторку «Мій список» (`showHikkaListSheet`). `HikkaListMark(status, size, color)` — значки закладки статусів (плюс, трикутник, галочка, пауза, хрестик), спільні для вкладок «Списків», шторки й профілю.

- `hikkaStatusColor()` (р.20)
- **HikkaMyListBar** (р.30)
- **_HikkaMyListBarState** (р.40)
- **HikkaListMark** (р.201)
- **_ListMarkPainter** (р.212)

### `lib/widgets/hikka/hikka_notifications_page.dart` (389 р.)
`HikkaNotificationsPage` — «Сповіщення»: нові серії в обраній озвучці (див. `episode_alerts.dart`); сірий рядок «Нові серії та повідомлення» з «Прочитати все» праворуч, групи сірими підписами, рядки: постер 44×62 (повідомлення розробника — сіра плитка з лінійним значком), назва жирна, поки не прочитано, жовта крапка `alert-unread`, сіра шпилька `alert-pinned`; довге утримання / права кнопка — `showAppMenu` («Закріпити» / «Відкріпити», червоне «Видалити»). Підписи груп і рядки — лінивим списком (`HikkaPageFrame.itemBuilder`): сто сповіщень не будуються й не просять постерів одразу.

- **HikkaNotificationsPage** (р.25)
  - `ago()` р.42
- **_HikkaNotificationsPageState** (р.61)

### `lib/widgets/hikka/hikka_admin_page.dart` (744 р.)
`HikkaAdminPage(route, scale, bottomInset, api)` — адмін-панель (маршрут `HikkaRouteKind.admin`): зверху хто ти для сервера (`whoami`: «ZEDDY · сповіщення отримують N пристроїв»; помилка — пояснення й «Спробувати ще», форми немає). «Нове сповіщення»: тип плашками `HikkaChip` (`admin-type-news|update|episode`), поля `_AdminField` (заголовок `admin-title` до 120, текст `admin-body` до 300 з лічильниками; тайтл `admin-slug` — slug або посилання, крім «Оновлення»; «Кому» — «Усім» / «Хто стежить за тайтлом»; картинка https), «Як виглядатиме» (`admin-preview`, підпис, що відкриє дотик), «Надіслати» (`admin-send`: перевірка `_problem`, підрахунок, `showAppConfirm` із кількістю пристроїв, результат `admin-result`, текст очищається) і тихе «Скільки отримають?» (`admin-count`). «Надіслані» — журнал `history()` рядками (`HikkaAdminPage.footer`: тип · кому · отримали · коли). Тест `test/admin_panel_test.dart`.

- **HikkaAdminPage** (р.25)
  - `footer()` р.36
  - `typeLabel()` р.43
  - `devices()` р.45
- **_HikkaAdminPageState** (р.51)
- **_AdminField** (р.640)
- **_AdminFieldState** (р.668)

### `lib/widgets/hikka/hikka_page_kit.dart` (693 р.)
Каркас сторінок: `HikkaPageFrame` (поля, максимальна ширина, прокрутка; `itemCount` / `itemBuilder` — довгий хвіст сторінки лінивим списком після `children`: будуються лише шматки біля екрана, кожен зі своєю шириною від лівого краю — сповіщення, франшиза, стаття; `columnWidth` — ширина вужчої колонки, що стоїть посередині широкого вікна, як колонка статті), `HikkaSection` (заголовок + вміст), `hikkaHeaderPosterWidth`, `hikkaWideBreakpoint` (760), `hikkaReadableWidth`. `HikkaPageFrame.onRefresh` — оновлення потягом вниз (лише на телефоні; на ПК є кнопка «Оновити»); `HikkaTabHeader(scale, title, subtitle, actions)` — заголовок головних вкладок «Огляд» / «Списки» / «Профіль». `HikkaLeadLine(scale, pad, parts)` — сірий рядок під смугою сторінки («Проводжальниця Фрірен · 53»), `HikkaSortLine<T>(value, options, onChanged, caption)` — тихий рядок порядку «Популярні ⌄» зі спільним випадним меню, `hikkaCountLine(scale, icon, text)` — тихий лічильник під іменем («5 аніме»). `HikkaHeaderSlot.put(w, resetOn, same)` — шматок сторінки в спільній шапці; поки `same` (з чого він зроблений) той самий, шапка не перебудовується (календар кладе дні після кожної своєї побудови).

- **HikkaPageFrame** (р.16)
- **HikkaSection** (р.114)
- **HikkaSortLine** (р.155)
- **HikkaLeadLine** (р.226)
- `hikkaCountLine()` (р.244)
- `hikkaHeaderPosterWidth()` (р.254)
- `hikkaReadableWidth()` (р.263)
- **HikkaTabHeader** (р.267)
- **HikkaSwipeTabs** (р.306)
- **_HikkaSwipeTabsState** (р.324)
- **HikkaTabEnter** (р.371)
- **_HikkaTabEnterState** (р.385)
- **HikkaHeaderSlot** (р.435)
  - `put()` р.446
  - `clear()` р.455
  - `takeReset()` р.469
- **_HeaderSlotScope** (р.476)
  - `updateShouldNotify()` р.482
- `hikkaHeaderSlot()` (р.486)
- **HikkaCollapsingHeader** (р.496)
- **_HikkaCollapsingHeaderState** (р.507)
- **HikkaLazy** (р.624)
- **_HikkaLazyState** (р.637)
- **_HeaderBg** (р.680)

### `lib/widgets/hikka/hikka_paged_list.dart` (216 р.)
`HikkaPagedList<T>(pager, scale, itemBuilder, emptyText, header, maxCardWidth, flush, empty, …)` — прокручуваний список карток із підвантаженням (`HikkaPager`): докантажує при наближенні до кінця; на широких вікнах — кілька стовпців; `flush` — рядки зі своїми полями (без проміжків і бічних полів списку; режим «Списком» у «Списках»); `empty` — свій порожній стан; «Повторити». Стовпці рахує `LayoutBuilder` над прокруткою (не `SliverLayoutBuilder`: той працював на кожному кадрі прокрутки й перебудовував усі видимі картки); готові картки й сліви повторно використовуються, як у `HikkaPagedGrid`.

- **HikkaPagedList** (р.14)
- **_HikkaPagedListState** (р.56)

### `lib/widgets/hikka/hikka_person_page.dart` (391 р.)
Сторінки людей: `HikkaAnimeStaffPage(route, scale, bottomInset)` — усі автори тайтлу рядками `AppMediaRow` (кругле фото, ім’я, ролі — `rolesOf`: три й «ще N»; ключі `staff-<slug>`), над ними `HikkaLeadLine` «назва тайтлу · кількість» (підвантаження по 30, `route.memo['pager']` тримає сторінки при поверненні); `HikkaPersonPage(route, scale, bottomInset)` — людина: фото, імена, тихі лічильники, опис `HikkaSynopsis`, пігулки «Ролі N» / «Аніме N» (`person-tab-characters` / `person-tab-anime`; першою й за замовчуванням — довша, `memo['tab']`) із сітками.

- **HikkaAnimeStaffPage** (р.20)
- **_HikkaAnimeStaffPageState** (р.31)
  - `rolesOf()` р.64
- **HikkaPersonPage** (р.103)
- **_HikkaPersonPageState** (р.114)

### `lib/widgets/hikka/hikka_profile_page.dart` (317 р.)
`HikkaProfilePage(scale, bottomInset, onOpenSettings, refreshToken, onRefresh)` — вкладка «Профіль»: заголовок із шестернею (`HikkaLineButton`, жовта крапка, коли є оновлення). Після входу — `HikkaUserProfile(own: true, extra: …)` з блоками `_app` («Застосунок»: «Налаштування» `profile-settings` — «Вигляд, субтитри, відтворення» або стан оновлення `UpdatePrompt.statusLine` («Є оновлення…», «Завантаження оновлення… 34%», «…готове до встановлення»), «Локальна медіатека», коли ввімкнено в «Розробнику», «Адмін-панель» `profile-admin` лише для `AdminApi.instance.visible` → `HikkaNav.openAdmin`) і `_account` («Акаунт»: «Синхронізувати налаштування й теми», «Передавати прогрес у списки» перемикачами, червоне «Вийти з акаунта» через `showAppConfirm`). Гість — `_guest` (сіра аватарка, «Гість», пояснення, `HikkaLoginButton`), «Застосунок» з «Про Miki Miki», підпис «Дані: Hikka · зображення: AniList».

- **HikkaProfilePage** (р.32)
- **_HikkaProfilePageState** (р.58)

### `lib/widgets/hikka/hikka_schedule_page.dart` (494 р.)
Вкладка «Календар»: сім денних плашок `_DayPlate` від сьогодні (день тижня й число, жовта крапка сьогодні; ключі `schedule-day-N`, `_day` — зсув від сьогодні), під ними сірий підпис «Сьогодні · N серій», рядки `_EpisodeTile` (час — лише коли змінився, постер 44×62, «Серія N з M», `HikkaListMark` для тайтлів зі списків) і сьогодні лінія «зараз» `_NowLine` перед першою майбутньою серією; розклад підвантажується, доки не покриє тиждень (сторінка перебудовується лише тоді, коли змінилося показане — `_shown`). Дні — у спільній шапці «Огляду» (`hikkaHeaderSlot`, з `same`).

- **HikkaSchedulePage** (р.22)
- **_HikkaSchedulePageState** (р.33)
- **_DayPlate** (р.272)
- **_NowLine** (р.337)
- **_EpisodeTile** (р.364)
- **_ScheduleSkeleton** (р.429)

### `lib/widgets/hikka/hikka_settings_dialog.dart` (170 р.)
Налаштування каталогу: мова назв (Українська / English / Ромаджі), 18+, «Оновити дані», «Очистити кеш зображень» із розміром. Розділ «Перегляд» з кнопкою «Джерела перегляду» (`SourcesDialog`). Розділ «Свій клієнт Hikka» (два поля, зміни з паузою 600 мс і при закритті → `HikkaAuth.setCustomClient`).

- **HikkaSettingsDialog** (р.16)
- **_HikkaSettingsDialogState** (р.40)

### `lib/widgets/hikka/hikka_shelf.dart` (271 р.)
Горизонтальні полиці: `HikkaShelf` (стрілки на десктопі; `gap` 10, `titleSize` 15, `calm` — типово так: сірий низький «Усі ›» і більший сірий підпис; широка сторінка тайтла лишає старий вигляд), `HikkaShelfSkeleton`, `HikkaShelfAsync<T>` (ті самі параметри; сама вантажить дані; порожній список ховає полицю; помилка — під заголовком із «Повторити»).

- **HikkaShelfMetrics** (р.11)
  - `cardWidth()` р.14
  - `height()` р.17
- **HikkaShelf** (р.22)
- **_HikkaShelfState** (р.64)
- **HikkaShelfSkeleton** (р.128)
- **HikkaShelfAsync** (р.192)

### `lib/widgets/hikka/hikka_slate_view.dart` (497 р.)
`HikkaSlateView(nodes, scale, fontSize, onLink)` — текст статті (документ Slate): абзаци, заголовки, списки, цитати, спойлери (`HikkaSpoilerBox`), картинки (`HikkaSlateImage`: проявляється, натискання → `HikkaImageViewer` із масштабуванням і гортанням групи), групи картинок плитками, відео, посилання (на аніме, персонажів, колекції й статті — всередину застосунку; світлі з тонким підкресленням). Основний текст 15, міжрядковий 1,6. `HikkaSlateView.pieces(nodes)` — документ шматками для лінивого списку (блоковий вузол окремо, рядкові підряд — одним абзацом); `HikkaSlateView` кожного шматка виглядає так само, як цілий.

- **HikkaSlateView** (р.16)
- **_HikkaSlateViewState** (р.50)
- **HikkaSlateImage** (р.340)
- **HikkaImageViewer** (р.400)
  - `show()` р.406
- **_HikkaImageViewerState** (р.419)

### `lib/widgets/hikka/hikka_watch_dialogs.dart` (453 р.)
Діалоги блоку «Дивитись»: `WatchDialogs.confirmLicensed(context, scale:, license:)` («Тричі подумайте»: головна дія — дивитись легально, тиха `QuietAction` «Все одно дивитись»; `true` — людина підтвердила), `WatchDialogs.teams(context, scale:, teams:, source:)` (опис, прапорці «Озвучення / Субтитри», кількість тайтлів і посилання команди з Mikai), `WatchDialogs.linkLabel(key)`; `WatchDialogFrame` — спільна оболонка діалогів перегляду (заголовок із закриттям, прокручуваний вміст, ряд кнопок); `QuietAction` — тиха текстова дія.

- **WatchDialogs** (р.15)
  - `confirmLicensed()` р.20
  - `teams()` р.38
  - `linkLabel()` р.43
- **WatchDialogFrame** (р.73)
- **_WatchDialogFrameState** (р.86)
- **QuietAction** (р.167)
- **_LicenseDialog** (р.206)
- **_TeamsDialog** (р.280)
- **_TeamBlock** (р.306)
- **_TeamBlockState** (р.317)

### `lib/widgets/hikka/hikka_watch_section.dart` (1106 р.)
`HikkaWatchSection(anime, route, scale, pad, bottom = 22)` — блок «Дивитись» (див. правило «Блок Дивитись» угорі індексу): головна кнопка, рядок-підсумок із сірою кнопкою, «Наступна серія», панель «Перегляд» (телефон — `showAppSheet`, ПК — `WatchDialogFrame`) з озвученням (вибір у шторці), плашками серій (`_episodeGrid`: 12 довкола наступної; «Показати всі» для довгого серіалу — діапазони по `episodeRange` = 100 у `AppRangeStrip` з `design_kit.dart`, відкривається той, де наступна серія), якістю, плеєром, джерелами, командою, сайтом, новим пошуком; картка ліцензії; порожній стан і помилки джерел.

- **HikkaWatchSection** (р.42)
- **_HikkaWatchSectionState** (р.57)

### `lib/widgets/hikka/sources_dialog.dart` (294 р.)
`SourcesDialog.show(context, scale:, registry:)` — «Джерела перегляду»: перемикачі сайтів (`SourcePrefs.setEnabled`; підказка від джерела), «Якість відео» (`maxHeight`), «Плеєр за замовчуванням» (`hoster`: Авто / Moon / Ashdi), «Ключ Mikai API» (`AppSearchField`; зберігається через 600 мс після набору й при закритті вікна; `SourceRegistry` одразу передає його в `MikaiSource`). Зміни діють одразу. `SourcesDialog.searchSignature(registry)` — відбиток налаштувань, від яких залежить пошук (ввімкнені сайти + ключ): змінився → блок «Дивитись» шукає наново.

- **SourcesDialog** (р.18)
  - `show()` р.24
  - `searchSignature()` р.29
- **_SourcesDialogState** (р.38)

### `lib/widgets/home_hub.dart` (373 р.)
`HomeHub(scale, onOpenFile, onOpenMultipleFiles, onOpenQueue, onOpenSettings({tab}), reserveBottom)` — оболонка застосунку: чотири вкладки `MainTab` (`iconOf`), на телефоні в портреті — нижня навігація (`bottomNavHeight` 64 dp, цілі ≥ 48, `Semantics(selected)`), на ПК і широких екранах — `AppSidebar` (монограма «M», `AppIdentity.name` / `tagline`, «Налаштування», версія). Сам вміст — `HikkaHub` у `SettingsFont` (на Android текст «Arial» малюється вбудованим Liberation Sans); локальна медіатека (`LocalLibrary`) передається йому будівельником. `HomeHub.lineIconOf(tab)` — лінійні іконки нижньої навігації (`LineIcon` home / search / bookmark / person; без «пігулки», вибрана — акцентна іконка й підпис); `iconOf` лишився для бічного меню ПК. `HomeHub.backHandler` (статичний) = `HikkaNav.back()`; `isCompact(context)`; `debugReset()` — для тестів.

- **HomeHub** (р.23)
  - `Function()` р.29
  - `debugReset()` р.32
  - `isCompact()` р.37
  - `iconOf()` р.41
  - `lineIconOf()` р.49
- **_HomeHubState** (р.85)

### `lib/widgets/local_library.dart` (976 р.)
`LocalLibrary(scale, onOpenFile, onOpenMultipleFiles, onOpenQueue, reserveBottom)` — колишній головний екран (відкрити файл чи посилання, історія файлів, остання черга й плейлисти), тепер прихована «Локальна медіатека» (правило «Локальна медіатека»); відкривається з «Профілю» сторінкою стека. Вкладки — `AppPillTab` (Огляд · Історія · Плейлисти з лічильниками); «Огляд»: «Відкрити» рядками `AppLineRow` (файл, папку, мережевий потік), «Остання черга» плиткою (кадр, «Серія N з M», «Зберегти як плейлист», кругла «Відновити», смужка прогресу черги), «Нещодавно» рядками `AppMediaRow` з кадром 96×54; на ПК — гарячі клавіші.

- **LocalLibrary** (р.19)
- **_LocalLibraryState** (р.41)

### `lib/widgets/mini_player.dart` (211 р.)
Міні-плеєр (вікно поверх): підпис часу й смужка прогресу з `PlaybackClock`, перемотка кліком.

- **MiniPlayer** (р.12)
- **_MiniPlayerState** (р.32)

### `lib/widgets/mobile_controls.dart` (421 р.)
Керування відтворенням для телефона (портрет і альбомна) у новому стилі (концепт П1/П4, `player_kit.dart`): угорі лінійні «Назад» / назва з сірим рядком (тап — інформація) / PiP / поворот (`active` — заблоковано; довге — автоповорот) / налаштування — без плашок; по центру `PlayerCircleButton`: попередня · −N с (`seek-back`, `PlayerSeekGlyph`) · пауза (велике коло, `LineIcon.pause`/`play`) · +N с (`seek-forward`) · наступна (на ширині ≥ 600 кола більші й рідші); унизу час, `AppSeekBar` і ряд `PlayerPill` «1×» (`player-speed`, жовта — меню відкрите або швидкість не 1×) · Anime4K (жовта крапка — увімкнено, довге — перемкнути) · субтитри (крапка — увімкнено) · звук · справа `PlayerPill` «Серії» (`player-episodes`; на вузькому екрані лише значок). Цілі дотику ≥ 48 dp (`hitHeight` пігулок), розміри в dp. Потрібен `Stack` (повертає `Positioned.fill`). Параметри `onPrevious` / `onNext` (як у `BottomDock`) і `showTransport` (false — перемотка й пауза плавно ховаються, поки `RemoteStatusOverlay` показує стан серії). Назву й сірий рядок дає `PlayerStateController.chromeTitle` / `chromeSubtitle()`.

- **MobileControls** (р.20)

### `lib/widgets/mobile_gesture_layer.dart` (332 р.)
Жести на відео для телефона: вертикально по лівій половині — яскравість, по правій — системна гучність (записи не частіше ~25/с), горизонтально — перемотка (застосовується, коли палець відпущено). Початок жесту = точка дотику (`DragStartBehavior.down`), краї екрана (системні жести) ігноруються. Тапи й подвійний тап лишаються за `VideoViewport`.

- **MobileGestureLayer** (р.23)
- **_Kind** (р.54)
- **_MobileGestureLayerState** (р.56)

### `lib/widgets/mobile_sheet.dart` (169 р.)
Рамка меню для телефона: у портреті нижня панель (до 68 % висоти, «ручка» і затемнення), в альбомній — бічна панель справа (340…440 dp). Поверхня як у шторок застосунку: колір сторінки, тонка лінія `AppTones.menuLine`, заокруглення 24 / 22, ручка `AppTones.dot`. Малює лише поверхню; вміст — `SettingsDrawer(sheet: true)` / `SidePanel(sheet: true)`.

- **MobileSheetFrame** (р.14)
  - `sideWidth()` р.30
- **_GrabHandle** (р.143)

### `lib/widgets/osd_toast.dart` (177 р.)
Підказка OSD поверх відео (концепт П6): темна плашка, біла іконка, «Назва · значення» жирним (коротке значення ≤ 16 знаків стає частиною назви, довге — сірим рядком під нею), тонка жовта смужка рівня (`progress`), клавіші на ПК, помилка — червона рамка й іконка; ключ `osd-plate`. Плавна поява, не перехоплює кліки. `topInset` — відступ під виріз / рядок стану на телефоні.

- **OsdToast** (р.13)
- **_OsdPill** (р.52)
  - `inline()` р.59
- **_OverlayKeyCap** (р.148)

### `lib/widgets/player_kit.dart` (421 р.)
Кнопки плеєра в новому стилі (концепти П1–П6): лінійні іконки просто на відео без плашок, м’яке коло лише під пальцем / курсором. `PlayerTones` (завжди світле на темному: `fg`, `sub`, `disabled`, `pill` / `pillLine`, `circle` / `circleBig`, `active` = акцент). `PlayerIconButton(icon, glyph, onTap, onLongPress, onSecondaryTap, active, badge, label, size, iconSize, stroke)` — `active` жовтий (меню відкрите, поворот заблоковано), `badge` — жовта крапка (Anime4K / субтитри увімкнено), `glyph` — свій малюнок (±N с); `PlayerCircleButton(child, onTap, size, big, label)` — напівпрозоре коло транспорту; `PlayerSeekGlyph(forward, seconds, size)` — кругла стрілка з числом; `PlayerPill(text, icon, onTap, …, active, label, height, fontSize, hitHeight, plain)` — темна пігулка «1×» / «Серії» (`hitHeight` — зона дотику 48 dp, `plain` — без плашки, лише під курсором). Меню: `PlayerMenuRow(scale, sheet, icon, title, sub, value, chevron, active, onTap, iconColor, dimWhenOff, leading)` — рядок налаштувань плеєра й «Перегляду» (лінійна іконка або `leading` — свій значок, як у сервісів пісні, назва, сірий рядок або значення праворуч, шеврон; світла / темна тема), `playerText(size, …)` — текст меню (Arial + MikiSans).

- **PlayerTones** (р.10)
- **_Press** (р.35)
- **_PressState** (р.47)
- **PlayerIconButton** (р.80)
- **PlayerCircleButton** (р.161)
- **PlayerSeekGlyph** (р.199)
- **PlayerPill** (р.226)
- `playerText()` (р.306)
- **PlayerMenuRow** (р.319)

### `lib/widgets/remote_panel.dart` (1330 р.)
`RemotePanelBody(scale, driver, sheet, onEpisodeSelected, onClose, header, lead)` — панель «Перегляд» (`header: false` — головна сторінка без заголовка «Перегляд», `lead` — блок угорі списку, що гортається з ним) серій із сайтів (концепт П3; та сама, що на сторінці тайтла). Свій заголовок («Перегляд» + назва аніме, «Закрити»; внутрішні сторінки — «Назад» `watch-back`). Головна: рядок озвучення `watch-variant` (мікрофон / субтитри, жовтий знак — `episodeCheckWarns`; «28 з 28 серій · оновлено ДД.ММ», з `RemoteDriver.hikka`), «Серії» `watch-episodes` (`CustomScrollView`): рядки з кадром TMDB, номером і тривалістю на ньому, назвою й датою (`_Rows.stills`), без кадрів — номер, назва, дата (`_Rows.titles`), без назв — плашки по сім у ряд (`_Rows.plates`); назви й кадри — `EpisodeGuideService` за `RemoteDriver.malNumbers` (правило «Назви й кадри серій»), поки назви іншого діапазону йдуть, рядки лишаються рядками. `ep-<i>`; переглянуті приглушені з галочкою, поточна світліша (у рядках — поступ і «ще N хв» з `RemoteDriver.progress`, `_Live`; у плашках — обведення й жовта риска); тап — серія; утримання / права кнопка на рядку — деталі серії (`_openDetail`: кадр, назви, дата, тривалість, опис, «Дивитися» `detail-play`, «Переглянуто» / «Зняти позначку» `detail-watched`): на телефоні вертикально — картка `episode-card` над затемненим списком (`_detailCard`), у бічній панелі (телефон набік, ПК) — сторінка `_Page.episode` (`_detailPage`; коротка панель — малий кадр поруч із назвою), «Назад» повертає список на те саме місце; на плашці утримання — «переглянуто» одразу; поки назви йдуть (`_loading`), рядки — сірі заготовки з номерами (кадр `AppTones.plate`, риски замість назви й дати), а тайтл, у якого назв не виявилось (`_platesOf`), лишається плашками; системна «Назад» / Esc — `RemoteDriver.panelBack` (`_stepBack`: деталі чи внутрішня сторінка → список); підказка на ПК — назва й оригінал; довгий серіал — діапазони по `episodeRange` = 100 з `AppRangeStrip` (над рядками — у верхньому блоці, над плашками — у їхньому), відкритий той, де поточна серія; рядки будуються лише видимі (`SliverFixedExtentList`), тож поточну прокручує розрахунок (`_revealCurrent`), плашку — `ensureVisible`, «Якість» `watch-quality` і «Плеєр» `watch-player` зі значеннями. Сторінки: озвучення й субтитри (підпис «Перемикається з того ж місця…», `EpisodeNote` для розбіжності з Hikka, групи «Озвучення · N» / «Субтитри · N», `AppCheckRow` `watch-variant-<id>` з жовтим знаком `watch-variant-warn-<id>`; вибір — `switchGroup` і назад), якість (`switchQuality`), плеєр (`switchHoster`). Черги файлів тут немає.

- **_Page** (р.29)
- **_Rows** (р.33)
- **RemotePanelBody** (р.45)
- **_RemotePanelBodyState** (р.84)
- **_Episode** (р.1308)
- **_Live** (р.1318)

### `lib/widgets/remote_status_overlay.dart` (155 р.)
`RemoteStatusOverlay(scale, driver, onOpenPanel, onClose)`: поки `driver.showsStatus` — картка поверх відео («Шукаю відео…», «Запускаю плеєр…», після збою — причина й дії: «Спробувати ще», «Інший плеєр» (`alternativeHoster`), «Озвучки та плеєри», «Наступна серія», «Закрити»). Поки відео йде — нічого не малює й не перехоплює дотики. Повертає `Positioned.fill` (потрібен `Stack`).

- **RemoteStatusOverlay** (р.12)

### `lib/widgets/settings_drawer.dart` (917 р.)
Меню плеєра в новому стилі (концепти П2 і П6). Головна сторінка — рядки `PlayerMenuRow` (ключі `menu-<id>`): «Якість» (лише для серій із сайтів із кількома варіантами: `remote` → `RemoteDriver.stream.qualities`, сторінка `quality`, перемикання `switchQuality`), «Швидкість» (`speed`), «Субтитри» і «Звук» (на телефоні значення сірим рядком під назвою, на ПК праворуч; у «Звуку» ще затримка, якщо не 0), «Розділи» (кількість; без розділів — тихий рядок «Немає»), «Anime4K» (жовтий, коли увімкнено), риска, «Більше» (`advanced`: «Апаратний декодер» → `hwdec`, «Статистика відтворення», «Усі налаштування» — `onOpenAppSettings`). Вибір усередині — `AppCheckRow` із жовтою галочкою (ключі `choice-<id>`; розділи з часом початку праворуч, Anime4K із комбінаціями Ctrl+N на ПК, якість Fast/HQ плашками `anime4k-quality-*`). «Звук» — доріжки, риска, `_AudioDelayRow` (крок 50 мс, ±10 с, кнопки-плашки `delay-minus` / `delay-plus` / `delay-reset`; `audioDelayKey` зберігає значення для твору) і пояснення. `sheet: true` — телефон: шапка 56 dp з лінійними «Назад» / «Закрити» (48 dp), рядки ≥ 52; ПК — темна плитка (`player-menu`, як випадні меню застосунку) під кнопкою, сірий підпис угорі, на внутрішній сторінці він веде назад (`menu-back`). `SettingsDrawer.qualityLabel(video)` — «1080p» / «Авто». Необовʼязковий `onAddSubtitleFile` → рядок «Додати файл субтитрів…». Сторінка «Розділи» для таймкодів AniSkip (`remote.skipPlan`, не сайт) — `_skipControls`: «Зсув таймкодів» (`_SkipShiftRow`, ±0,5 с, «≈» — поки зсув невідомий), «Опенінґ почався тут» (`skip-here`), примітка `skipNote`. Степери (затримка звуку, зсув) — спільний `_StepperRow` (ключі `<id>-minus/-value/-plus/-reset`; на телефоні значення під назвою, довга назва трохи зменшується, а не обрізається). Пісні: сторінки `song-op` / `song-ed` (`_songPage`: обкладинка, «Опенінґ 1», назва, виконавець; рядки `song-<app>` з «пісня» / «кліп» / «пошук», відкриває `HikkaNav.urlOpener`); у «Розділах» перед опенінґом / ендінґом — обкладинка `chapter-song-<op|ed>` (`AppCheckRow.leading`; з еквалайзером на поточному розділі; відкриває «Пісню»), пісня — підписом; рядки сервісів — зі значком `MusicAppBadge` (`PlayerMenuRow.leading`).

- **SettingsDrawer** (р.29)
  - `qualityLabel()` р.133
  - `skipNote()` р.643
- **_AudioDelayRow** (р.717)
- **_AudioDelayRowState** (р.728)
  - `format()` р.759
- **_StepperRow** (р.778)
- **_SkipShiftRow** (р.883)
  - `format()` р.893

### `lib/widgets/shortcuts_view.dart` (567 р.)
Довідка «Гарячі клавіші»: `ShortcutsView` (картки груп із кнопками клавіатури, пошук за назвою/клавішами, дві колонки від 640 px) і `ShortcutsDialog` (вікно: перемикач схеми, пошук, Esc / F1 / Ctrl+F). Тіло довідки використовує й вкладка налаштувань.

- **ShortcutSection** (р.14)
- **ShortcutsView** (р.57)
  - `sections()` р.70
  - `queryWords()` р.96
  - `matches()` р.118
  - `splitIndex()` р.136
- **_GroupCard** (р.197)
- **_ShortcutRow** (р.259)
- **ShortcutsDialog** (р.311)
  - `show()` р.319
- **_ShortcutsDialogState** (р.337)

### `lib/widgets/side_panel.dart` (637 р.)
Бокова панель: черга / інфо / розділи у плаский стиль меню застосунку (заголовок `AppPanelHeader`: «Черга · N», «Розділи · N», «Про відео»). Черга: плашки «Додати» (`queue-add`) і режим повтору (`queue-repeat`: «Без повтору / Повтор черги / Повтор відео»), «Очистити» (`queue-clear`); рядки `queue-<i>` — ручка перетягування, кадр із номером, назва (поточна жирна з жовтим «Зараз відтворюється»), на ПК «Вище / Нижче», «Прибрати з черги». Розділи: кадр із номером (поточний — жовта рамка), назва, «початок · тривалість» (поточний — «Зараз · …» жовтим), повтор розділу (`chapter-loop-<i>`, A-B у mpv). Інфо: сірі підписи груп і рядки «назва — значення». `sheet: true` — режим меню-панелі для телефона (більші кнопки, черга міняється порядок перетягуванням). Параметр `remote` (`RemoteDriver?`): коли `remote.active`, вкладка «Серії» — `RemotePanelBody` зі своїм заголовком, а в «Про відео» замість шляху до файлу — серія, озвучка й плеєр (`_fileRows`).

- **SidePanelType** (р.18)
- **SidePanel** (р.20)
- **_SidePanelState** (р.65)

### `lib/widgets/side_panel_drawer.dart` (73 р.)
Анімована обгортка SidePanel. Параметр `remote` передається в `SidePanel`.

- **SidePanelDrawer** (р.8)

### `lib/widgets/skip_button.dart` (190 р.)
Кнопка пропуску глави/опенінгу (концепт П1): темна плашка з тонкою світлою рамкою, «Пропустити …» жирним і лінійний знак `skipForward` (ключ `skip-chapter`). Стежить за `PlaybackClock` через `ClockValue` + `AppClockBuilder`: перебудовується лише коли кнопка з'являється/зникає. `touch: true` — телефон: висота 48 dp, стоїть над нижньою панеллю. Неточні розділи (`VideoChapter.autoSkip == false`, безпечні таймкоди AniSkip) не пропускаються самі — лише кнопкою; «Заставка» → «Пропустити заставку» (`SkipButton.accusative`).

- **SkipButton** (р.13)
  - `accusative()` р.24
- **_SkipButtonState** (р.40)

### `lib/widgets/song_card.dart` (389 р.)
Пісня опенінґу / ендінґу над відео: `SongCard` (верхній лівий кут на м'якому затемненні, обкладинка з еквалайзером, «ОПЕНІНҐ 1», назва, виконавець; `touch` — телефон; `hidden` — під меню; `onOpen(kind, key)`), `SongCover` (обкладинка з `HikkaImage`, без неї — плашка з нотою; `equalizer` + `playing` — анімований еквалайзер), `EqualizerPainter` (три смужки, `level(i, t)`), `MusicAppBadge` (значок сервісу з його сайту, `iconUrl`).

- **EqualizerPainter** (р.25)
  - `level()` р.33
- **SongCover** (р.55)
- **_SongCoverState** (р.67)
- **SongCard** (р.137)
- **_SongCardState** (р.170)
- **_CornerEllipse** (р.339)
  - `transform()` р.343
- **MusicAppBadge** (р.351)
  - `iconUrl()` р.364

### `lib/widgets/stats_overlay.dart` (424 р.)
Stats overlay (AppModalShell): у «Відтворенні» плитка «Вихід звуку» (`PlaybackStats.audioOutput`: канали джерела → виходу, частота, вихід mpv; моно видно одразу); вкладки «Огляд», «Логи libmpv», «Джерела» (`SourceLog`, автопрокрутка донизу, очищення); «Зберегти у файл» (`LogExport.save`: журнал сесії + поточний стан + логи libmpv) і значок копіювання звіту в буфер (`_videoBlock` — спільний блок).

- **StatsOverlay** (р.14)
- **_StatsOverlayState** (р.42)

### `lib/widgets/subtitle_settings_dialog.dart` (410 р.)
Діалог стилю субтитрів.

- **SubtitleSettingsDialog** (р.11)
  - `show()` р.21
- **_SubtitleSettingsDialogState** (р.33)

### `lib/widgets/top_dock.dart` (110 р.)
Верхня панель плеєра на ПК (концепт П5): лінійні `PlayerIconButton` без плашок — «Згорнути» (chevronDown), назва (15.5, жирна) із сірим рядком `subtitle` («Серія 6 з 28 · Inari · 1080p»; клік — інформація), «Відкрити файл» (doc), налаштування (`settingsKey`, жовта, поки меню відкрите), «Закрити плеєр»; під ними м’який темний градієнт.

- **TopDock** (р.8)

### `lib/widgets/update_prompt.dart` (328 р.)
Вікно «Доступне оновлення» (`WatchDialogFrame`): `UpdatePrompt.show(context, scale:, info:, updater:, start:)` — стежить за `AppUpdater.state` і `download` (`ListenableBuilder`). Без відомої версії (відкрито з повідомлення) — «Перевіряємо…» / «У вас найновіша версія — X» / помилка зі «Спробувати ще». Є версія: «Пропустити версію» / «Пізніше» / «Оновити» (`canInstallInApp`; інакше «Завантажити» → браузер); під час завантаження смуга `HikkaProgressBar` + `progressText` («Завантаження… 12.4 з 36.4 МБ · 34%»), «Скасувати» / «У фоні»; готово — «Встановити» (Windows — «Встановити й перезапустити», `installRestartsApp`); `waitingPermission` — підказка про «Дозволити з цього джерела» й «Відкрити налаштування»; помилка — «Сторінка релізу» / «Спробувати ще». Завантаження, почате у вікні, встановлюється саме, щойно файл готовий (`_installWhenReady`). `start: true` — одразу завантажити / встановити (кнопка в налаштуваннях). `isOpen` — вікно на екрані (не показувати вдруге). `cleanNotes` — нотатки релізу без markdown; `statusLine(updater)` — рядок для «Профілю» («Є оновлення…», «Завантаження оновлення… 34%», «Оновлення X готове до встановлення»); `updateMegabytes`. Показ: `HomeHub` — нова версія раз за запуск (`_maybePromptUpdate`), запит `AppUpdater.promptRequests` (`_onPromptRequest`: повідомлення «нова версія», `miki://open/update`; працює й до появи екрана) і завантаження, що скінчилося без вікна (`_onDownloadDone` за `AppUpdater.downloadsDone`; і тоді, коли екран був закритий повним плеєром — показується, щойно `HomeHub` знову на місці).

- `updateMegabytes()` (р.17)
- **UpdatePrompt** (р.23)
  - `show()` р.40
  - `cleanNotes()` р.46
  - `progressText()` р.55
  - `statusLine()` р.62
- **_UpdatePromptState** (р.78)

### `lib/widgets/video_viewport.dart` (161 р.)
Відео + жести (тап, подвійний тап по боках — перемотка, утримання — прискорення). Плашки над відео — темні з лінійним знаком: «↺/↻ 10 с» (`double-tap-back` / `double-tap-forward`) і швидкість утримання (`speed-hold`, підпис `speedLabel`, напр. «2×»).

- **VideoViewport** (р.8)
- **_VideoViewportState** (р.45)

### `lib/widgets/watch_callout.dart` (71 р.)
Застереження про серії: `watchWarnColor()` (жовтий; темніший на світлій темі), `episodeCheckWarns(check)` (чи ставити жовтий прапорець: `incomplete` / `mismatch`), `WatchCallout` (плашка з іконкою) і `EpisodeNote(scale, check, compact)` — пояснення розбіжності нумерації з Hikka; використовують блок «Дивитись» і вкладка «Озвучка» в плеєрі.

- **WatchCallout** (р.14)
- **EpisodeNote** (р.48)

- **Телефон, налаштування**: у портреті `HomeHub.onOpenSettings` без розділу викликає `HikkaNav.openSettings()` (маршрут `HikkaRouteKind.settings`, сторінка поверх вкладки, нижня навігація видима; вміст — `AppSettingsDialog(embedded: true)` через `settingsBuilder`); на ПК й у альбомній — вікно. Стрічка календаря (`hikka_airing_strip.dart`) при відкритті прокручується до першої серії поточної години (інакше найближчої наступної), `HikkaAiring.isCurrent`.
- **Moon через офіційний API**: `SourcePrefs.effectiveMoonKey` = власний ключ із налаштувань (поле «Свій ключ Moon API» у `SourcesDialog`) або безкоштовний ключ із бекенду (`BackendClient.cachedMoonKey`, сервер віддає його через `config`); вбудованого ключа в застосунку немає (файл `moon_key.dart` прибрано). Без ключа чи при збої API діє розбір сторінки плеєра.
- **Умова Moon (Ashdi)**: `StreamResolver.withoutAshdiWhereMoon(hosters)` — де в серії є Moon, Ashdi прибирається і з вибору (`ResolvedStream.hosters`, «Інший плеєр», панель серій), і з автопідстановки; Ashdi лишається лише там, де Moon нема. У `SourcesDialog` «Плеєр за замовчуванням» = Авто / Moon.


### `lib/widgets/hikka/hikka_overview_page.dart` (226 р.)
`HikkaOverviewPage(scale, bottomInset, refreshToken)` — розділ «Усе» в Огляді: «Сьогодні в ефірі» (три серії від поточної години: час сірим, мініатюра, назва, «Серія N»; «Незабаром в ефірі», якщо сьогодні вже нічого; «Розклад ›»), «Колекції» віялом (`HikkaCollectionFanCard`), «Статті» рядками (`HikkaArticleRow`, три), далі полиці «Каталог» і «Персонажі»; «Усі ›» відкриває повний розділ (`HikkaNav.setTab`).

- **HikkaOverviewPage** (р.22)
- **_HikkaOverviewPageState** (р.36)
- **_AiringRow** (р.175)

### `lib/services/backend_client.dart` (340 р.)
`BackendClient` (одинак `BackendClient.instance`, розділ сховища `backend`) — клієнт бекенду на Firebase Functions (проєкт `miki-miki-729d9`, `europe-west1`; код сервера — окремий архів `miki_backend`: `session`, `hikkaToken`, `config`). `ensureSession()` — анонімна сесія на 30 днів (заголовок `x-session`, одна спроба з новою при 401); `hikkaToken(ref)` — обмін коду входу Hikka на токен (секрет клієнта лише на сервері; власний клієнт з налаштувань і далі обмінюється напряму); `refreshMoonKey()` / `cachedMoonKey` — ключ Moon з бекенду (`SourcePrefs.effectiveMoonKey`: власний > з бекенду; вбудованого ключа нема). Запускається у фоні з `main`. Транспорт підміняється (`BackendTransport`); у тестах — `FakeBackend` (`test/support/hikka_account_fakes.dart`). `admin(hikkaToken, action, fields)` — запити адмін-панелі (функція `admin`, заголовок `x-hikka-auth`). `guide(mal)` — гід по серіях MoonAnime (функція `guide`, додаток `tools/backend/guide.ts`: ключ MoonAnime лише на сервері, Firestore `guide/{mal}` — доба для онґоїнґу, тиждень після; `guideThumb` зменшує кадри MoonAnime 1920×1080 до 320×180 WebP, підпис HMAC, кеш CDN Hosting на місяць); 404 (функцію ще не розгорнуто) — до перезапуску не питаємо; `hostingOrigin` — адреса Hosting для `guideThumb`.

- **BackendException** (р.12)
- **BackendClient** (р.27)
  - `debugGet()` р.131
  - `ensureSession()` р.141
  - `pushRegister()` р.204
  - `effectiveTmdbKey()` р.298
  - `refreshMoonKey()` р.307

### `lib/services/audio_route_guard.dart` (75 р.)
`AudioRouteGuard(reload, hasMedia, isPlaying, pause, notice, settle)` — звук у лад із картинкою, коли змінюється вихід (Android): `routeChanged({change, devices, route})` — після `settle` (0,8 с; Bluetooth повідомляє кроками) один `reload` (у плеєрі — mpv `ao-reload`), лише коли щось відкрито; `becomingNoisy()` — пауза й OSD «Пауза: навушники відʼєднано», якщо грало; `route` — куди йде звук. Усе пишеться в журнал (тег `звук`). Створює й підключає `PlayerStateController` (`_audioRoute`). Тест `test/audio_output_test.dart`.

- **AudioRouteGuard** (р.14)
  - `routeChanged()` р.47
  - `becomingNoisy()` р.63

### `lib/services/deep_links.dart` (71 р.)
`DeepLinks.handle(link, {nav, auth, updater})` — посилання `miki://open/…`: просте відкриття, `anime/<slug>`, `character/<slug>`, `collection/<id>`, `article/<slug>`, `update` (вікно оновлення: `AppUpdater.requestPrompt`), `notifications` (сторінка «Сповіщення»), `auth?reference=` (лише поки вхід триває). Приходять із `SystemControls` (подія `deepLink`, `initialLink`). Тест `test/deep_links_test.dart`.

- **DeepLinks** (р.16)
  - `anime()` р.25
  - `handle()` р.28

### `lib/services/app_updater.dart` (697 р.)
`AppUpdater` (одинак `AppUpdater.instance`, розділ `updates`) — оновлення з GitHub Releases (`repo` = `Zeddy-Coder/miki-miki`). Перевірка: `check({auto})` (тиха — не частіше `autoEvery`), `state` (`UpdateIdle` / `UpdateChecking` / `UpdateUpToDate` / `UpdateAvailable(info)` / `UpdateFailed`), `UpdateInfo` (версія, нотатки, сторінка, файл, розмір, `digest` `sha256:` з GitHub), `pickAsset` (Android — arm64 APK; Windows — `…Setup….exe`, далі exe / msix / zip), `skip` / `shouldPrompt`, `compareVersions`, `requestPrompt()` → `promptRequests` (показати вікно), `downloadsDone` — лічильник завершених завантажень. Завантаження в застосунку: `canInstallInApp(info)` (APK на Android, exe на Windows), `startDownload(info)` → `download` (`DownloadIdle` / `DownloadRunning(received, total, fraction)` / `DownloadReady(path, waitingPermission, error)` / `DownloadFailed(message)`): файл `<тека>/updates/<назва релізу>` (Android — `cache/updates`, його віддає FileProvider; Windows — `%TEMP%/MikiMiki/updates`), `.part` дописується через `Range` після обриву, 30 с без даних — обрив, перевірка розміру й SHA-256 (`Isolate.run`), старі версії прибираються, готовий файл переживає перезапуск (`_data['file']`) і видаляється, коли версія вже стоїть; `cancelDownload()`, `readyFor(version)`. `install({askPermission})` → `UpdateInstall` (`started` / `needsPermission` / `unavailable` / `failed`): Android — `SystemControls.installApk` (без дозволу відкриває налаштування «встановлювати невідомі застосунки», після повернення — `AppLifecycleListener` — пробує ще раз без питання; `denied` — підказка); Windows — лише копія, поставлена інсталятором (поруч `unins*.exe`, `_detectInstalledCopy`), оновлюється тихо (`windowsScript`: PowerShell `Start-Process … /SILENT /SP- /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS -Wait; Start-Process <exe>`), застосунок закривається (`exit(0)`) і відкривається знову; копія з теки оновлюється вручну (сторінка релізу). `installRestartsApp`. Усе підміняється в конструкторі (`transport`, `fetch` / `UpdateFetchResponse`, `dir`, `installApk`, `runSetup`, `onNextResume`, `isAndroid`, `isWindows`, `installedCopy`). Тести: `test/app_updater_test.dart`, `test/update_prompt_test.dart`.

- **UpdateInfo** (р.16)
  - `toJson()` р.42
  - `fromJson()` р.45
- **UpdateState** (р.62)
- **UpdateIdle** (р.66)
- **UpdateChecking** (р.70)
- **UpdateUpToDate** (р.74)
- **UpdateAvailable** (р.78)
- **UpdateFailed** (р.83)
- **UpdateDownload** (р.89)
- **DownloadIdle** (р.93)
- **DownloadRunning** (р.97)
- **DownloadReady** (р.110)
- **DownloadFailed** (р.123)
- **UpdateInstall** (р.130)
- **UpdateFetchResponse** (р.148)
- **AppUpdater** (р.163)
  - `compareVersions()` р.300
  - `pickAsset()` р.318
  - `skip()` р.345
  - `shouldPrompt()` р.357
  - `requestPrompt()` р.360
  - `check()` р.366
  - `canInstallInApp()` р.424
  - `readyFor()` р.436
  - `startDownload()` р.474
  - `cancelDownload()` р.496
  - `describeError()` р.589
  - `install()` р.616
  - `windowsScript()` р.659
- **_DownloadJob** (р.688)
  - `Function()` р.690
  - `cancel()` р.692

### `lib/services/admin_api.dart` (201 р.)
Адмін-панель (лише ZEDDY). `AdminApi` (одинак `AdminApi.instance`; `backend`, `auth` підміняються): `admins` = {`zeddy`} (сервер має той самий список — `ADMINS` у `tools/backend/admin.ts`, і саме він вирішує), `visible` (вхід у Hikka під адміном), `isAdminName`, `slugOf(slug або hikka.io/anime/…)`, `whoami()` → (імʼя, пристроїв), `count(audienceSlug)`, `send(AdminPush)` → `AdminSendResult`, `history()` → `AdminLogEntry`; помилки — `AdminException` українською (`describe(status, error)`: 403 — не адмін, 404 — функцію не розгорнуто, 429, 400-коди). `AdminPushType` (`news` / `update` / `episode`, `wire`, `label`), `AdminPush` (`target` = `all` | `slug:<тайтл>`, `toJson`), `maxTitle` 120 / `maxBody` 300. Тест `test/admin_panel_test.dart`.

Примітка: `HikkaClientKey` (`services/hikka_client_key.dart`) тепер містить лише референс клієнта (замаскований; не секрет); секрету клієнта Hikka в застосунку немає — код входу міняє бекенд (`BackendClient.hikkaToken`). У тестах — `HikkaClientKey.testReference`.

Примітка (позначки й календар): `HikkaMyList.statusOf(slug)` / `loadIndex()` — статус кожного тайтлу зі списків (один прохід по всіх статусах, по 100 за запит; запускається з `main` і при вході); картки аніме статусу не показують (чисті постери за новим дизайном); статус видно на закладці сторінки тайтла й у «Списках». `HikkaSchedulePage` — вкладки Пн–Нд (відкривається на сьогодні), серії найближчих 7 діб вибраного дня, свайп між днями (`HikkaSwipeTabs`). Заглушки замість кіл: `HikkaCardSkeleton` (сітка), `HikkaListSkeleton` (колекції, статті), `_ScheduleSkeleton`.

Примітка («Продовжити перегляд»): картки горизонтальні — `HikkaContinueCard` (див. запис файлу). Тап викликає `QuickPlay.resume(anime)` (`services/quick_play.dart`): запускає пошук озвучок (`WatchService.start`), чекає першу знайдену (до 25 с), бере варіант за замовчуванням і серію за `continuePoint`, відкриває плеєр через `WatchLauncher.play`; якщо не вийшло (нічого не знайдено, тайтл ліцензований, плеєр не готовий) — відкривається сторінка тайтлу. `HikkaShelf` / `HikkaShelfAsync` / `HikkaShelfSkeleton` мають `cardWidth` / `cardHeight` для нестандартних карток; меню карток — `showHikkaCardMenu` (`hikka_cards.dart`).

Примітка (b44–b46): нові файли — `services/anilist_posters.dart` (постери лише з AniList), `services/system_fonts.dart`, `services/app_layers.dart` (`AppLayers`/`AppLayerClaim`: лічильник відкритих у дереві панелей, під якими ховається міні-плеєр), `services/video_zoom.dart` (`VideoZoomMath`, `VideoZoomController`, `VideoZoomTransform`: щипок-масштаб відео лише від центру, магніти, відгук). Банери: `BannerArt.load` → бекенд (`BackendClient.banners`, кеш лише CDN-посилань; ключ TMDB зберігає бекенд, `effectiveTmdbKey()`) → AniList; `HikkaTitleBackdrop` (`hikka_banner.dart`) — тло лише під постером і назвами на сторінці тайтла. Сторінки-маршрути (тайтл, персонаж, франшиза, колекція, стаття) мають шапку-накладку `HikkaCollapsingHeader` (слот `HikkaHeaderSlot` / `hikkaHeaderSlot(context)`: сторінка під шапкою, напр. «Календар», кладе в неї свою частину — дні ховаються разом із шапкою) (у `hikka_hub.dart`). `HikkaPrefs.showSecondary` / `secondaryLang` — одна другорядна назва (`HikkaAnime.secondaryTitle`). `HikkaMyListBar` (тепер закладка зі шторкою «Мій список», `hikka_list_sheet.dart`) — випадне меню статусів (стрілка), «Серії та оцінка…» відкриває `HikkaListEditDialog`; посилання тайтла — кнопка + `HikkaLinksDialog`.

Примітка (b48): налаштування каталогу тепер вкладка «Каталог і джерела» (`AppSettingsDialog.tabCatalog` = 9) основних налаштувань: вміст — `HikkaCatalogSettings` (`widgets/hikka/hikka_settings_dialog.dart`; окремого вікна більше немає), джерела перегляду вбудовані як `SourcesSettings` (`sources_dialog.dart`; `SourcesDialog` лишається обгорткою для швидкого входу з тайтла й «Профілю»). «Оновити дані» викликає `HikkaNav.instance.refreshAll` (ставить `HikkaHub`).

Примітка (1.1.2): комерційні шрифти (Trebuchet MS, Impress BT) не входять до репозиторію (`.gitignore`) і застосунку: `SystemFonts.embedded` порожній, типовий шрифт субтитрів — `SystemFonts.defaultFont` (Arial на ПК, Roboto на Android). Історія змін — `CHANGELOG.md`; нотатки релізу CI бере з розділу `## <версія>` цього файлу (без нього збірка тега падає).

- **AdminPushType** (р.5)
- **AdminPush** (р.21)
  - `toJson()` р.39
- **AdminSendResult** (р.50)
- **AdminLogEntry** (р.58)
- **AdminException** (р.95)
- **AdminApi** (р.106)
  - `isAdminName()` р.125
  - `slugOf()` р.134
  - `describe()` р.157
  - `whoami()` р.173
  - `count()` р.179
  - `send()` р.184

### `lib/models/hikka_profile_models.dart`
Публічний профіль Hikka: `HikkaUser` (+ `HikkaUserLink`, `roleLabel`, `fromMe`), `HikkaUserStats` (улюблене, коментарі, відгуки, правки), `HikkaFollowStats`, `HikkaActivityDay.parseList` (365 днів, опівніч UTC), `HikkaHistoryEntry` (`isAnime`, `describe()`: «Переглянуто епізод 12 з 19», «Завершено», «Додано до списку «…»», «Оцінка N», «Додано до улюблених»…), `HikkaProfileText.watchTime` / `historyDay`. `HikkaWatchStats.duration` — хвилини перегляду.

### `lib/widgets/hikka/hikka_user_profile.dart` (839 р.)
`HikkaUserProfile(username, seed, scale, own, reloadKey, extra)` — блоки профілю (кладуться в `HikkaPageFrame`): `HikkaProfileHeader` (кругла аватарка 62 або перша літера на градієнті, ім’я з роллю сірою плашкою, «На Hikka з …», «N стежать · M відстежує», опис і посилання плашками), «Список» — `HikkaListSummary(stats, inset, onStatus)` (смужка часток `list-bar`, рядки статусів зі значками й числами `list-row-<name>`, «Час перегляду»), `extra` (свій профіль: «Застосунок» і «Акаунт»), «Активність» без рамки (`_ActivityCard`: заголовок із «N дій за рік», `HikkaActivityHeatmap` — `level(actions, max)` 0…4, три числа «коментарі · відгуки · правки»), улюблені аніме й персонажі (сірий підзаголовок «12 тайтлів»), статті (`HikkaArticleRow`) і колекції (`HikkaCollectionRow`) через `_AuthoredList`, «Історія» (`HikkaHistoryList`, сірі підписи днів); `HikkaUserPage(route)` — сторінка чужого профілю.

- **HikkaUserProfile** (р.33)
- **_Core** (р.52)
- **_HikkaUserProfileState** (р.61)
- **HikkaProfileHeader** (р.203)
- **HikkaListSummary** (р.312)
- **_ActivityCard** (р.364)
- **HikkaActivityHeatmap** (р.426)
  - `level()` р.433
- **_HikkaActivityHeatmapState** (р.439)
  - `colorOf()` р.444
- **_HeatmapPainter** (р.535)
- **_AuthoredList** (р.593)
- **HikkaHistoryList** (р.642)
- **_HikkaHistoryListState** (р.655)
- **_HistoryRow** (р.744)
- **HikkaUserPage** (р.795)
- **_HikkaUserPageState** (р.806)

### `lib/utils/app_clock.dart`
`AppClock.now` — «зараз» для екранів Hikka з днями й годинами (розклад, стрічка серій, «Сьогодні» / «Вчора», наступна серія). Тести (`HikkaTestEnv`) фіксують середу 4 листопада 2026, 12:00, а `FakeHikka` зсуває знімок розкладу на ціле число тижнів, тож знімки екрана й перевірки не залежать від дня запуску. Новий код, що показує дату чи час на екранах Hikka, бере `AppClock.now()`, а не `DateTime.now()`.

- Сторінка тайтла на телефоні (`HikkaNav.immersive`): без шапки, банер під панеллю індикаторів, кругла «Назад» у `HikkaHub._floatingBack`; `home_hub` не додає верхній safe-відступ.
- `HikkaInfoTable` (hikka_common.dart): картка «Інформація» з плитками значок/підпис/значення, 2 стовпці від ~232 dp, довгі значення на весь рядок (`fullWidth`); у хабі при `immersive` — градієнт під панеллю індикаторів.
- Сторінка тайтла на телефоні (hikka_anime_page.dart): постер по центру на банері, назва, жанри одним рядком, `_scoresCard`, «Мій список», «Дивитись», опис, інформація; секції-полиці: Персонажі → Автори (`_PersonCard`) → Музика (`_OstCard`) → Франшиза → Рекомендації → Посилання/Відео.
- Люди: `HikkaPerson` (+`otherNames`, лічильники), `HikkaPersonAnime`, `HikkaPersonCharacter`; API `person`/`personAnime`/`personCharacters`; маршрути `HikkaRouteKind.person`/`animeStaff` (`openPerson`, `openAnimeStaff`); `hikka_person_page.dart` (`HikkaPersonPage`, `HikkaAnimeStaffPage`); `HikkaPersonCard` (hikka_cards.dart). `HikkaPagedGrid.sectionOf` — розділи сітки («Головні»/«Другорядні»). `HikkaSearchFilters.studios/studioNames` — фільтр за студією (логотип у «Інформації» відкриває каталог).
- Сповіщення «Вийшла нова серія»: `lib/services/episode_alerts.dart` (`EpisodeAlerts.instance`: `check` — стрічка Mikai `GET /updates?since=` звіряється з тайтлами з `WatchStore` і їхньою обраною озвучкою Mikai (`releaseId` = id релізу); `items`, `unread`, `markRead`, `markAllRead`, `clear`, `tracked`); перевірка за 6 с після запуску й при поверненні в застосунок (`main.dart`, `player_screen.dart`); сторінка `HikkaNotificationsPage` (`hikka_notifications_page.dart`, маршрут `HikkaRouteKind.notifications`, `HikkaNav.openNotifications`) — список + «Прочитати все», потяг вниз / «Оновити» перевіряють стрічку; лічильник на дзвіночку в `_TopBar`.

Примітка (b100+): лінійні іконки — `lib/widgets/line_icons.dart`, спільні блоки нового дизайну — `lib/widgets/design_kit.dart` і `app_tones.dart` (див. їхні записи). `SettingsChoiceRow(leading:)` — свій малюнок замість іконки. `test/player_preview_test.dart` — прев'ю плеєра для звірки з концептом П1–П6 (справжній кадр із `/tmp/concept/player/img`: телефон в альбомній з керуванням і «Пропустити опенінг», шторка налаштувань, «Перегляд», портрет; ПК з кадром під курсором, меню від шестерні й OSD гучності; лише з `PREVIEW=1` → `test/preview/player_p*.png`). `test/remote_ui_test.dart` — панель «Перегляд» у плеєрі (плашки, діапазони, озвучення, якість і плеєр). `test/pages_perf_test.dart` — швидкодія всіх сторінок із великим вмістом на телефоні (412 dp, 2,8) і ПК (1280×720) з даними як у важких випадках (каталог 700, списки 840, календар на два тижні, людина з 450 роботами, франшиза 64, колекція 150, довга стаття, 100 сповіщень, 1150 серій у «Перегляді», пошук і фільтри, перемикання вкладок): відкриття, прокрутка з довантаженням, прокрутка назад, 2 с спокою; перевіряє, що нерухома сторінка не просить кадрів, кадр прокрутки перебудовує мало, оболонка не перебудовується, довгий список будує лише видиме; наприкінці таблиця (і файл із `PERF_REPORT`) з найважчим кадром і тим, звідки почалися перебудови («Image ← HikkaPoster…»). Помічники — `test/support/page_perf.dart` (`PerfFrames`, `PerfRebuilds.roots()`, `perfScroll`, `perfIdleFrames`, `mountPerfHub`, генератори `PerfData`). `test/json_worker_test.dart` — `JsonWorker` і запис сирої відповіді на диск; `test/flutter_test_config.dart` піднімає поріг `JsonWorker` для всіх тестів. `test/title_preview_test.dart` — прев'ю як на телефоні (412 dp, справжні картинки Фрірен із `/tmp/concept/img`, вхід, «Дивлюсь», Mikai з Inari) для звірки з дизайном: сторінка тайтла, усі головні вкладки й сторінки (`screens`), 520 dp (`tabs520`), вікна й меню (`modals`: М1, М3–М5, Л2, Л4, Л5, Л7) і гість (Л6); запускається лише з `PREVIEW=1` (`PREVIEW=1 flutter test --update-goldens test/title_preview_test.dart` → `test/preview/*.png`).

Примітка (оновлення в застосунку, адмін-панель): нові файли — `lib/services/app_updater.dart` (завантаження й встановлення), `lib/services/admin_api.dart`, `lib/widgets/hikka/hikka_admin_page.dart`, `tools/backend/admin.ts`, `android/app/src/main/res/xml/update_paths.xml`; залежність `crypto` (SHA-256), `androidx.core:core` у `android/app/build.gradle.kts` (FileProvider). `LineIcon.shield` — значок адмін-панелі. Тести: `test/app_updater_test.dart` (група «завантаження»: `FakeServer` з `Range`, обрив, скасування, контрольна сума, Android-дозвіл, Windows), `test/update_prompt_test.dart` (стани вікна; завантаження в `tester.runAsync`), `test/deep_links_test.dart` (`update`, `notifications`), `test/admin_panel_test.dart` (`FakeAdminServer` — функція `admin`; `signedIn(username)`), `test/update_flow_test.dart` (вікно на справжньому `HomeHub` через `mountPerfHub`: запит із повідомлення до появи екрана, завантаження, що скінчилося за повним плеєром чи на відкритому екрані).

Примітка (звук): затримка й моно — `MpvConfig.audioOptions` (`gapless-audio=weak`, Android `ao=audiotrack,opensles`), `AudioRouteGuard` (`ao-reload` після зміни пристрою виводу, пауза, коли навушники зняли; Android — `AudioDeviceCallback` і `ACTION_AUDIO_BECOMING_NOISY` у `MainActivity.kt`), рядки виходу звуку mpv (`AO: …`, повідомлення `ao/…`) — у журнал під тегом `звук` (`PlayerStateController`, слухач `player.stream.log`). Перевірка поведінки mpv: `tools/audio_bench.py` (потрібні mpv, ffmpeg, numpy; файли — `tools/.audio_bench/`, у git не йдуть). Тест `test/audio_output_test.dart`.
