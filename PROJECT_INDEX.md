# PROJECT_INDEX — Miki Miki (Flutter: Windows + Android)

> Індекс для швидкої навігації. Читай ЦЕЙ файл замість сканування lib/. Номери рядків орієнтовні (оновлюй після великих змін).

## Ключові правила
- Теми/кольори: тільки через `uiTheme` (`lib/services/ui_theme_service.dart`), не через AppConstants.
- Назва застосунку (Miki Miki) і технічні ідентифікатори — лише з `AppIdentity` (`lib/constants/app_identity.dart`): `name` («Miki Miki», для людей), `shortName` («MikiMiki»: теки, знімки екрана, `User-Agent`), `packageName` («miki_miki»: пакет Dart, префікс журналів і файлів звіту, канал `miki_miki/system`), `dataDirName` («MikiMiki»: `%APPDATA%/MikiMiki`, `files/MikiMiki`, кеші `hikka_images`, `thumbnails`), `legacyDataDirName` («MyPlayerFork»), `tagline`, `version` (синхронна з `pubspec.yaml`), `userAgent(purpose)`, `migrateLegacyData` (перший запуск на ПК: якщо теки `MikiMiki` ще немає, а `MyPlayerFork` є — її перейменовано чи скопійовано; не кидає винятків; на Android це інший застосунок із власною текою). Рядком «Miki Miki» у коді не писати. Поза Dart назва живе в: `pubspec.yaml` (`name: miki_miki` — звідси імпорти `package:miki_miki/…` у тестах), `android/app/build.gradle.kts` (`namespace` і `applicationId` = `com.mikimiki.app`), `AndroidManifest.xml` (`android:label`), `MainActivity.kt` (пакет `com.mikimiki.app`, канал `miki_miki/system`), `windows/CMakeLists.txt` (`project(miki_miki)`, `BINARY_NAME` = «MikiMiki» → `MikiMiki.exe`), `windows/runner/Runner.rc` і `main.cpp` (заголовок вікна), `README.md`, `CLAUDE.md`, `.idea`. Знак застосунку поки тимчасовий (монограма «M» у бічному меню, `Symbols.smart_display_rounded` у «Про програму»); маскот замінить його, коли буде готовий.
- Банери «Головної»: `BannerArt.instance.load(List<HikkaAnime>)` (`services/banner_art.dart`) → `Map<MAL-id, BannerArtwork>`: спершу AniList (`AniListBanners`: один GraphQL-запит на ≤50 MAL-id, `bannerImage` і `coverImage.color`), для тих, у кого банера немає, — TheMovieDB (`TmdbBackdrops`, лише з ключем: `StorageService.getTmdbKey` — «Налаштування → Розробник → Банери на головній» або `--dart-define=TMDB_KEY=…`; ключ v3 іде параметром `api_key`, v4 («read access token», `eyJ…`) — заголовком Bearer). Кеш на диску (розділ `banner_art` у `StorageService`): знайдений банер — 14 днів, «банера немає» — 2 дні, до 400 записів. Збій AniList не кидає виняток і нічого не записує: віддаються лише застарілі записи кешу. Поки банера немає чи він вантажиться — той самий постер, прокручений крізь крихітну копію (~40 px, `FilterQuality.medium`; без `BackdropFilter`, бо той вбиває кадри). Джерела, які треба називати в «Про програму» й у підписі профілю: Hikka (дані), AniList (банери), TheMovieDB (запасні банери; «використовує TMDB API, але не схвалений і не сертифікований TMDB»).
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
- Android / телефон: у проєкті є `android/` (збірка: `flutter build apk --release --target-platform android-arm64`, потрібен Android SDK; libmpv — `media_kit_libs_android_video`; AGP 8.13.2 / Gradle 8.14.3 в `settings.gradle.kts` і `gradle-wrapper.properties` — file_picker 11 не збирається з AGP 9). Віконні функції (`window_manager`, міні-плеєр, «поверх усіх вікон», повний екран) — лише коли `AppPlatform.isDesktop`. Платформа — `AppPlatform` (`lib/utils/platform_info.dart`): `isMobile`/`isDesktop` (`debugMobile` — перевизначення для тестів), `defaultHwdec` (Windows `d3d11va-copy`, Android `mediacodec-copy`), `mobileScale` (1.15, лише для старих віджетів), `touchTarget` (48 dp); розкладка екрана — `AppLayout(size)` (portrait/landscape, `isCompactWidth` < 640, `isShortHeight` < 520).
- Мобільний інтерфейс (`PlayerScreen._mobilePlayer`, шари знизу вгору): відео на весь екран → `MobileGestureLayer` (вертикально ліворуч — яскравість, праворуч — системна гучність, горизонтально — перемотка; математика в `TouchGestureMath`) → `SkipButton(touch: true)` → `MobileControls` (угорі: назад / назва / PiP / поворот / налаштування; по центру: попередня · −N с · пауза · +N с · наступна; унизу: повзунок із часом і ряд швидкість · Anime4K · субтитри · звук · епізоди; усе ≥ 48 dp, розміри в dp, а не `* scale`) → `MobileSheetFrame` (портрет — нижня панель до 68 % висоти, альбомна — бічна справа) з `SettingsDrawer(sheet: true)` / `SidePanel(sheet: true)` → `OsdToast`. Тап по відео показує/ховає панелі (`PlayerStateController.toggleControlsByTouch()`, `touchActivity()`, таймер `TouchHideTimer` 4 с; на паузі, з відкритим меню чи панеллю не ховає). Головна: `HomeHub` у вузькому портреті (`HomeHub.isCompact`) має нижню навігацію з чотирма вкладками (`MainTab`: Головна · Огляд · Списки · Профіль); `AppSettingsDialog` на телефоні на весь екран (портрет — рядок вкладок, альбомна — бічне меню).
- Android-можливості — канал `miki_miki/system` (`SystemControls`, `android/app/src/main/kotlin/com/mikimiki/app/MainActivity.kt`): PiP (`enterPip`; автовхід `setPipAuto` лише поки йде відтворення; у вікні PiP лишається тільки відео), яскравість вікна (жест; на головній — системна, `resetBrightness`/`restoreBrightness`), системна гучність. Орієнтація вільна (датчик / системний автоповорот, `main.dart`); кнопка повороту в плеєрі фіксує портрет ↔ альбомну (`PlayerStateController.toggleRotation`, довге натискання або вихід на головну — `unlockRotation`). Системна «Назад» — `PopScope` у `PlayerScreen` → `handleBack()`; коли застосунок у фоні (не PiP), відео ставиться на паузу й позиція зберігається (`onAppBackgrounded`). Стан застосунку на Android лежить у постійній теці `files/MikiMiki` (застосунок `com.mikimiki.app` має власну приватну теку: старий `com.example.my_player` — окремий застосунок, його дані не переносяться). Правила для нових мобільних віджетів: розміри в dp, цілі дотику ≥ `AppPlatform.touchTarget`, підказки клавіатури не показувати (`!AppPlatform.isMobile`), меню — через `MobileSheetFrame`.
- Ще не зроблено для телефона: легші мініатюри/прев'ю (зараз «безголовий» libmpv), шрифт Arial відсутній (Roboto), сповіщення/медіа-сесія (керування з шторки), підписання release-збірки власним ключем.
- Навігація й вміст (Miki Miki — «hikka-first»: усе, що бачить людина, — це дані hikka.io; аніме, манґи й ранобе в каталозі немає): чотири головні вкладки `MainTab` — «Головна», «Огляд», «Списки», «Профіль». `HomeHub` (`widgets/home_hub.dart`) — лише оболонка: нижня навігація на телефоні в портреті, `AppSidebar` (монограма «M» як тимчасовий знак, назва й підпис з `AppIdentity`, «Налаштування», версія) на ПК і широких екранах; налаштування відкриваються з «Профілю» й знизу бічного меню (`onOpenSettings({int? tab})` → `AppSettingsDialog.show(initialTab:)`). `HikkaHub` (`widgets/hikka/hikka_hub.dart`) тримає вкладки (`HikkaHomePage`, `HikkaDiscoverPage`, `HikkaListsPage`, `HikkaProfilePage`; будуються ліниво й після відкриття не руйнуються — `Offstage` + `TickerMode`, тож пошук і прокрутка лишаються на місці) і шар відкритих сторінок `HikkaRoute` поверх них (`AppFadeSwitcher`, `HikkaBackBar` з «Оновити» та «Відкрити на hikka.io»). `HikkaNav` — одинак (`ChangeNotifier`; власний стек, не `Navigator`): `setMain(MainTab)`, `setTab(HikkaTab)` (розділи «Огляду»: Усе · Календар · Каталог · Колекції · Статті · Персонажі), `openCatalog(HikkaSearchFilters, {focusSearch})` / `openSearch()` (+ одноразові `takePendingFilters` / `takeFocusSearch`), `openAnime` / `openCharacter` / `openFranchise` / `openAnimeCharacters` / `openCollection` / `openArticle` / `openLocalLibrary`, `openLink(url)` (посилання з описів і статей), `back()` з охоронцями `addBackGuard`. «Назад»: `HomeHub.backHandler` (статичний хук; викликає `PlayerScreen._wrapMobile` після `handleBack()`) = `HikkaNav.back()`: охоронці (панель фільтрів тощо) → сторінки зі стеку → з кореня іншої вкладки на «Головну»; на «Головній» повертає `false` — тоді екран плеєра вирішує, чи виходити із застосунку. Мишача кнопка «Назад» теж працює (`kBackMouseButton`). Нова сторінка = новий `HikkaRouteKind` + `HikkaNav.openXxx` + гілка в `HikkaHub._page` + заголовок / адреса в `_routeTitle` / `_routeUrl`.
- Головна (`HikkaHomePage`): рядок пошуку (дотик → `HikkaNav.openSearch()`) і сповіщення (заглушка `HikkaNotificationsDialog`: нові серії й озвучки з Hikka та Mikai зʼявляться після входу), тонка стрічка календаря `HikkaAiringStrip` (які серії щойно вийшли й які вийдуть; підпис — `HikkaAiring.of(entry, now)`; «Календар» → `setTab(HikkaTab.schedule)`), банери поточних онґоїнґів `HikkaBannerCarousel` (гортаються самі; фон — `BannerArt`, див. правило нижче), полиці «Продовжити перегляд» (`ContinueWatching.load`; порожня — не показується), «Рекомендації», «Зараз виходить», «Анонси», «Найпопулярніші», «Найкращі за оцінкою». На телефоні вкладка оновлюється потягом вниз (`HikkaPageFrame.onRefresh`), на ПК — кнопка «Оновити».
- Акаунт Hikka (вхід, списки, прогрес; з v1.0.3). `HikkaAuth` (`services/hikka_auth.dart`, `HikkaAuth.instance`, ChangeNotifier; фази `HikkaAuthPhase`: signedOut / waiting / exchanging / signedIn; дані — розділ сховища `hikka_auth`: `token`, `me`, `sync`, власний клієнт `client_ref` / `client_secret`). Потік входу (застосунок третьої сторони, як на hikka.io/oauth): `startLogin()` піднімає тимчасовий сервер `HikkaLoopback` на `127.0.0.1:47615` (лише GET `/auth/confirm`, Host тільки `127.0.0.1`/`localhost`; гасне після входу чи скасування) і відкриває `https://hikka.io/oauth?reference=<клієнт>&scope=user-details,watchlist,favourite`; людина тисне «Продовжити» — сайт перекидає на зареєстровану адресу клієнта з кодом запиту (`HikkaAuth.redirectUri` = `http://127.0.0.1:47615/auth/confirm` — саме її вписано як «endpoint» клієнта на hikka.io; окремий домен не потрібен) → `POST /auth/token {request_reference, client_secret}` → токен → `GET /user/me`. Запасний шлях без порту: людина вставляє адресу, на яку її перекинуло, або сам код — `submit()` / `parseReference()` (UUID, `reference=` / `request_reference=`). Токен іде заголовком `auth: <секрет>` лише в запитах `HikkaApi._request(auth: true)`; 400 із кодами `auth:*` → `HikkaErrorKind.unauthorized` → `onUnauthorized` розлогінює («Сесія Hikka завершилась»); `HikkaApi.sharedTokenProvider` / `sharedOnUnauthorized` — статичні, щоб підміна `HikkaApi.instance` у тестах не відчепила токен. Вихід `signOut()` відкликає токен (`GET /auth/token/info` → `DELETE /auth/token/{ref}`), але локально виходить завжди. Сторінка згоди показує «Невідомий застосунок», доки Hikka не позначить клієнта верифікованим — це нормально. Схему всіх методів можна взяти з `https://api.hikka.io/openapi.json` (звірено з v0.4.4: `WatchArgs` — `status` обовʼязковий, дати рядком date-time; `WatchResponse` — дати числами; `TokenProceedArgs`, `TokenResponse{secret, created, expiration}`, `TokenRequestResponse{reference, redirect_url, expiration}`, `AuthTokenInfoResponse{reference, scope, expiration…}`; запити акаунта — заголовок або кукі `auth`).
- Клієнт Hikka (референс і ключ застосунку) — ЛИШЕ `HikkaClientKey` (`services/hikka_client_key.dart`): значення зберігаються замаскованими (XOR двох масивів), а НЕ рядками; жодних літералів ключа чи референсу в коді, тестах (там `HikkaClientKey.testOverride`), журналі, індексі та відповідях. Свій клієнт людина вписує в «Налаштування каталогу → Свій клієнт Hikka» (`HikkaAuth.setCustomClient`; діє при наступному вході, має перевагу). Якщо секрет на hikka.io перестворили, вбудований перестає працювати: треба замінити масиви в `HikkaClientKey` на нові (нове значення дає користувач у чаті; у файли, тести й індекс його не писати, у відповідях не повторювати).
- Списки Hikka: `HikkaMyList` (`services/hikka_lists.dart`, `HikkaMyList.instance`, ChangeNotifier; скидається при вході й виході): `entry(slug)` — мій запис (`GET /watch/{slug}`, 404 = немає; кеш у памʼяті), `save(slug, {status, episodes, score, total})` (`PUT /watch/{slug}` — завжди повний запис, щоб не стерти оцінку, нотатку, дати; «Переглянуто» добиває лічильник до кінця, лічильник не перевищує кількість серій), `remove`, `stats()`, улюблене `isFavourite` / `setFavourite`, `version` (росте при змінах — за ним перезавантажується «Списки»). Моделі — `models/hikka_user_models.dart` (`HikkaWatchStatus` watching / planned / completed / on_hold / dropped, `HikkaWatchEntry`, `HikkaWatchStats`, `HikkaMe`, `HikkaToken`). UI: `HikkaAccountCard` і `HikkaLoginDialog` (`widgets/hikka/hikka_account_ui.dart`; у «Профілі» й у «Списках» для гостя); «Списки» після входу — чипи статусів із лічильниками («Дивлюсь · N») + «Улюблене», картки з плашкою `серії/всього` (для «Дивлюсь», «Відкладено», «Кинуто») і `★ оцінка` в підписі, довге натискання / права кнопка — «Прибрати зі списку»; на сторінці аніме блок «Мій список» (`HikkaMyListBar` у `hikka_my_list_bar.dart`, між оцінками й блоком «Дивитись»: гість — «Додати в список» → вхід; далі плитка статусу, прогресу й оцінки → `HikkaListEditDialog`; серце «В улюблене»).
- Прогрес із плеєра: `RemoteDriver._markWatched` для ключів `hikka:<slug>` викликає `HikkaMyList.syncEpisode(slug, номер, total:)` (без `await`, збої тихі; лише коли ввійшли й увімкнено `HikkaAuth.syncProgress`): тайтл потрапляє в «Дивлюсь», лічильник серій лише зростає, після останньої серії — «Переглянуто»; вже «Переглянуто» не чіпається. Номер — `HikkaMyList.episodeNumber(number, position, total)` (номер із джерела, якщо він цілий і не більший за кількість серій, інакше позиція серії в черзі).
- «Огляд» (`HikkaDiscoverPage`) — розділи: «Колекції» (`HikkaCollectionsPage` → `HikkaCollectionPage`) і «Статті» (`HikkaArticlesPage` → `HikkaArticlePage`) — користувацький вміст Hikka (`HikkaApi.collections/collection/articles/article`, моделі — `hikka_community_models.dart`, текст статей — документ Slate, малює `HikkaSlateView`: абзаци, заголовки, списки, цитати, спойлери, картинки з переглядом `HikkaImageViewer`, відео, посилання всередину застосунку); «Каталог» (`HikkaCatalogPage`); «Персонажі»; «Календар». Списки з підвантаженням — `HikkaPagedList<T>`; картки — `HikkaCollectionCard` / `HikkaArticleCard` (`hikka_community_cards.dart`). Колекції з позначкою 18+ ховаються, поки вимкнено `HikkaPrefs.allowAdult`.
- «Списки» (`HikkaListsPage`) — для гостя картка входу й пояснення, що буде після входу (Дивлюсь · У планах · Переглянуто · Відкладено · Кинуто · Улюблене); після входу — вкладки статусів із лічильниками та «Улюблене» (правило «Акаунт Hikka» нижче). «Профіль» (`HikkaProfilePage`) — картка акаунта `HikkaAccountCard` (гість: «Увійти через Hikka»; після входу: імʼя, перемикач «Передавати прогрес у списки», «Вийти з акаунта»), «Налаштування застосунку» (`AppSettingsDialog`), «Каталог і дані» (`HikkaSettingsDialog`), «Джерела перегляду» (`SourcesDialog`), «Про Miki Miki» (`AppSettingsDialog.tabAbout`), прихована «Локальна медіатека» й підпис джерел даних.
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
- Звірка з Hikka (`episode_check.dart`, `checkEpisodes(episodes, HikkaEpisodeInfo)`): рівні `match / unknown / lag / incomplete / lead / extra / mismatch`. Розбіжність нумерації — злиті частини («24 з 12»), наскрізна 13–24, повтори номерів, OVA посеред сезону, пропуски, кілька сезонів, серії без номерів — це `mismatch`: показати дисклеймер і не синхронізувати «переглянуто» з Hikka (`syncSafe == false`). OVA лише в кінці → `extra` із `syncLimit` (синхронізувати до цього номера). «0 з N» (сторінка є, серій немає) → `incomplete` / `lag`. `looksLikeExtra(name)` визнає OVA лише за позначкою на початку назви чи в дужках («Серія 12. Special Training» — звичайна серія).
- Тести (`test/`; запуск: `flutter test test/sources_*_test.dart test/watch_services_test.dart test/watch_pick_test.dart test/track_defaults_test.dart test/hls_proxy_test.dart test/app_log_test.dart test/orientation_policy_test.dart test/player_diagnostics_test.dart test/remote_playback_test.dart test/remote_driver_test.dart test/hikka_core_test.dart test/identity_test.dart test/hikka_community_test.dart test/hikka_slate_test.dart test/home_services_test.dart test/hikka_franchise_test.dart test/hikka_markdown_test.dart test/touch_hide_timer_test.dart test/anime4k_test.dart`): детерміновані, без мережі (сторінки сайтів — `test/data/sources/*`, відповіді Hikka — `test/support/hikka_fakes.dart`). `sources_live_test.dart` ходить у справжні сайти (UFDub, Mikai, UAKino) лише з `LIVE=1` (транспорт застосунку; з `LIVE_CURL=1` — через `curl`, `test/support/curl_sender.dart`, для пісочниць без прямого `dart:io`). Драйвер перегляду — `remote_driver_test.dart` (`test/support/remote_fakes.dart`: `FakeEngine`, `FakeSource`, `Rig` — стенд із драйвером, сховищем у пам'яті й керованими плеєрами). Віджетні тести (`remote_ui_test.dart`, `hikka_watch_ui_test.dart`, `hikka_ui_test.dart` та інші з `loadTestFonts()` з `test/support/fakes.dart`) прив'язані до шляхів шрифтів середовища, де їх писали, і до теки користувача не потрапляють. `watch_pick_test.dart` — який варіант відкриває «Дивитись» (`pickGroup`, `choiceKeyOf`, улюблені); `track_defaults_test.dart` — мови доріжок (`LangMatch`) і автовибір субтитрів та звуку (`TrackDefaults`). `Rig` у `remote_fakes.dart` має параметр `subLangs` (пріоритет мов субтитрів). `app_log_test.dart` — журнал (рівні, згортання повторів, маскування, файл, ротація, звіт) і збереження у файл (`LogExport`); `orientation_policy_test.dart` — орієнтація плеєра; `player_diagnostics_test.dart` — `analyzeSync`. У `hikka_core_test.dart` — повтори мережевих збоїв. `identity_test.dart` — `AppIdentity` (назви, `userAgent`, перенос даних зі старої теки); `hikka_community_test.dart` — колекції й статті Hikka (моделі, `HikkaApi`, Slate, посилання); `hikka_slate_test.dart` — текст статей (`HikkaSlateView`): розмітка, списки, цитати, посилання (власний обробник, каталог, браузер), спойлери, картинки й перегляд на весь екран. `home_services_test.dart` — `HikkaText.compact`, `HikkaAiring.of`, `ContinueWatching`, `AniListBanners` / `TmdbBackdrops` / `BannerArt` (кеш, TTL, запасний пошук). `HikkaTestEnv` (`test/support/hikka_fakes.dart`) — готовий стенд для віджетних тестів Hikka: підмінює `HikkaApi` (`FakeHikka`), зображення, `HikkaPrefs`, `WatchService`, `BannerArt` (AniList віддає банер лише для парних MAL-id; TMDB без ключа) і `HikkaNav` (`opened` — записані зовнішні посилання); `dispose()` повертає все назад. Віджетні тести `hikka_ui_test.dart` (десктоп, банери, телефон, оболонка `HomeHub`, стани, вузьке вікно) і `mobile_test.dart` використовують його. `FakeHikka.interceptor` — власні відповіді поверх записаних; `HikkaTestEnv` підставляє `HikkaAuth` (гість, без локального сервера, браузер — лише журнал `opened`) і `HikkaMyList`. Акаунт: `hikka_auth_test.dart` (потік входу, локальний сервер, запасне вставлення адреси, токен, вихід), `hikka_lists_test.dart` (запис, збереження без втрати полів, улюблене, синхронізація прогресу), `hikka_lists_ui_test.dart` (вхід у вікні, «Списки» зі статусами, «Мій список» на сторінці аніме, профіль; `FakeAccountServer` — стан акаунта, що змінюється запитами); підроблений сервер входу й списків для сервісних тестів — `test/support/hikka_account_fakes.dart`.
- Серії з сайтів у плеєрі: кнопки блоку «Дивитись» викликають `WatchLauncher.play(RemoteLaunch)` (`remote_playback.dart`); `PlayerScreen` підписується через `WatchLauncher.attach(state.openRemote)` (відписка в `dispose`) → `PlayerStateController.openRemote(launch)` → `RemoteDriver.start`. `RemoteDriver` (`lib/services/remote_driver.dart`) — чиста логіка без media_kit і віджетів: плеєр для нього — інтерфейс `RemoteEngine` (у застосунку `MpvRemoteEngine`, `remote_engine.dart`; у тестах `FakeEngine`). Фази `RemotePhase` (idle / resolving / opening / playing / failed). Посилання на потік шукається в момент відтворення (`StreamResolver`; живе кілька годин), місце початку передається опцією `Media.start`, позиція зберігається через `StorageService.savePlaybackPosition` (ключ запису `hikka:<slug>#<серія>`), «переглянуто» — за `episodeSeen` (≥ 85 % або ендінґ), автоперехід — за `StorageService.getAutoplayNext()`. Сторож запуску: 30 с (`openTimeout`) і 6 с після помилки mpv (`errorGrace`; помилки бувають дрібні) → наступний не пробований плеєр → «Не вдалося» з «Повторити»; якщо потік завис посеред перегляду — нове посилання з того ж місця (`_recover`, не частіше ніж раз на 30 с).
- Чого не можна робити із серіями з сайтів: у mpv відкрите лише одне відео, тому в `player.playlist` лежать «синтетичні» елементи `remote://<ключ>` (щоб працювали черга, `currentPlaylistIndex` і заголовок) — `player.next()/previous()`, `reorderQueue` / `removeFromQueue` / `persistQueue` для них не викликати: «Наступна / Попередня» — це `PlayerStateController.playNext()/playPrevious()` (самі розрізняють файли й серії; їх передають у `BottomDock` / `MobileControls` через `onNext` / `onPrevious`), вибір серії — `selectEpisode(i)` (веде в драйвер). `currentFilePath` для серії = ключ запису; `SeekPreviewService.supports()` відхиляє адреси `схема://` (наведення на смужку не показує прев'ю потоку); `remote.stop()` викликають усі `open*` і `returnToHome`.
- Інтерфейс серій: `RemoteStatusOverlay` (`widgets/remote_status_overlay.dart`: «Шукаю відео…», помилка з діями «Спробувати ще / Інший плеєр / Озвучки та плеєри / Наступна серія / Закрити»; під час стану на телефоні ховається перемотка — `MobileControls.showTransport`), `RemotePanelBody` (`widgets/remote_panel.dart`: вкладки «Серії» / «Озвучка» / «Плеєр» (плеєр і якість) — перемикання на льоту з того ж місця). Бічна панель і шторка на телефоні показують його замість черги файлів, коли `state.remote.active` (`SidePanel(remote:)`, `SidePanelDrawer(remote:)`); «Інформація» показує серію, озвучку й плеєр (адресу потоку не показуємо). Розділи беруться з таймкодів Moon (`chaptersFromTimestamps`), тож «Пропустити опенінг» працює звичайним `SkipButton`.
- Блок «Дивитись» (`widgets/hikka/hikka_watch_section.dart`) стоїть під шапкою сторінки аніме (`HikkaAnimePage._top`: шапка → `_scores` (компактні оцінки) → `_watch()` → жанри → опис). Головна кнопка `_mainButton` — суцільна `AppAccentButton(solid, expand)`, видна з першої миті («Дивитись / Продовжити · серія N / Дивитись знову»), праворуч «⋮» (tooltip «Ще») → модалка `_openMenu`: «Серії» (модалка `_openEpisodes` із сіткою серій; тап запускає й закриває, утримання/права кнопка — позначка «переглянуто», понад 48 серій — «Показати всі»), «Про команду(и)», «Джерела, якість і плеєр» (`SourcesDialog`), «Оновити пошук», «Відкрити на сайті»; унизу — помилки/зауваження джерел (`_offerNotes`). Пошук ще нічого не дав → тап по головній кнопці: джерела вимкнено — модалка `WatchDialogs.noSources`, інакше підпис під кнопкою. Озвучку обирають перед стартом у випадному списку `AppDropdown` (`_variants`/`_option`: аватарка команди, назва, іконка виду, «N з M сер.», «оновлено ДД.ММ» з `WatchGroup.updatedAt`; жовтий — `episodeCheckWarns`); вибір → `WatchStore.setPreferredGroup` + `setFavoriteChoice`, так само перемикання в плеєрі. Під списком: `EpisodeNote` (лише за потреби), «З першої серії» й «Переглянуто N з M». Ліцензовано → картка «Ліцензовано в Україні» → «Все одно дивитись» → `WatchDialogs.confirmLicensed` (`_ack` лише на цей показ). Стан — `HikkaRoute.memo['watch']` (`WatchLoad`). Діалоги — `widgets/hikka/hikka_watch_dialogs.dart`.
- Прокрутка й карусель (v34): `main.dart` → `_AppScrollBehavior` (на краю — `StretchingOverscrollIndicator`, як в Android 12+, а не світіння); `AppScrollbar`/усі `RawScrollbar` — `thumbVisibility: false` + згасання за ~0,9 с (на ПК `interactive`); `HikkaBannerCarousel` на вузьких екранах безкінечна (`_loops` віртуальних кіл, `_loopMode`, перецентрування в `_tick`), на широких — зі стрибком на початок; `AppDropdownOption` має `leading/title/subtitle/subtitleIcon` (розширений вигляд пункту), `AppAccentButton.solid` — головна дія сторінки.
- Налаштування джерел перегляду — `SourcesDialog` (`widgets/hikka/sources_dialog.dart`): сайти, найбільша якість, плеєр за замовчуванням (Авто / Moon / Ashdi), ключ Mikai API; відкривається з блоку «Дивитись» (кнопка «Джерела») і з налаштувань каталогу (розділ «Перегляд»).
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

### `lib/main.dart` (78 р.)
Вхід: ініціалізація media_kit, StorageService (і window_manager — лише на десктопі), uiTheme, ThumbnailService. Десктоп: вікно 1280×720. Телефон: `SystemControls.init()`, вільна орієнтація (`setPreferredOrientations([])`), edge-to-edge, масштаб тексту обмежено 0.9–1.25. Запуск: `AppLog.instance.init(<appBasePath>/logs, detailed)` → `AppDiagnostics.instance.install()`; `MaterialApp.navigatorObservers: [AppNavObserver()]`. Назва вікна й застосунку — `AppIdentity.name`.

### `lib/models/hikka_community_models.dart` (266 р.)
Колекції й статті спільноти Hikka (`part of 'hikka_models.dart'`, чиста Dart-логіка): `HikkaAuthor` (автор), `HikkaCollectionEntry` (запис колекції: `anime`, `comment` автора, `label` розділу, `order`), `HikkaCollection` (`reference`, `title`, `description` — Markdown, `author`, `entries` — скільки записів усього, `voteScore`, `commentsCount`, `tags`, `labelsOrder`, `spoiler`, `nsfw`, `items` — записи; у списку лише перші), `SlateNode` (вузол документа редактора Slate: `type`, `text`, `bold` / `italic` / `underline` / `strike` / `code`, `url`, `children`; `isText`, `plainText`, `firstImage`, `parseList`; `fromJson` стійкий до сміття) і `HikkaArticle` (`slug`, `title`, `author`, `category`, `views`, `voteScore`, `commentsCount`, `tags`, `preview` — початок тексту, `document` — весь текст у Slate).

- **HikkaAuthor** (р.6)
- **HikkaCollectionEntry** (р.21)
- **HikkaCollection** (р.32)
- **SlateNode** (р.125)
- **HikkaArticle** (р.189)

### `lib/models/hikka_models.dart` (1034 р.)
Моделі API Hikka (чиста Dart-логіка): `HikkaAnime` (назви за мовою `title(lang)`, `isAdult`, `nextEpisode(now)`, `seasonLabel`, `episodesLabel`, студії, жанри, посилання, відео, OST, розклад, статистика), `HikkaPage<T>` (`{pagination, list}`), `HikkaCharacter` / `HikkaCharacterRole` / `HikkaCharacterAnime`, `HikkaCharacterVoice` (коди мов → українські назви, `groupByLanguage`), `HikkaStaff`, `HikkaScheduleEntry`, `HikkaRelation` / `HikkaFranchiseData`, `HikkaSearchFilters` (умови пошуку → тіло POST /anime, `copyWith`, `activeCount`) + `HikkaSortOption`, `HikkaTitleLang`; `HikkaText` — українські підписи значень API (статус, тип, сезон, вікова категорія, числа з нерозривним пробілом, `plural`, дні тижня). `HikkaText.compact(n)` — лічильники для карток («1,3 тис.», «2,4 млн»). Колекції й статті спільноти лежать в окремому файлі `hikka_community_models.dart` (`part`), але користуються тими самими допоміжними функціями розбору.

- **HikkaTitleLang** (р.32)
- **HikkaText** (р.45)
  - `mediaType()` р.132
  - `status()` р.133
  - `season()` р.134
  - `rating()` р.135
  - `source()` р.136
  - `seasonOfMonth()` р.139
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
- **HikkaEpisodeSlot** (р.316)
- **HikkaAnimeStats** (р.328)
- **HikkaAnime** (р.359)
- **HikkaPage** (р.570)
- **HikkaCharacter** (р.595)
- **HikkaCharacterRole** (р.650)
- **HikkaCharacterAnime** (р.661)
- **HikkaPerson** (р.671)
- **HikkaCharacterVoice** (р.692)
  - `groupByLanguage()` р.759
- **HikkaRole** (р.802)
- **HikkaStaff** (р.821)
- **HikkaScheduleEntry** (р.839)
- **HikkaRelation** (р.859)
- **HikkaFranchiseData** (р.885)
- **HikkaSortOption** (р.902)
- **HikkaSearchFilters** (р.915)
  - `copyWith()` р.957
  - `toBody()` р.1008

### `lib/models/hikka_user_models.dart` (175 р.)
Моделі акаунта Hikka: `HikkaWatchStatus` (watching «Дивлюсь», planned «У планах», completed «Переглянуто», onHold «Відкладено», dropped «Кинуто»; `api` — значення API, `label` — підпис, `fromApi`), `HikkaToken` (`secret`, `created`, `expiration`), `HikkaMe` (профіль без пошти; `toJson` для сховища), `HikkaWatchEntry` (`status`, `episodes`, `score`, `note`, `rewatches`, дати, `anime`; `copyWith`, `toArgs()` — повний запис для `PUT /watch/{slug}` без втрати полів), `HikkaWatchStats` (лічильники за статусами, `of(status)`, `total`).

- **HikkaWatchStatus** (р.7)
- **HikkaToken** (р.28)
- **HikkaMe** (р.43)
- **HikkaWatchEntry** (р.73)
- **HikkaWatchStats** (р.149)

### `lib/models/media_models.dart` (74 р.)
Моделі даних (файли, історія, глави). `VolumeState` — гучність + mute одним значенням (для `PlayerStateController.volumeState`).

- **VideoChapter** (р.3)
- **VolumeState** (р.17)
- **CachedSubtitleTrack** (р.30)
- **CachedAudioTrack** (р.40)
- **PlaybackStats** (р.50)

### `lib/models/source_models.dart` (251 р.)
Моделі джерел перегляду (Dart-версія `animesource.model` з Aniyomi; чиста логіка): `SAnime` (сторінка сайту: назва, оригінальна назва, постер, студія, жанри, `SAnimeStatus`, рік, серій вийшло / всього; `mergedWith`, `toJson` / `fromJson`), `SAnimePage` (сторінка видачі + `hasNextPage`), `SEpisode` (адреса, назва, номер, сезон, озвучка `voice`, службові `data`), `Track` (зовнішні субтитри / звук), `TimeStamp` + `ChapterType` (опенінґ / ендінґ / рекап…), `Video` (посилання, підпис якості, висота, заголовки, доріжки, таймкоди, `preferred`), `Hoster` (плеєр сайту з відкладеним завантаженням відео); `pickVideo(videos, maxHeight:)` — вибір якості (0 — найвища).

- **SAnimeStatus** (р.5)
- **SAnime** (р.8)
  - `mergedWith()` р.46
  - `toJson()` р.62
- **SAnimePage** (р.95)
- **SEpisode** (р.105)
- **Track** (р.150)
- **ChapterType** (р.157)
- **TimeStamp** (р.160)
- **Video** (р.170)
- **Hoster** (р.225)

### `lib/screens/player_screen.dart` (599 р.)
Кореневий екран: збирає HomeHub / VideoViewport + оверлеї + SidePanelDrawer, слухає PlayerStateController і uiTheme. Підключає `KeyboardShortcuts`, `OsdToast` і довідку клавіш (`state.onShowShortcuts` → `ShortcutsDialog`). Статистика (`StatsOverlay`) слухає лише `state.liveStats`, гучність у доці — `state.volumeState`. Телефон: `_mobilePlayer` (див. правило про мобільний інтерфейс), `_wrapMobile` (`PopScope` «Назад», кольори системних панелей), спостерігач життєвого циклу. `_wrapMobile`: «Назад» спершу віддається `HomeHub.backHandler` (сторінки каталогу), далі `handleBack()`. Серії із сайтів: `WatchLauncher.attach(state.openRemote)` в `initState` (відписка в `dispose`); `RemoteStatusOverlay(driver: state.remote)` поверх відео на десктопі й телефоні (`onOpenPanel` → `openSidePanel(episodes)`, `onClose` → `returnToHome`); `state.remote` передається в `SidePanelDrawer`; «попередня / наступна» (`state.playPrevious` / `playNext`) — у `ControlsOverlay` і `MobileControls`; підпис і `hasQueue` на телефоні для серій беруться з `remote.nowPlaying` / `hasNext || hasPrevious`. Перетягування на вікно: `onDragDone` → `state.handleDroppedFiles` (відео відкривається, самі субтитри додаються до відкритого відео); у шухляді налаштувань `onAddSubtitleFile: state.pickSubtitleFile`. `HomeHub(onOpenSettings: ({int? tab}) => AppSettingsDialog.show(…, initialTab: tab ?? 0))`.

- **PlayerScreen** (р.34)
- **_PlayerScreenState** (р.41)

### `lib/services/anime4k_controller.dart` (253 р.)
Стан і застосування Anime4K (ChangeNotifier): режим / якість / поріг пропуску за роздільністю, черга команд до mpv, OSD-відгук, повторне застосування після відкриття файлу, виявлення помилок шейдерів у логах рушія. Живе в `PlayerStateController.anime4k`. Результат застосування / вимкнення / помилки шейдера пишеться в `AppLog` (тег `anime4k`).

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

### `lib/services/app_diagnostics.dart` (252 р.)
Глобальна діагностика: `AppDiagnostics.instance.install()` (помилки Flutter й асинхронні, життєвий цикл, зміни розмірів, повільні кадри >40 мс у вікні 5 с, памʼять / стан пристрою раз на 15 с), `logEnvironment()` (шапка звіту), `describeAudioRoute()`, `AppDiagnostics.build` (позначка збірки); `AppNavObserver` — відкриття / закриття діалогів і панелей.

- **AppDiagnostics** (р.18)
  - `install()` р.42
  - `logEnvironment()` р.71
  - `describeAudioRoute()` р.120
  - `didChangeAppLifecycleState()` р.134
  - `didHaveMemoryPressure()` р.140
  - `didChangeMetrics()` р.146
- **AppNavObserver** (р.226)
  - `didPush()` р.228
  - `didPop()` р.233
  - `didRemove()` р.238
  - `didReplace()` р.243

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

### `lib/services/continue_watching.dart` (95 р.)
«Продовжити перегляд»: `ContinueWatching.recent({store, limit})` — тайтли Hikka (ключ `hikka:<slug>` у `WatchStore`) з останньою відкритою серією, найновіші першими; `load({store, api, limit, allowAdult})` → `ContinueItem` (`anime`, `episodeKey`, `at`, `episodeLabel` «Серія 3» / «Сезон 2 · серія 5», `episodeShort` «С2 · Е5»): запити до Hikka йдуть паралельно, збійні, 18+ (без дозволу) і завершені, повністю переглянуті тайтли пропускаються; `episodeCaption` / `episodeShort` — підписи за ключем серії.

- **ContinueItem** (р.11)
- **ContinueWatching** (р.27)
  - `episodeCaption()` р.34
  - `episodeShort()` р.42
  - `recent()` р.53
  - `load()` р.69

### `lib/services/episode_check.dart` (246 р.)
Звірка серій варіанта з Hikka (див. правило «Звірка з Hikka»): `checkEpisodes(episodes, HikkaEpisodeInfo)` / `checkGroup` → `EpisodeCheck` (`level`, `count`, `expected`, `summary` «24 з 12», `note` — текст дисклеймера, `hasNote`, `isWarning`, `syncSafe`, `syncLimit`), `looksLikeExtra(name)`.

- **EpisodeCheckLevel** (р.16)
- **HikkaEpisodeInfo** (р.40)
- **EpisodeCheck** (р.53)
  - `mismatch()` р.145
  - `extraNote()` р.214
  - `EpisodeCheck()` р.235

### `lib/services/hikka_api.dart` (639 р.)
Клієнт api.hikka.io (див. правило про дані Hikka; запити акаунта — `auth: true`, токен у заголовку `auth`, див. правило «Акаунт Hikka»): `HikkaApi.instance`, підставний `sender` / `retryDelay` для тестів, `networkCalls`, `clearCache()`; `HikkaException(kind, …)` з українським `message` (мережа / не знайдено / сервер / відповідь). Транспорт `_IoTransport` відкидає `HttpClient` після збою (м'яке закриття) і перевіряє DNS; `HikkaApi.describeError(e)`; повтори: мережа до 3 спроб, тайм-аут і 5xx / 429 — до 2; усе пишеться в `AppLog` (тег `hikka`). Колекції й статті: `collections({contentType, sort: 'popular' | 'new', page, size, allowAdult})` (колекції 18+ відкидаються, якщо `allowAdult` вимкнено), `collection(reference)`, `articles({category, sort: 'new' | 'top', page, size})`, `article(slug)`; `User-Agent` — `AppIdentity.userAgent`.

- **HikkaErrorKind** (р.14)
- **HikkaException** (р.16)
- **HikkaRequest** (р.42)
- **HikkaResponse** (р.50)
- **HikkaSender** (р.58)
- **_IoTransport** (р.66)
- **_CacheEntry** (р.123)
- **HikkaApi** (р.129)
  - `clearCache()` р.156
  - `describeError()` р.165
  - `searchAnime()` р.335
  - `anime()` р.352
  - `animeCharacters()` р.359
  - `animeStaff()` р.366
  - `recommendations()` р.373
  - `franchise()` р.384
  - `genres()` р.391
  - `schedule()` р.401
  - `character()` р.417
  - `searchCharacters()` р.425
  - `characterAnime()` р.436
  - `characterVoices()` р.446
  - `collections()` р.459
  - `collection()` р.481
  - `articles()` р.492
  - `article()` р.506
  - `exchangeToken()` р.556
  - `me()` р.564
  - `tokenReference()` р.567
  - `revokeToken()` р.569
  - `myWatch()` р.572
  - `saveWatch()` р.582
  - `removeWatch()` р.586
  - `watchList()` р.595
  - `watchStats()` р.611
  - `isFavourite()` р.615
  - `setFavourite()` р.626
  - `favourites()` р.635

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

### `lib/services/hikka_lists.dart` (196 р.)
Мої списки Hikka й прогрес із плеєра (правило «Акаунт Hikka»): `HikkaMyList` (ChangeNotifier; `instance`; кеш записів і улюбленого в памʼяті, скидається при вході/виході): `entry(slug)`, `cached`, `knows`, `save(slug, {status, episodes, score, total, anime})`, `remove`, `stats()`, `isFavourite`, `setFavourite`, `version`, `syncEpisode(slug, серія, {total})` (черга на тайтл, тихі збої), статичний `episodeNumber(number, position, total)`.

- **HikkaMyList** (р.15)
  - `entry()` р.74
  - `save()` р.87
  - `remove()` р.109
  - `stats()` р.117
  - `isFavourite()` р.128
  - `setFavourite()` р.135
  - `episodeNumber()` р.146
  - `syncEpisode()` р.158

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

### `lib/services/hikka_nav.dart` (231 р.)
Навігація застосунку: `MainTab` (Головна · Огляд · Списки · Профіль, `label`), `HikkaTab` (розділи «Огляду»: Усе · Календар · Каталог · Колекції · Статті · Персонажі), `HikkaRouteKind` / `HikkaRoute` (відкрита сторінка: вид, slug, `seed` — дані зі списку для миттєвої шапки, `scroll`, `memo`), `HikkaNav` — одинак `HikkaNav.instance` (`ChangeNotifier`; власний стек, не `Navigator`, до 40 сторінок): `main`, `tab`, `routes`, `top`, `canGoBack`; `setMain` (повторний тап по вкладці веде на її корінь), `setTab`, `openCatalog(filters, {focusSearch})` / `openSearch()` (одноразово: `takePendingFilters`, `takeFocusSearch` / `wantsSearchFocus`), `openAnime` / `openCharacter` / `openFranchise` / `openAnimeCharacters` / `openCollection` / `openArticle` / `openLocalLibrary` (повторне відкриття тієї самої сторінки згортається, порожній slug ігнорується), `openLink(url)` (всередину застосунку чи в браузер через `urlOpener`), `back()` (охоронці `addBackGuard` → стек → з іншої вкладки на «Головну» → `false`), `reset()`. Усе пишеться в `AppLog` (тег `навігація`).

- **MainTab** (р.9)
- **HikkaTab** (р.20)
- **HikkaRouteKind** (р.31)
- **HikkaRoute** (р.34)
- **HikkaNav** (р.63)
  - `setMain()` р.89
  - `setTab()` р.98
  - `openCatalog()` р.108
  - `openSearch()` р.119
  - `takePendingFilters()` р.122
  - `takeFocusSearch()` р.131
  - `openAnime()` р.148
  - `openCharacter()` р.152
  - `openFranchise()` р.156
  - `openAnimeCharacters()` р.160
  - `openCollection()` р.164
  - `openArticle()` р.168
  - `openLocalLibrary()` р.173
  - `openLink()` р.176
  - `addBackGuard()` р.196
  - `removeBackGuard()` р.198
  - `back()` р.202
  - `reset()` р.223

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

### `lib/services/mpv_config.dart` (237 р.)
Конфіг mpv (hwdec, video-sync) і збір статистики для Stats. Android: `androidSubtitleFontAsset` / `androidSubtitleFontName` — єдиний шрифт libass (системних у libmpv немає); `sub-font` і `sub-fonts-dir` на Android не виставляються. Теки даних — `AppIdentity.dataDirName`.

- **MpvConfig** (р.9)
  - `configureEngine()` р.15
  - `loadCustomMpvConf()` р.49
  - `applySubtitleStyles()` р.91
  - `fetchLiveStats()` р.142
  - `extractChapters()` р.197
  - `extractSubtitleTracks()` р.224
  - `extractAudioTracks()` р.231

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

### `lib/services/playback_clock.dart` (261 р.)
Єдиний «годинник відтворення» на плеєр (`PlaybackClock.of(player)`): одна підписка на потоки position/duration/buffer/playing і готові похідні (`seconds`, `permille`). `ClockValue` — значення, що сповіщає лише при зміні результату; `ClockProgress` — прогрес смужки, що сповіщає при зсуві на піксель (з режимом `live`); `ChapterMath` — чисті функції над розділами (поточний, «Пропустити»).

- **PlaybackClock** (р.16)
  - `of()` р.35
  - `release()` р.38
- **ClockValue** (р.95)
  - `refresh()` р.112
- **ClockProgress** (р.140)
- **ChapterMath** (р.223)
  - `indexAt()` р.227
  - `isSkippable()` р.236
  - `skippableFlags()` р.245
  - `skipIndexAt()` р.249

### `lib/services/player_actions.dart` (448 р.)
Таблиця дій гарячих клавіш: id з `ShortcutCatalog` → замикання (перемотка, швидкість, гучність, субтитри, зображення, Anime4K, вікно, скриншот…) з OSD-відгуком. `run(id)` виконує дію, `escape()` — поведінка Esc. Перемикання доріжок гарячими клавішами — `setSubtitleTrack(…, closeMenu: false)` / `setAudioTrack(…, closeMenu: false)`. Кожна гаряча клавіша пишеться в журнал (`клавіші`, debug).

- **PlayerActions** (р.18)
  - `has()` р.27
  - `run()` р.30
  - `escape()` р.291

### `lib/services/player_diagnostics.dart` (251 р.)
Події плеєра в журнал і знімок синхронізації кожні 3 с: `PlayerDiagnostics(player, context:)` (`start`, `sample`, `dispose`), `SyncSnapshot`, `analyzeSync(prev, cur)` — застереження (розбіжність A/V >0,1 с, ≥8 втрачених кадрів за знімок, позиція стоїть, відставання від годинника).

- **SyncSnapshot** (р.17)
- **PlayerDiagnostics** (р.71)
  - `start()` р.86
  - `sample()` р.188

### `lib/services/player_state_controller.dart` (1339 р.)
ГОЛОВНИЙ стан плеєра (ChangeNotifier): Player, VideoController, плейлист, драйвери/меню (drawerOwner, _drawerStack), side panel, stats, fullscreen, збереження позиції, live-знімок прев'ю. Також: `anime4k` (Anime4kController), `keyScheme` / `setKeyScheme()`, `osd` + `showOsd()`, прямі команди mpv (`mpv()`, `mpvGet()`), скриншот, always-on-top, `onShowShortcuts`. Часті значення — окремі нотифікатори, що не перебудовують екран: `liveStats` (опитування статистики, `currentStats`), `volumeState` (`VolumeState`). Наявність файлів черги перевіряється паралельно й асинхронно. Телефон: панелі показує тап (`toggleControlsByTouch()`, `touchActivity()`); `isInPip`, `pipSupported`, `enterPip()`, автовхід у PiP (`_syncPipArm`); `rotationLocked`, `toggleRotation()`, `unlockRotation()`; `handleBack()` (кнопка «Назад»); `onAppBackgrounded()` (пауза + збереження позиції); `showOsdMessage()` для жестів; системні панелі (immersive у плеєрі, edge-to-edge на головній) та яскравість синхронізує `_syncSystemUi()` при кожному `notifyListeners()`. `toggleFullscreen()` на телефоні нічого не робить. Серії із сайтів: поле `remote` (`RemoteDriver` + `MpvRemoteEngine`), `openRemote(RemoteLaunch)` (скидає панелі й розділи, запускає драйвер), `playNext()` / `playPrevious()` (файли → `player.next/previous`, серії → драйвер; на краях — OSD «Це остання / перша серія»), `openSidePanel(type)`, `selectEpisode(i)` у режимі серій веде в `remote.open`. `_bindRemote()`: `onSession` / `onEntry` наповнюють `playlistItems` синтетичними `remote://…` і виставляють заголовок, розділи (`currentChapters` з таймкодів), `onMessage` → `showOsd`. У потоках плеєра: тривалість → `remote.onDuration`, завершення → `onCompleted`, помилка → `onPlayerError`, тік → `tick`. Операції з чергою файлів (`persistQueue`, `addMediaToQueue`, `reorderQueue`, `removeFromQueue`, `clearQueueExceptCurrent`) для серій нічого не роблять; `remote.stop()` — у кожному `open*` і в `returnToHome`. Субтитри й звук: `_applyTrackDefaults(tracks)` (автовибір за мовами з налаштувань через `TrackDefaults.plan`; пропускається після ручного вибору `_trackChoiceManual` і для серій із сайтів; `_resetAutoTracks()` у кожному `open*` і при зміні елемента черги; OSD «Субтитри»), `setSubtitleTrack` / `setAudioTrack(track, {closeMenu})`, зовнішні субтитри `addExternalSubtitle(path)`, `handleDroppedFiles(paths)`, `pickSubtitleFile()`, `subtitleExtensions`, `isSubtitleFile`. `PlayerConfiguration(libass: true, libassAndroidFont: …)` — шрифт для субтитрів на Android. Журнал і орієнтація: тег `дія` у публічних методах; `PlayerDiagnostics` (`_diag`, контекст — шейдери / джерело / PiP, `_diagContext`); `PlayerConfiguration.logLevel` = `v` у детальному режимі, докладні рядки libmpv не потрапляють у `mpvLogs` (лише у файл); орієнтація — `_orientation` (`OrientationPolicy`), `rotationLocked` — геттер, `refreshOrientationPreference()`, `_syncSystemUi` викликає `enterPlayer` / `leavePlayer`. Знімки кадру лягають у `Зображення/MikiMiki` (`AppIdentity.shortName`). Затримка звуку: `audioDelayKey` (серії — `r|animeKey|озвучка`, файли — `l|тека`), `_applyAudioDelay()` викликається на першу тривалість нового файлу й повертає твору його `audio-delay` (mpv інакше тягне значення попередньої серії). `returnToHome()`: `isCollapsed = false` ставиться лише перед фінальним `notifyListeners()`, щоб «хрестик» мініплеєра не розгортав плеєр (і не мигала орієнтація).

- **PlayerStateController** (р.39)
  - `collapsePlayer()` р.144
  - `expandPlayer()` р.154
  - `init()` р.162
  - `pointerInZone()` р.344
  - `refreshSettings()` р.360
  - `handleInteraction()` р.362
  - `toggleControlsByTouch()` р.365
  - `touchActivity()` р.380
  - `refreshOrientationPreference()` р.404
  - `notifyListeners()` р.429
  - `showOsdMessage()` р.496
  - `enterPip()` р.499
  - `toggleRotation()` р.517
  - `unlockRotation()` р.533
  - `handleBack()` р.544
  - `onAppBackgrounded()` р.570
  - `persistQueue()` р.603
  - `openQueue()` р.610
  - `openFileOrPlaylist()` р.659
  - `openMultipleFiles()` р.686
  - `pickAndOpenFile()` р.717
  - `addMediaToQueue()` р.727
  - `reorderQueue()` р.748
  - `removeFromQueue()` р.761
  - `clearQueueExceptCurrent()` р.772
  - `selectEpisode()` р.785
  - `playNext()` р.800
  - `playPrevious()` р.810
  - `openRemote()` р.822
  - `openDrawer()` р.865
  - `openSubDrawer()` р.882
  - `backDrawer()` р.888
  - `closeDrawers()` р.894
  - `closeSidePanel()` р.900
  - `toggleSidePanel()` р.906
  - `openSidePanel()` р.915
  - `setSpeed()` р.922
  - `setSubtitleTrack()` р.930
  - `setAudioTrack()` р.937
  - `addExternalSubtitle()` р.946
  - `isSubtitleFile()` р.958
  - `handleDroppedFiles()` р.965
  - `pickSubtitleFile()` р.980
  - `changeHwdec()` р.1032
  - `toggleFullscreen()` р.1045
  - `enterMiniPlayer()` р.1071
  - `exitMiniPlayer()` р.1103
  - `returnToHome()` р.1123
  - `openStatsOverlay()` р.1145
  - `closeStatsOverlay()` р.1162
  - `setVolumeDelta()` р.1175
  - `toggleMute()` р.1191
  - `mpv()` р.1206
  - `mpvGet()` р.1217
  - `showOsd()` р.1229
  - `setKeyScheme()` р.1255
  - `toggleAlwaysOnTop()` р.1262
  - `takeScreenshot()` р.1274

### `lib/services/playlist_service.dart` (56 р.)
Побудова плейлиста з файлу/теки.

- **PlaylistService** (р.6)

### `lib/services/remote_driver.dart` (564 р.)
Драйвер перегляду серій із сайтів (чиста логіка; правило «Серії з сайтів у плеєрі»). `_markWatched` для `hikka:<slug>` ще й передає серію в списки Hikka (`_syncToHikka` → `HikkaMyList.syncEpisode`, правило «Акаунт Hikka»). `RemoteEngine` — що потрібно від плеєра (`openVideo(video, {start})`, `position`, `duration`, `playing`, `addSubtitle` / `addAudio`), `RemotePhase` (idle / resolving / opening / playing / failed). `RemoteDriver` (ChangeNotifier): `start(RemoteLaunch)`, `open(i, {hoster, height, startAt, saveCurrent})`, `next()` / `previous()`, `retry()`, `switchGroup` / `switchHoster` / `switchQuality`, `stop({save})`; події плеєра `onDuration`, `tick`, `onCompleted`, `onPlayerError`; стан: `phase`, `error`, `session`, `title`, `groupId`, `group`, `isSub`, `index`, `entry`, `stream`, `video`, `hoster`, `chapters`, `attempt`, `hasNext` / `hasPrevious`, `active`, `showsStatus` (екран стану поверх відео), `alternativeHoster`, `nowPlaying({withKind})`; зворотні виклики контролера `onEntry`, `onSession`, `onMessage`. Токен (`_token`) відсікає відповіді застарілих запитів; між запитом посилання й початком відео стоїть таймер-сторож; повторне відкриття серії, що закінчилась одразу після старту з середини, починає її спочатку. Також: `checkOf(group)` (звірка варіанта з Hikka за `RemoteLaunch.hikka`); `switchGroup` запам'ятовує вибір (`setPreferredGroup` для тайтлу + `setFavoriteChoice(choiceKeyOf(g))` для нових); зовнішні субтитри варіанта «Субтитри» вмикаються за мовою з налаштувань (`LangMatch.pickByLabel`, інʼєкція `subPriorities`), а не просто перша доріжка.

- **RemoteEngine** (р.25)
- **RemotePhase** (р.43)
- **RemoteDriver** (р.60)
  - `nowPlaying()` р.175
  - `checkOf()` р.199
  - `start()` р.202
  - `open()` р.216
  - `next()` р.237
  - `previous()` р.243
  - `retry()` р.250
  - `switchGroup()` р.259
  - `switchHoster()` р.280
  - `switchQuality()` р.288
  - `onDuration()` р.301
  - `tick()` р.313
  - `onCompleted()` р.323
  - `onPlayerError()` р.348
  - `stop()` р.376

### `lib/services/remote_engine.dart` (54 р.)
`MpvRemoteEngine implements RemoteEngine` — міст між драйвером і media_kit: `openVideo` відкриває `Media(url, httpHeaders:, start:)` (заголовки й місце початку — до завантаження, без «стрибка»), `addSubtitle` / `addAudio` — команди mpv `sub-add` / `audio-add` (мова коротким кодом, довільний підпис іде в назву). Приймає `Player` і функцію команд mpv (`PlayerStateController.mpv`); імпортує media_kit лише `show Media, Player` (інакше `Track` / `Video` конфліктують з `source_models.dart`).

- **MpvRemoteEngine** (р.9)
  - `openVideo()` р.21
  - `addSubtitle()` р.40
  - `addAudio()` р.44

### `lib/services/remote_playback.dart` (138 р.)
Чиста логіка відтворення серій із сайтів: `chaptersFromTimestamps(stamps, total)` (розділи з таймкодів Moon; проміжки — розділи «Episode», що не пропонуються до пропуску), `episodeSeen(position, total, stamps)` (≥ 85 % або дійшли до ендінґа), `RemoteLaunch` (озвучка, серія, назва, постер → `session`, `startIndex`) і `WatchLauncher` (`attach` / `detach` / `play`) — міст між сторінками застосунку й плеєром. `RemoteLaunch.hikka` (`HikkaEpisodeInfo?`) — що Hikka каже про кількість серій: за цим плеєр показує, де нумерація може не збігатися.

- **RemoteLaunch** (р.78)
- **WatchLauncher** (р.118)
  - `attach()` р.123
  - `detach()` р.125
  - `play()` р.132

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

### `lib/services/source_registry.dart` (71 р.)
Реєстр джерел: `SourceRegistry.standard()` (Mikai, UFDub, UAKino зі спільним `SourceHttp`), `all`, `enabled`, `byId`, `mikai`; ключ Mikai підхоплюється з `SourcePrefs`. `SourceRegistry.instance`.

- **SourceRegistry** (р.14)
  - `byId()` р.59
  - `isEnabled()` р.68

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

### `lib/services/sources/episode_naming.dart` (24 р.)
Номер серії й сезону з людських назв («Серія 12 — …», «12 серія», «Сезон 2», «Episode 5»): `parseEpisodeNumber`, `parseSeasonNumber`, `looksLikeNumbered`.

### `lib/services/sources/extractors.dart` (411 р.)
Екстрактори плеєрів: `VideoExtractors.forUrl(url)` / `playerName(url)` / `plain(url)`, `AshdiExtractor` (`ashdi.vip/vod/<id>` → `index.m3u8`; серіальні сторінки), `MoonExtractor` (iframe `moonanime.art`: шаблони Video.js і PlayerJS, розшифровка двох шарів, субтитри, таймкоди `__skipSegments` / `__skipCtx`), `EmbedLink(provider, url)` + `encodeEmbeds` / `embedsOf` / `hostersFor` / `hosterVideosOf` / `videosOfEpisode` — як серія зберігає перелік своїх плеєрів у `SEpisode.data`; `embedHeaders(referer)` (заголовки як у iframe), `parseBracketList` («[Назва]посилання, …»), `subtitleLang`. Не підтримуваний плеєр → `SourceException(unsupported)`.

- **VideoExtractor** (р.42)
- **VideoExtractors** (р.54)
  - `moonViaProxyForTest()` р.58
  - `forUrl()` р.60
  - `playerName()` р.69
  - `plain()` р.82
- **AshdiExtractor** (р.111)
  - `canHandle()` р.118
  - `extract()` р.124
- **MoonExtractor** (р.152)
  - `canHandle()` р.159
  - `decodeLayer1()` р.178
  - `decodeXorString()` р.193
  - `extract()` р.280
- **EmbedLink** (р.334)

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

### `lib/services/sources/source_http.dart` (375 р.)
HTTP для джерел: `SourceHttp` (`get`, `postForm`, ручні редиректи, куки між запитами, `User-Agent`, підстановний `sender` для тестів), `SourceRequest` / `SourceResponse`, `CookieJar` (`store`, `headerFor`), `IoSourceTransport` (`dart:io`), `SourceException(kind, detail, {status})` з українським `message` + `SourceErrorKind` (`network`, `timeout`, `notFound`, `blocked`, `rateLimited`, `server`, `badResponse`, `unsupported`).

- **SourceErrorKind** (р.11)
- **SourceException** (р.13)
- **SourceRequest** (р.38)
- **SourceResponse** (р.61)
- **SourceSender** (р.112)
- **IoSourceTransport** (р.115)
- **CookieJar** (р.158)
  - `store()` р.161
  - `headerFor()` р.191
  - `clear()` р.202
  - `get()` р.204
- **SourceHttp** (р.219)
  - `encodeForm()` р.235
  - `parseUrl()` р.239
  - `get()` р.251
  - `postForm()` р.254
  - `resolve()` р.262
  - `send()` р.272

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

### `lib/services/sources/ua/mikai_source.dart` (475 р.)
Mikai (api.mikai.me/public/v1, без ключа 60 запитів/хв; ключ — заголовок `X-API-Key`): каталог (`popular` / `latest` / `search`), `byHikka(slug)` / `byMal(id)`, `player(anime)` → `MikaiPlayer` (релізи `MikaiRelease` по командах `MikaiTeam`, озвучення чи субтитри, `licensed` + `MikaiLicense`), `episodesOfRelease(release)` (серії лише з підтримуваними плеєрами; `voice` = підпис релізу), `teamInfo(team)` (опис і посилання команди). Кеш відповідей з TTL, 429 → `rateLimited`. `User-Agent` — `AppIdentity.userAgent`.

- **MikaiTeam** (р.14)
- **MikaiTeamInfo** (р.24)
- **MikaiEmbed** (р.50)
- **MikaiEpisode** (р.57)
- **MikaiRelease** (р.70)
- **MikaiLicense** (р.98)
- **MikaiPlayer** (р.105)
- **_Cached** (р.113)
- **MikaiSource** (р.119)
  - `clearCache()` р.146
  - `api()` р.148
  - `animeFromJson()` р.225
  - `teamFromJson()` р.258
  - `playerFromJson()` р.267
  - `popular()` р.345
  - `latest()` р.348
  - `search()` р.351
  - `details()` р.354
  - `byHikka()` р.362
  - `byMal()` р.375
  - `animeWebUrl()` р.387
  - `teamInfo()` р.391
  - `player()` р.417
  - `episodesOfRelease()` р.433
  - `flatten()` р.453
  - `episodes()` р.456
  - `hosters()` р.467
  - `hosterVideos()` р.470
  - `videos()` р.474

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

### `lib/services/storage_service.dart` (384 р.)
Збереження налаштувань, історії, позицій відтворення, черги й плейлистів. Ключі Anime4K: `getAnime4kEnabled/Mode/Quality/SkipHeight` + `save…`; схема клавіш: `getKeyScheme/saveKeyScheme`; `getHwdec()` за замовчуванням бере `AppPlatform.defaultHwdec`. Файл стану: Windows — `%APPDATA%/MikiMiki`, Android — `files/MikiMiki` (правило «Назва застосунку»). Каталог Hikka: `getHikkaTitleLang/saveHikkaTitleLang` (мова назв: ua / en / ja), `getHikkaAllowAdult/saveHikkaAllowAdult` (18+, типово вимкнено). Розділи для даних джерел перегляду: `getSection(key)` / `saveSection(key, map)` (типи `SectionLoader` / `SectionSaver`); їх використовують `SourcePrefs` і `WatchStore`. `getPlayerOrientation` / `savePlayerOrientation` ('system' | 'landscape' | 'portrait'), `getDetailedLog` / `saveDetailedLog` (типово true). Перейменування: теки даних — `AppIdentity.dataDirName` (`_basePathFor`), на ПК при старті `AppIdentity.migrateLegacyData` переносить `MyPlayerFork` → `MikiMiki`. Банери: `getTmdbKey` / `saveTmdbKey` (ключ TheMovieDB; запасне значення — `--dart-define=TMDB_KEY`). Приховане: `getLocalLibrary` / `saveLocalLibrary` / `localLibraryListenable` (локальна медіатека). Кнопки перемотки на телефоні: `getMobileSeekButtons/saveMobileSeekButtons` (ключ `mobile_seek_buttons`, типово true; вимикач у Налаштування → Відтворення, `MobileControls.seekButtons`). Затримка звуку твору: `getAudioDelay/saveAudioDelay(key, ms)` (мапа `audio_delays`, нуль видаляє запис).

- **SectionLoader** (р.10)
- **SectionSaver** (р.11)
- **StorageService** (р.13)
  - `init()` р.19
  - `flush()` р.69
  - `getPlaybackPosition()` р.79
  - `savePlaybackPosition()` р.84
  - `getSection()` р.97
  - `saveSection()` р.102
  - `getTmdbKey()` р.110
  - `saveTmdbKey()` р.112
  - `getLocalLibrary()` р.116
  - `saveLocalLibrary()` р.117
  - `getThemeMode()` р.129
  - `saveThemeMode()` р.130
  - `getAccentColorHex()` р.132
  - `saveAccentColorHex()` р.133
  - `getUiRadius()` р.135
  - `saveUiRadius()` р.136
  - `getAutoplayNext()` р.139
  - `saveAutoplayNext()` р.140
  - `getDefaultPlaybackSpeed()` р.142
  - `saveDefaultPlaybackSpeed()` р.143
  - `getSeekStep()` р.145
  - `saveSeekStep()` р.146
  - `getSeekButtons()` р.148
  - `saveSeekButtons()` р.149
  - `getDoubleTapSeek()` р.151
  - `saveDoubleTapSeek()` р.152
  - `getHoldToSpeedEnabled()` р.154
  - `saveHoldToSpeedEnabled()` р.155
  - `getHoldToSpeedRate()` р.157
  - `saveHoldToSpeedRate()` р.158
  - `getAutoSkipChapters()` р.160
  - `saveAutoSkipChapters()` р.161
  - `getAnime4kEnabled()` р.164
  - `saveAnime4kEnabled()` р.165
  - `getAnime4kMode()` р.168
  - `saveAnime4kMode()` р.169
  - `getAnime4kQuality()` р.172
  - `saveAnime4kQuality()` р.173
  - `getAnime4kSkipHeight()` р.176
  - `saveAnime4kSkipHeight()` р.177
  - `getHikkaTitleLang()` р.181
  - `saveHikkaTitleLang()` р.182
  - `getHikkaAllowAdult()` р.185
  - `saveHikkaAllowAdult()` р.186
  - `getKeyScheme()` р.190
  - `saveKeyScheme()` р.191
  - `getHwdec()` р.194
  - `saveHwdec()` р.195
  - `getVolume()` р.197
  - `saveVolume()` р.198
  - `getSpeed()` р.200
  - `saveSpeed()` р.201
  - `getPitchCorrection()` р.203
  - `savePitchCorrection()` р.204
  - `getPlayerOrientation()` р.207
  - `savePlayerOrientation()` р.208
  - `getDetailedLog()` р.211
  - `saveDetailedLog()` р.212
  - `getDefaultAudioLang()` р.214
  - `saveDefaultAudioLang()` р.215
  - `getAudioLangPriorities()` р.217
  - `saveAudioLangPriorities()` р.225
  - `getSubLangPriorities()` р.232
  - `saveSubLangPriorities()` р.241
  - `getDefaultSubLang()` р.247
  - `saveDefaultSubLang()` р.248
  - `getSubFont()` р.250
  - `saveSubFont()` р.251
  - `getSubFontSize()` р.253
  - `saveSubFontSize()` р.254
  - `getSubTextColor()` р.256
  - `saveSubTextColor()` р.257
  - `getSubBorderSize()` р.259
  - `saveSubBorderSize()` р.260
  - `getSubBorderColor()` р.262
  - `saveSubBorderColor()` р.263
  - `getSubShadowOffset()` р.265
  - `saveSubShadowOffset()` р.266
  - `getSubMarginY()` р.268
  - `saveSubMarginY()` р.269
  - `getSubBgOpacity()` р.271
  - `saveSubBgOpacity()` р.272
  - `getSubAssMode()` р.274
  - `saveSubAssMode()` р.275
  - `getCustomFonts()` р.277
  - `addCustomFont()` р.278
  - `getRecentFiles()` р.287
  - `addRecentFile()` р.288
  - `clearRecentFiles()` р.297
  - `getLastQueue()` р.315
  - `saveLastQueue()` р.324
  - `clearLastQueue()` р.331
  - `getPlaylists()` р.338
  - `createPlaylist()` р.361
  - `updatePlaylist()` р.370
  - `deletePlaylist()` р.381

### `lib/services/stream_resolver.dart` (78 р.)
Відео для серії в момент відтворення: `StreamResolver({maxHeight, preferredHoster}).resolve(source, episode, {hoster, height})` → `ResolvedStream` (відео, усі якості, обраний плеєр, усі плеєри); плеєри перебираються за порядком, перший робочий виграє, помилка зведена (один плеєр — його власна).

- **ResolvedStream** (р.11)
- **StreamResolver** (р.28)
  - `resolve()` р.41

### `lib/services/system_controls.dart` (111 р.)
Міст до Android через `MethodChannel('miki_miki/system')` (реалізація — `MainActivity.kt`): `pipSupported`, `enterPip`, `setPipAuto`, `inPip` (нотифікатор; шле Android), `getBrightness/setBrightness/resetBrightness/restoreBrightness` (`userBrightness` — вибір жестом), `getVolume/setVolume`. Поза Android усі методи безпечні (нічого не роблять); `debugEnabled` — для тестів. `openUrl(url)` — відкриває http(s)-посилання у браузері (Android — канал `openUrl`, десктоп — системна команда); потрібен каталогу Hikka. `deviceInfo()` → `Map` (модель, Android, RAM, енергозбереження, нагрів, частота екрана, маршрут звуку) з `MainActivity.kt` (метод `deviceInfo`); поза Android — `null`. Канал — `miki_miki/system`.

- **SystemControls** (р.11)
  - `init()` р.28
  - `pipSupported()` р.48
  - `enterPip()` р.51
  - `setPipAuto()` р.56
  - `getBrightness()` р.64
  - `setBrightness()` р.65
  - `resetBrightness()` р.71
  - `restoreBrightness()` р.74
  - `deviceInfo()` р.80
  - `openUrl()` р.86
  - `getVolume()` р.109
  - `setVolume()` р.110

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

### `lib/services/watch_models.dart` (269 р.)
Моделі «Дивитись»: `episodeKey(episode, index)` («3», «3.5», «s2e5», «i7»), `WatchGroup` (озвучка / субтитри: `id` = `джерело|аніме|реліз`, `label`, `isSub`, `teams`, `episodes`), `WatchOffer` (що знайшло джерело), `WatchTitle` (пропозиції + `licensed` / `license` + `errors`), `RemoteEntry` / `RemoteSession` (черга плеєра: ключ `hikka:<slug>#<серія>` для позиції й «переглянуто»; однакові номери в одному варіанті отримують суфікс `~2`). Також: `episodeLabel(episode, index)` (підпис кнопки серії), `episodeKeysOf(group)` (ключі серій варіанта; повтори отримують `~2`, `~3`), `ContinuePoint` + `continuePoint(keys, watched, lastKey)` (звідки продовжити: остання відкрита, а якщо вона переглянута — наступна; усе переглянуто → `allWatched`). Також: `WatchGroup.fullLabel` («Озвучення: Inari» / «Субтитри: Inari»), `choiceKeyOf(group)` (стійка ознака варіанта поза тайтлом: вид + команди), `pickGroup(groups, {preferredId, favorites, safe})` (який варіант відкриває «Дивитись»).

- **WatchGroup** (р.25)
- **WatchOffer** (р.102)
- **WatchTitle** (р.113)
  - `offerOf()` р.137
  - `groupById()` р.144
  - `offerOfGroup()` р.151
- **RemoteEntry** (р.155)
- **ContinuePoint** (р.194)
- **RemoteSession** (р.223)
  - `indexOfKey()` р.262
  - `displayTitle()` р.265

### `lib/services/watch_service.dart` (257 р.)
`WatchService.start(HikkaAnime, {searchOthers})` → `WatchLoad` (див. правило «Потік Дивитись»); `searchOffer(source, anime)` (збережене зіставлення → пошук за назвами → `bestAnimeMatch`), `offerFor`, `groupEpisodes`, `titlesOf` / `queriesOf`, `infoOf` (дані Hikka для звірки), `keyOf`. `WatchLoad.defaultGroup(store)` — варіант за кнопкою «Дивитись» (`pickGroup`).

- **WatchLoad** (р.19)
  - `checkOf()` р.46
  - `defaultGroup()` р.49
- **WatchService** (р.86)
  - `keyOf()` р.96
  - `infoOf()` р.98
  - `titlesOf()` р.105
  - `queriesOf()` р.116
  - `start()` р.126
  - `searchOffer()` р.189
  - `offerFor()` р.219
  - `groupEpisodes()` р.225

### `lib/services/watch_store.dart` (154 р.)
Що переглянуто й де зупинилися (розділ `watch_store`): `watched` / `isWatched` / `setWatched` / `markUpTo(animeKey, order, upTo)`, `last` / `setLast` (до 400 тайтлів), `recentTitles`, `preferredGroup` / `setPreferredGroup`, зіставлення Hikka ↔ сайт `link` / `setLink`; ChangeNotifier, інʼєкція `load` / `save` для тестів. `favoriteChoices` / `setFavoriteChoice(key)` — озвучки й субтитри (`choiceKeyOf`), які людина свідомо обирала в плеєрі: до 8, найновіші першими.

- **WatchLast** (р.11)
- **WatchStore** (р.19)
  - `reload()` р.43
  - `watched()` р.57
  - `isWatched()` р.59
  - `setWatched()` р.61
  - `markUpTo()` р.73
  - `last()` р.83
  - `setLast()` р.92
  - `recentTitles()` р.106
  - `preferredGroup()` р.112
  - `setPreferredGroup()` р.114
  - `setFavoriteChoice()` р.126
  - `link()` р.140
  - `setLink()` р.145

### `lib/utils/formatters.dart` (219 р.)
Форматування часу/розміру/назв. `translateChapterTitle` запам'ятовує результати (викликається часто).

- **AppFormatters** (р.5)
  - `clearTrackCache()` р.9
  - `formatTime()` р.14
  - `formatSpeed()` р.21
  - `getSpeedIcon()` р.25
  - `cleanMediaTitle()` р.32
  - `translateChapterTitle()` р.64
  - `formatTrackTitle()` р.141

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

### `lib/widgets/app_dock_widgets.dart` (679 р.)
Віджети доку: колесо миші над елементом (`AppWheelRegion`), гучність (`AppVolumeControl`), смужка прогресу з прев'ю й розділами (`AppSeekBar`: власний шар малювання, перемальовується лише при зсуві на піксель, `live`), `AppClockBuilder` (будує за значенням годинника, лише поки `live`), `AppProgressLine` (тонка смужка прогресу з `PlaybackClock.permille`).

- **AppWheelRegion** (р.16)
- **AppClockBuilder** (р.42)
- **_AppClockBuilderState** (р.53)
- **AppProgressLine** (р.85)
- **AppVolumeControl** (р.134)
- **_AppVolumeControlState** (р.154)
- **_VolumePainter** (р.257)
- **AppSeekBar** (р.295)
- **_AppSeekBarState** (р.323)
- **_SeekPainter** (р.585)

### `lib/widgets/app_media_thumbnail.dart` (116 р.)
AppMediaThumbnail(uri,…) — віджет прев'ю через ThumbnailService.

- **AppMediaThumbnail** (р.10)
- **_AppMediaThumbnailState** (р.40)

### `lib/widgets/app_settings_dialog.dart` (2344 р.)
Діалог налаштувань (має власні копії nav/section віджетів). Вкладки: Вигляд, Субтитри, Відтворення, Відео & GPU, Anime4K, Звук, Гарячі клавіші, Розробник, Про програму; чернетка з «Скасувати» / «Скинути» / «Застосувати». Телефон: на весь екран (портрет — рядок вкладок `_buildPhoneTabStrip`, альбомна — бічне меню), перемикачі й кнопки ≥ 48 dp, без розділу «Гарячі клавіші» та підказок клавіш. «Розробник»: секція «Журнал і діагностика» (`_setDetailedLog`, `_saveLogToFile` → `LogExport.save`, `_clearLogs`, `_buildLogStatusLine`); «Відтворення»: «Орієнтація плеєра» лише на телефоні (`_playerOrientation`, у знімку змін). `initialTab` / `tabDeveloper` (5) / `tabAbout` (6) — відкрити вікно відразу на потрібній вкладці (з «Профілю»); «Розробник» → «Приховані можливості» (перемикач «Локальна медіатека») і «Банери на головній» (ключ TheMovieDB, `_tmdbKey`); «Про програму» бере назву, версію й збірку з `AppIdentity` / `AppDiagnostics.build` і називає джерела (Hikka, AniList, TheMovieDB).

- **AppSettingsDialog** (р.23)
  - `show()` р.41
- **_AppSettingsDialogState** (р.57)

### `lib/widgets/app_ui_kit.dart` (2354 р.)
UI KIT: AppOverlayButton, AppPanelSurface/Header, AppSelectableSurface, AppSelectableTile (з необов'язковими subtitle/trailing), AppSecondaryButton, AppEmptyState, AppModalShell, AppSidebar, AppNavItem, AppPaneHeader, AppSectionHeader, AppAccentButton, AppCard, AppStatTile, AppKeyCap / AppKeyCombo (кнопки клавіатури), AppSearchField, AppScrollEdgeFade, AppScrollbar + базові віджети. Нові UI будувати з цього. На телефоні сегменти `AppSegmentedBar` ≥ 48 dp, `AppOverlayButton` має `onLongPress`. `AppSearchField(icon:)` — з іншою іконкою й підказкою це звичайне однорядкове поле (ключ API).

- **EdgeToEdgeSliderTrackShape** (р.8)
- **DotSliderThumbShape** (р.25)
- **AppSegmentOption** (р.65)
- **AppSegmentedBar** (р.71)
- **AppDropdownOption** (р.153)
- **AppDropdown** (р.160)
- **_AppDropdownState** (р.182)
- **AppSearchDropdown** (р.349)
- **_AppSearchDropdownState** (р.373)
- **AppLanguagePriorityList** (р.652)
- **_AppLanguagePriorityListState** (р.668)
- **AppDragHandle** (р.994)
- **AppRowIconButton** (р.1023)
- **AppSelectableTile** (р.1060)
- **AppOverlayButton** (р.1175)
- **_AppOverlayButtonState** (р.1214)
- **AppPanelSurface** (р.1300)
- **AppPanelHeader** (р.1342)
- **AppSelectableSurface** (р.1423)
- **AppSecondaryButton** (р.1479)
- **AppEmptyState** (р.1557)
- **AppModalShell** (р.1592)
- **AppSidebar** (р.1635)
- **AppNavGroupLabel** (р.1675)
- **AppNavItem** (р.1699)
- **AppPaneHeader** (р.1782)
- **AppSectionHeader** (р.1864)
- **AppAccentButton** (р.1913)
- **AppCard** (р.1984)
- **AppStatTile** (р.2030)
- **AppKeyCap** (р.2106)
- **AppKeyCombo** (р.2147)
- **AppSearchField** (р.2171)
- **_AppSearchFieldState** (р.2193)
- **AppScrollEdgeFade** (р.2292)
- **AppScrollbar** (р.2332)

### `lib/widgets/bottom_dock.dart` (495 р.)
Нижня панель керування (слайдер, кнопки; drawerOwner/isEpisodesOpen). Кнопка Anime4K: клік — меню режимів, права кнопка — вмикання/вимикання, крапка — активний. `live` (false — панель прихована: підписи часу, прогрес і розділ не стежать за відтворенням); `volume` — `ValueListenable<VolumeState>` (перебудовується лише повзунок гучності). Параметри `onPrevious` / `onNext` (типово — `player.previous/next`; для серій із сайту їх задає `PlayerStateController.playPrevious/playNext`).

- **BottomDock** (р.14)
- **_BottomDockState** (р.90)

### `lib/widgets/center_flash.dart` (80 р.)
`CenterFlash` — коротка (650 мс) велика іконка пауза/пуск посередині відео при зміні стану відтворення (замість постійних центральних кнопок).

- **CenterFlash** (р.8)
- **_CenterFlashState** (р.18)

### `lib/widgets/center_hub.dart` (78 р.)
Центральні кнопки play/seek.

- **CenterHub** (р.6)

### `lib/widgets/collapsed_player.dart` (179 р.)
Згорнутий плеєр (смужка внизу вікна): підпис часу й тонка смужка прогресу з `PlaybackClock`. `width` — на телефоні в портреті картка на всю ширину.

- **CollapsedPlayer** (р.14)

### `lib/widgets/controls_overlay.dart` (231 р.)
Збирає top/bottom/center + випадні меню (settings/subs/audio/speed/Anime4K). Прихована панель передає в док `live:false`; гучність — `volume: ValueListenable<VolumeState>`. Передає `onPrevious` / `onNext` у `BottomDock`. Необовʼязковий `onAddSubtitleFile` передається в `SettingsDrawer`.

- **ControlsOverlay** (р.11)

### `lib/widgets/frosted_tile.dart` (84 р.)
Застаріла «скляна» плитка (майже не використовується).

- **FrostedTile** (р.4)

### `lib/widgets/hikka/hikka_account_ui.dart` (259 р.)
`HikkaLoginDialog.show(context, scale:)` — вікно входу (одразу запускає `HikkaAuth.startLogin()`; стани «Чекаю на підтвердження…» / «Завершую вхід…» / помилка з «Спробувати ще раз»; без локального порту або за кнопкою «Не спрацювало? Вставити адресу» — поле для адреси чи коду; «Відкрити знову»; закривається саме після входу, закриття вікна скасовує вхід) і `HikkaAccountCard` (гість із кнопкою «Увійти через Hikka»; після входу — аватар, імʼя, «Передавати прогрес у списки», «Вийти з акаунта»).

- **HikkaLoginDialog** (р.19)
- **HikkaAccountCard** (р.172)

### `lib/widgets/hikka/hikka_airing_strip.dart` (231 р.)
`HikkaAiringStrip` — тонка стрічка календаря на «Головній»: кнопка «Календар» + чипи найближчих серій (`_EpisodeChip`; «вийшла щойно / 20 хв тому / о 10:00», «через 30 хв», «Сьогодні, 17:00», «Завтра, …»); `HikkaAiring.of(entry, now)` → `text` + `live` (акцент, поки серія щойно вийшла) — чиста логіка, покрита тестами.

- **HikkaAiring** (р.13)
  - `of()` р.24
- **HikkaAiringStrip** (р.39)
- **_Strip** (р.69)
- **_CalendarButton** (р.99)
- **_EpisodeChip** (р.137)
- **_StripSkeleton** (р.205)

### `lib/widgets/hikka/hikka_anime_characters_page.dart` (75 р.)
Усі персонажі аніме (головні / другорядні) сіткою з підвантаженням.

- **HikkaAnimeCharactersPage** (р.13)
- **_HikkaAnimeCharactersPageState** (р.24)

### `lib/widgets/hikka/hikka_anime_page.dart` (653 р.)
Сторінка аніме: шапка зі списку одразу, повні дані з API; постер, назви, статус, жанри (→ каталог із жанром), оцінки MAL / Hikka, наступна серія, згортуваний опис, таблиця інформації, полиці персонажів / франшизи / рекомендацій, автори, посилання (дивитись — першими), відео, музика; заглушка 18+. Секція «Дивитись» (`HikkaWatchSection`) іде першою в `_sections`. Під оцінками (`_scores`) і над блоком «Дивитись» стоїть `_myList(a)` → `HikkaMyListBar` (мій статус, прогрес, оцінка, серце).

- **HikkaAnimePage** (р.21)
- **_HikkaAnimePageState** (р.32)

### `lib/widgets/hikka/hikka_article_page.dart` (162 р.)
`HikkaArticlePage(scale, route, pad)` — стаття: категорія, назва, автор і дата, лічильники й текст (`HikkaSlateView`); шапка зʼявляється одразу з `route.seed`, повний текст вантажиться окремо (`HikkaApi.article`).

- **HikkaArticlePage** (р.15)
- **_HikkaArticlePageState** (р.26)

### `lib/widgets/hikka/hikka_articles_page.dart` (106 р.)
`HikkaArticlesPage` — розділ «Статті»: фільтр за категорією (Усі · Новини · Огляди · Авторські), порядок (найновіші / найвище оцінені), `HikkaPagedList` із `HikkaArticleCard`.

- **HikkaArticlesPage** (р.15)
- **_HikkaArticlesPageState** (р.26)

### `lib/widgets/hikka/hikka_banner.dart` (370 р.)
`HikkaBannerCarousel(items, scale, pad, autoAdvance = 7 с, artLoader)` — банери поточних онґоїнґів: широкий фон (`_WideBackdrop` із AniList / TMDB; запасний `_Backdrop` — постер крізь крихітну копію), чіткий постер, назва, мета в один рядок (тип не показується для `tv`), оцінка й кнопка «Дивитись»; самогортання таймером (`autoAdvance`; дотик зупиняє, у фоні й поза екраном не крутиться), крапки `_Dots`; `HikkaBannerArtLoader` (у тестах підміняється), `HikkaBannerCarouselMetrics` (скелет повторює розміри).

- **HikkaBannerCarouselMetrics** (р.17)
- **HikkaBannerArtLoader** (р.25)
- **HikkaBannerCarousel** (р.31)
- **_HikkaBannerCarouselState** (р.53)
- **_Dots** (р.173)
- **_Banner** (р.202)
- **_Backdrop** (р.327)
- **_WideBackdrop** (р.348)

### `lib/widgets/hikka/hikka_cards.dart` (245 р.)
Картки: `HikkaAnimeCard` (постер, оцінка, назва, підпис), `HikkaCharacterCard`, `HikkaAnimeRow` (рядок франшизи: мініатюра, підпис зв’язку, оцінка, виділення поточного).

- **HikkaAnimeCard** (р.12)
- **HikkaCharacterCard** (р.94)
- **HikkaAnimeRow** (р.145)

### `lib/widgets/hikka/hikka_catalog_page.dart` (234 р.)
Вкладка «Аніме»: пошук із паузою 450 мс, підсумок («Оцінка MAL ↓ · N знайдено»), сітка з підвантаженням, панель фільтрів (охоронець «Назад» її закриває). Тепер розділ «Каталог» в «Огляді». Пошукова панель «Головної» (`HikkaNav.openSearch`) ставить курсор у поле пошуку (`_searchFocus`, `HikkaNav.takeFocusSearch`); панель фільтрів закривається, коли людина йде з розділу.

- **HikkaCatalogPage** (р.20)
- **_HikkaCatalogPageState** (р.31)

### `lib/widgets/hikka/hikka_character_page.dart` (309 р.)
Сторінка персонажа: портрет, імена й синоніми, лічильники, опис із спойлерами, озвучення за мовами (японська, українська, англійська першими), аніме персонажа сіткою.

- **HikkaCharacterPage** (р.18)
- **_HikkaCharacterPageState** (р.29)

### `lib/widgets/hikka/hikka_characters_page.dart` (97 р.)
Вкладка «Персонажі»: пошук (від двох символів) і сітка популярних.

- **HikkaCharactersPage** (р.14)
- **_HikkaCharactersPageState** (р.25)

### `lib/widgets/hikka/hikka_collection_page.dart` (337 р.)
`HikkaCollectionPage(scale, route, pad)` — колекція: назва, автор, опис (Markdown), записи: рядками з коментарем автора (`_EntryRow`) або сіткою постерів; групи записів — окремими блоками; колекція 18+ закрита заглушкою «Контент 18+ прихований» (кнопка показу діє лише для цієї колекції — `_revealed`), поки вимкнено `allowAdult`.

- **HikkaCollectionPage** (р.19)
- **_HikkaCollectionPageState** (р.30)
- **_EntryRow** (р.269)

### `lib/widgets/hikka/hikka_collections_page.dart` (92 р.)
`HikkaCollectionsPage` — розділ «Колекції»: за замовчуванням найпопулярніші, можна найновіші; `HikkaPagedList` із `HikkaCollectionCard`.

- **HikkaCollectionsPage** (р.14)
- **_HikkaCollectionsPageState** (р.25)

### `lib/widgets/hikka/hikka_common.dart` (912 р.)
Спільні будівельні блоки каталогу: `HikkaLayout` (розміри, `compact`), `HikkaPoster`, `HikkaAsync` (завантаження → вміст / помилка з «Повторити»), `HikkaLoading`, `HikkaErrorView`, `HikkaChip`, `HikkaScoreBadge`, `HikkaPill`, `HikkaLinkButton`, `HikkaIconButton`, `HikkaBackBar`, `HikkaPagedGrid` (сітка з підвантаженням і `header`), `HikkaToggleRow`, `HikkaInfoTable` (у вузькій колонці значення йде під назвою), `HikkaSearchBar`, `hikkaStyle(...)`. `HikkaSearchBar(focusNode:)` — зовнішній фокус для поля пошуку.

- **HikkaLayout** (р.16)
- **HikkaPoster** (р.46)
- **HikkaAsync** (р.128)
- **_HikkaAsyncState** (р.162)
- **HikkaLoading** (р.214)
- **HikkaErrorView** (р.237)
- **HikkaChip** (р.282)
- **HikkaScoreBadge** (р.363)
- **HikkaPill** (р.390)
- **HikkaLinkButton** (р.416)
- **HikkaIconButton** (р.456)
- **HikkaBackBar** (р.502)
- **HikkaGridDelegate** (р.559)
- **HikkaPagedGrid** (р.609)
- **_HikkaPagedGridState** (р.645)
- **HikkaToggleRow** (р.760)
- **HikkaInfoTable** (р.827)
- **HikkaSearchBar** (р.873)

### `lib/widgets/hikka/hikka_community_cards.dart` (216 р.)
Картки спільноти: `HikkaCollectionCard` (смужка постерів перших тайтлів, назва, автор, лічильники → `HikkaNav.openCollection`), `HikkaArticleCard` (обкладинка, категорія, дата, початок тексту, лічильники → `openArticle`), `HikkaStat` (значок + число, `HikkaText.compact`), `HikkaChipRow` (рядок міток, що гортається вбік; `selectedIndex` — вибрана мітка сама прокручується в поле зору).

- **HikkaStat** (р.12)
- **HikkaChipRow** (р.35)
- **HikkaCollectionCard** (р.66)
- **HikkaArticleCard** (р.152)

### `lib/widgets/hikka/hikka_discover_page.dart` (132 р.)
`HikkaDiscoverPage(scale, bottomInset, onRefresh)` — вкладка «Огляд»: заголовок `HikkaTabHeader`, рядок розділів `HikkaTab` (`HikkaDiscoverPage.iconOf`), вміст розділу (`_sections`: усе, календар, каталог, колекції, статті, персонажі); перший розділ — «Усе» (`HikkaOverviewPage`); розділи й «Списки» гортаються свайпом (`HikkaSwipeTabs` у `hikka_page_kit.dart`: різкий рух убік перемикає вкладку, вміст виїжджає з відповідного боку з коротким проявом); відкриті розділи не руйнуються; потяг вниз оновлює.

- **HikkaDiscoverPage** (р.18)
- **_HikkaDiscoverPageState** (р.40)

### `lib/widgets/hikka/hikka_filter_sheet.dart` (304 р.)
Панель фільтрів: сортування, тип, статус, сезон, рік, жанри, оцінка, вікова категорія, «лише з перекладом»; на десктопі бічна панель, на телефоні — `MobileSheetFrame`. «Скинути» з’являється, коли щось змінено.

- **HikkaFilterSheet** (р.13)
- **_HikkaFilterSheetState** (р.36)

### `lib/widgets/hikka/hikka_franchise_page.dart` (234 р.)
Франшиза: «За роками» / «За групами», рядки `HikkaAnimeRow` (поточний виділено), 18+ вузли приховано, підсумок «N тайтлів · основна історія: M».

- **HikkaFranchisePage** (р.18)
- **_HikkaFranchisePageState** (р.29)

### `lib/widgets/hikka/hikka_home_page.dart` (263 р.)
`HikkaHomePage(scale, bottomInset, onRefresh)` — «Головна»: `_TopBar` (рядок пошуку `_SearchPill` → `HikkaNav.openSearch`, «Оновити» на ПК, «Сповіщення» → `HikkaNotificationsDialog`), `HikkaAiringStrip`, `HikkaBannerCarousel` (банери — `BannerArt`; скелет `_BannerSkeleton`), полиці «Продовжити перегляд» (`ContinueWatching.load`, порожню не показує), «Рекомендації», «Зараз виходить», «Анонси», «Найпопулярніші», «Найкращі за оцінкою» (кнопка «Усі» → `HikkaNav.openCatalog` з готовими умовами); кожна полиця завантажується окремо (`HikkaShelfAsync`) і має «Повторити».

- **HikkaHomePage** (р.23)
- **_HikkaHomePageState** (р.42)
- **_TopBar** (р.164)
- **_SearchPill** (р.198)
- **_BannerSkeleton** (р.241)

### `lib/widgets/hikka/hikka_hub.dart` (266 р.)
`HikkaHub(scale, onOpenSettings, localLibraryBuilder, bottomInset)` — вміст застосунку: чотири головні вкладки (`_root(MainTab)`: `HikkaHomePage` / `HikkaDiscoverPage` / `HikkaListsPage` / `HikkaProfilePage`; ліниво, у `Offstage` + `TickerMode`, `_mounted`) і шар відкритих сторінок (`_page(HikkaRoute)`: аніме, персонаж, франшиза, персонажі аніме, колекція, стаття, локальна медіатека) з плавною зміною (`AppFadeSwitcher`) і `HikkaBackBar` (`_routeTitle` / `_routeSubtitle` / `_routeUrl`; «Оновити» → `_refreshRoute`, «Відкрити на hikka.io»; для локальної медіатеки без цих дій). `_refreshAll` / `_pullRefresh` перезавантажують вкладки (`_refresh`), `_forget` скидає запам'ятований стан сторінки (розкрите 18+ лишається — `memo['revealed']`), `_openCatalogSettings` → `HikkaSettingsDialog`. Мишача кнопка «Назад».

- **HikkaHub** (р.27)
- **_HikkaHubState** (р.51)

### `lib/widgets/hikka/hikka_lists_page.dart` (440 р.)
Статуси мають сталі кольори: `hikkaStatusColor` (дивлюсь — блакитний, заплановано — фіолетовий, переглянуто — зелений, відкладено — жовтий, кинуто — червоний) і `hikkaFavouriteColor` у `hikka_my_list_bar.dart`; `HikkaChip.color`, `HikkaAnimeCard.pillColor`.
`HikkaListsPage` — вкладка «Списки»: для гостя `HikkaAccountCard` і перелік того, що буде після входу (`HikkaListsPage.planned`, `_PlannedRow`); після входу — чипи статусів із лічильниками (`HikkaWatchStats`) і «Улюблене», `HikkaPagedGrid` за вкладкою (`HikkaApi.watchList` / `favourites`, пейджер на вкладку), картки `HikkaAnimeCard(pill: серії/всього, caption: ★ оцінка · тип · рік, onRemove)`; перезавантажується за `HikkaMyList.version` і зміною акаунта; 18+ ховається за `HikkaPrefs.allowAdult`.

- **HikkaListsPage** (р.12)
- **_HikkaListsPageState** (р.32)
- **_PlannedRow** (р.123)

### `lib/widgets/hikka/hikka_markdown_view.dart` (399 р.)
Віджети описів: `HikkaMarkdownView` (абзаци, списки, цитати, спойлери, посилання → `HikkaNav.openLink`), `HikkaCollapsible` (згорнути довгий текст із «Показати більше»). `HikkaSpoilerBox` — спойлер, спільний для описів і статей.

- **HikkaMarkdownView** (р.14)
- **_HikkaMarkdownViewState** (р.36)
- **HikkaSpoilerBox** (р.188)
- **_HikkaSpoilerBoxState** (р.199)
- **HikkaCollapsible** (р.260)
- **_HikkaCollapsibleState** (р.280)
- **_SizeReporter** (р.372)
- **_RenderSizeReporter** (р.384)

### `lib/widgets/hikka/hikka_my_list_bar.dart` (349 р.)
`hikkaStatusIcon(status)` — значок статусу (спільний із вкладкою «Списки»). `HikkaMyListBar(anime, scale)` — блок «Мій список» на сторінці аніме: гість — «Додати в список» (веде до входу), ввійшов — «Завантажую список…» → «Додати в список» або плитка `статус · серій N/M · ★ оцінка` (тап → `HikkaListEditDialog`) і серце «В улюблене» / «Прибрати з улюбленого». `HikkaListEditDialog` — статус (чипи), лічильник серій −/+ (до кількості серій; «Переглянуто» ставить усі), оцінка 1–10 (повторний тап скидає), «Зберегти», «Видалити зі списку»; помилка мережі лишає вікно відкритим.

- **HikkaMyListBar** (р.32)
- **HikkaListEditDialog** (р.222)

### `lib/widgets/hikka/hikka_notifications_dialog.dart` (111 р.)
`HikkaNotificationsDialog` — «Сповіщення»: заглушка (нові серії й озвучки з Hikka та Mikai зʼявляться після входу).

- **HikkaNotificationsDialog** (р.11)

### `lib/widgets/hikka/hikka_page_kit.dart` (146 р.)
Каркас сторінок: `HikkaPageFrame` (поля, максимальна ширина, прокрутка), `HikkaSection` (заголовок + вміст), `hikkaHeaderPosterWidth`, `hikkaWideBreakpoint` (760), `hikkaReadableWidth`. `HikkaPageFrame.onRefresh` — оновлення потягом вниз (лише на телефоні; на ПК є кнопка «Оновити»); `HikkaTabHeader(scale, title, subtitle, actions)` — заголовок головних вкладок «Огляд» / «Списки» / «Профіль».

- **HikkaPageFrame** (р.12)
- **HikkaSection** (р.62)
- **HikkaTabHeader** (р.112)
- Оновлення: на телефоні кнопки «Оновити» немає — потяг вниз (`RefreshIndicator`: Огляд, Списки, Головна, відкриті сторінки в `HikkaHub._withRouteRefresh`); на ПК кнопка в шапці. «Списки»: кнопка фільтра/сортування (`HikkaFilterSheet` з `sortOptions: HikkaSearchFilters.listSorts`, `defaultSort: defaultListSort='watch_updated'`), фільтри йдуть у `HikkaApi.watchList(filters:)`; на «Улюблене» не діють.
- Прокрутка: `AppScrollBehavior` (app_ui_kit.dart) — розтягування краю як в Android 12 (StretchingOverscrollIndicator); використовується в `MaterialApp.scrollBehavior` і скрізь замість `ScrollBehavior().copyWith(scrollbars:false)` (старий варіант повертав світіння). Фізика прокрутки — платформна (без BouncingScrollPhysics).
- Стрічка серій на Головній (`HikkaAiringStrip`): тонка смужка з одним записом, що змінюється фейдом кожні `kAiringTick` (5 с), тонка лінія прогресу внизу; ліворуч іконка календаря, крапка лише в серій поточної години; збоку «Серія N» і час.
- Оновлення: `services/app_updater.dart` — `AppUpdater.instance` (репозиторій `Zeddy-Coder/miki-miki`, GitHub Releases `releases/latest`), `check({auto})` (тиха раз на 12 год, ручна завжди), `state` (`UpdateIdle/Checking/UpToDate/Available/Failed`), `compareVersions`, `pickAsset` (Android — arm64 `.apk`, Windows — `.zip/.exe`). Нічого не ставить сам: «Завантажити» відкриває файл/сторінку через `SystemControls.openUrl`. Блок у «Про програму» (`_buildUpdateBlock` у `app_settings_dialog.dart`), підказка в рядку «Про» профілю, тиха перевірка з main.dart через 8 с. Реліз: тег `vX.Y.Z` + APK у Assets.
- Кеш Hikka: у памʼяті (`HikkaApi._cache`, TTL 3/10/30 хв) + на диску (`services/hikka_disk_cache.dart`, `HikkaApi.disk`, у main.dart; один файл на запит, до 600 файлів / 14 днів): свіже з диска без мережі; до 6 год — віддається одразу й оновлюється у фоні; старше — лише коли немає мережі; `clearCache()` (ручне оновлення) не віддає збережене як свіже. Статуси списків для позначок: `HikkaMyList.loadIndex` (диск `hikka_status_index`, оновлення раз на 6 год, на старті з відкладенням 4 с). Зображення — окремо `HikkaImageStore`.
- **HikkaCollapsingHeader** — шапка (`header`) над вмістом (`body`): ховається при вертикальній прокрутці вниз, повертається при прокрутці вгору чи на верху; не ховається, якщо вмісту замало для повернення; `resetOn` показує шапку при зміні вкладки. Використано: Огляд (шапка + чіпси), календар (дні), Списки, Каталог (пошук), Профіль. Вкладені шапки ховаються разом.

### `lib/widgets/hikka/hikka_paged_list.dart` (172 р.)
`HikkaPagedList<T>(pager, scale, itemBuilder, emptyText, header, maxCardWidth, …)` — прокручуваний список широких карток із підвантаженням (`HikkaPager`): докантажує при наближенні до кінця; на широких вікнах — два стовпці; порожній стан і «Повторити».

- **HikkaPagedList** (р.12)
- **_HikkaPagedListState** (р.46)

### `lib/widgets/hikka/hikka_profile_page.dart` (201 р.)
`HikkaProfilePage(scale, bottomInset, onOpenSettings, onOpenCatalogSettings)` — вкладка «Профіль»: картка акаунта (`HikkaAccountCard`: вхід / імʼя, перемикач синхронізації, вихід), пункти «Налаштування застосунку», «Каталог і дані», «Джерела перегляду», «Про Miki Miki», «Локальна медіатека» (лише коли ввімкнено в «Розробник», слухає `StorageService.localLibraryListenable`), підпис «Дані: Hikka · зображення: AniList».

- **HikkaProfilePage** (р.19)
- **_HikkaProfilePageState** (р.41)
- **_MenuRow** (р.200)

### `lib/widgets/hikka/hikka_schedule_page.dart` (222 р.)
Вкладка «Календар»: найближчі серії за днями, решта підвантажується під час прокрутки.

- **HikkaSchedulePage** (р.16)
- **_Row** (р.28)
- **_DayRow** (р.32)
- **_EpisodeRow** (р.37)
- **_HikkaSchedulePageState** (р.42)
- **_EpisodeTile** (р.166)

### `lib/widgets/hikka/hikka_settings_dialog.dart` (240 р.)
Налаштування каталогу: мова назв (Українська / English / Ромаджі), 18+, «Оновити дані», «Очистити кеш зображень» із розміром. Розділ «Перегляд» з кнопкою «Джерела перегляду» (`SourcesDialog`). Розділ «Свій клієнт Hikka» (два поля, зміни з паузою 600 мс і при закритті → `HikkaAuth.setCustomClient`).

- **HikkaSettingsDialog** (р.16)
- **_HikkaSettingsDialogState** (р.40)

### `lib/widgets/hikka/hikka_shelf.dart` (218 р.)
Горизонтальні полиці: `HikkaShelf` (стрілки на десктопі), `HikkaShelfSkeleton`, `HikkaShelfAsync<T>` (сама вантажить дані; порожній список ховає полицю; помилка — під заголовком із «Повторити»).

- **HikkaShelfMetrics** (р.11)
- **HikkaShelf** (р.22)
- **_HikkaShelfState** (р.48)
- **HikkaShelfSkeleton** (р.110)
- **HikkaShelfAsync** (р.155)

### `lib/widgets/hikka/hikka_slate_view.dart` (474 р.)
`HikkaSlateView(nodes, scale, fontSize, onLink)` — текст статті (документ Slate): абзаци, заголовки, списки, цитати, спойлери (`HikkaSpoilerBox`), картинки (`HikkaSlateImage`: проявляється, натискання → `HikkaImageViewer` із масштабуванням і гортанням групи), групи картинок плитками, відео, посилання (на аніме, персонажів, колекції й статті — всередину застосунку).

- **HikkaSlateView** (р.16)
- **_HikkaSlateViewState** (р.30)
- **HikkaSlateImage** (р.318)
- **HikkaImageViewer** (р.378)
- **_HikkaImageViewerState** (р.397)

### `lib/widgets/hikka/hikka_watch_dialogs.dart` (369 р.)
Діалоги блоку «Дивитись»: `WatchDialogs.confirmLicensed(context, scale:, license:)` («Тричі подумайте»: головна дія — дивитись легально, тиха `QuietAction` «Все одно дивитись»; `true` — людина підтвердила), `WatchDialogs.teams(context, scale:, teams:, source:)` (опис, прапорці «Озвучення / Субтитри», кількість тайтлів і посилання команди з Mikai), `WatchDialogs.linkLabel(key)`; `WatchDialogFrame` — спільна оболонка діалогів перегляду (заголовок із закриттям, прокручуваний вміст, ряд кнопок); `QuietAction` — тиха текстова дія.

- **WatchDialogs** (р.13)
  - `confirmLicensed()` р.18
  - `teams()` р.24
  - `linkLabel()` р.29
- **WatchDialogFrame** (р.59)
- **_WatchDialogFrameState** (р.72)
- **QuietAction** (р.155)
- **_LicenseDialog** (р.194)
- **_TeamsDialog** (р.245)
- **_TeamBlock** (р.271)
- **_TeamBlockState** (р.282)

### `lib/widgets/hikka/hikka_watch_section.dart` (567 р.)
`HikkaWatchSection(anime, route, scale, pad)` — блок «Дивитись» (правило «Блок Дивитись на сторінці аніме»): стан `WatchLoad` з `HikkaRoute.memo['watch']`; шапка з «Джерела» і «Оновити»; картка ліцензії → `_ack` → плеєр; порожній стан («Не знайшли, де це дивитись українською» / «Усі джерела вимкнено») з «Спробувати ще» й «Джерела», примітки про джерела без серій, помилки джерел, «Ще шукаю…»; одна головна дія («Дивитись / Продовжити · серія N», «З першої серії») + рядок озвучки за замовчуванням (`_voiceRow`) + `EpisodeNote`; сітка серій; «Джерело: … · На сайті». Усі цілі дотику на телефоні ≥ `AppPlatform.touchTarget`.

- **HikkaWatchSection** (р.25)
- **_HikkaWatchSectionState** (р.37)

### `lib/widgets/hikka/sources_dialog.dart` (145 р.)
`SourcesDialog.show(context, scale:, registry:)` — «Джерела перегляду»: перемикачі сайтів (`SourcePrefs.setEnabled`; підказка від джерела), «Якість відео» (`maxHeight`), «Плеєр за замовчуванням» (`hoster`: Авто / Moon / Ashdi), «Ключ Mikai API» (`AppSearchField`; зберігається через 600 мс після набору й при закритті вікна; `SourceRegistry` одразу передає його в `MikaiSource`). Зміни діють одразу. `SourcesDialog.searchSignature(registry)` — відбиток налаштувань, від яких залежить пошук (ввімкнені сайти + ключ): змінився → блок «Дивитись» шукає наново.

- **SourcesDialog** (р.17)
  - `show()` р.23
  - `searchSignature()` р.28
- **_SourcesDialogState** (р.38)

### `lib/widgets/home_hub.dart` (273 р.)
`HomeHub(scale, onOpenFile, onOpenMultipleFiles, onOpenQueue, onOpenSettings({tab}), reserveBottom)` — оболонка застосунку: чотири вкладки `MainTab` (`iconOf`), на телефоні в портреті — нижня навігація (`bottomNavHeight` 64 dp, цілі ≥ 48, `Semantics(selected)`), на ПК і широких екранах — `AppSidebar` (монограма «M», `AppIdentity.name` / `tagline`, «Налаштування», версія). Сам вміст — `HikkaHub`; локальна медіатека (`LocalLibrary`) передається йому будівельником. `HomeHub.backHandler` (статичний) = `HikkaNav.back()`; `isCompact(context)`; `debugReset()` — для тестів.

- **HomeHub** (р.16)
- **_HomeHubState** (р.66)

### `lib/widgets/local_library.dart` (1234 р.)
`LocalLibrary(scale, onOpenFile, onOpenMultipleFiles, onOpenQueue, reserveBottom)` — колишній головний екран (відкрити файл чи посилання, історія файлів, остання черга й плейлисти), тепер прихована «Локальна медіатека» (правило «Локальна медіатека»); відкривається з «Профілю» сторінкою стека.

- **LocalLibrary** (р.17)
- **_LocalLibraryState** (р.39)

### `lib/widgets/mini_player.dart` (211 р.)
Міні-плеєр (вікно поверх): підпис часу й смужка прогресу з `PlaybackClock`, перемотка кліком.

- **MiniPlayer** (р.12)
- **_MiniPlayerState** (р.32)

### `lib/widgets/mobile_controls.dart` (452 р.)
Керування відтворенням для телефона (портрет і альбомна): угорі назад / назва (тап — інформація) / PiP / поворот (довге — автоповорот) / налаштування; по центру попередня · −N с · пауза · +N с · наступна; унизу повзунок із часом і ряд швидкість · Anime4K (довге — перемкнути) · субтитри · звук · епізоди. Усі цілі дотику ≥ 48 dp, розміри в dp. Потрібен `Stack` (повертає `Positioned.fill`). Параметри `onPrevious` / `onNext` (як у `BottomDock`) і `showTransport` (false — перемотка й пауза плавно ховаються, поки `RemoteStatusOverlay` показує стан серії).

- **MobileControls** (р.20)

### `lib/widgets/mobile_gesture_layer.dart` (226 р.)
Жести на відео для телефона: вертикально по лівій половині — яскравість, по правій — системна гучність (записи не частіше ~25/с), горизонтально — перемотка (застосовується, коли палець відпущено). Початок жесту = точка дотику (`DragStartBehavior.down`), краї екрана (системні жести) ігноруються. Тапи й подвійний тап лишаються за `VideoViewport`.

- **MobileGestureLayer** (р.20)
- **_Kind** (р.47)
- **_MobileGestureLayerState** (р.49)

### `lib/widgets/mobile_sheet.dart` (158 р.)
Рамка меню для телефона: у портреті нижня панель (до 68 % висоти, «ручка» і затемнення), в альбомній — бічна панель справа (340…440 dp). Малює лише поверхню; вміст — `SettingsDrawer(sheet: true)` / `SidePanel(sheet: true)`.

- **MobileSheetFrame** (р.12)
  - `sideWidth()` р.28
- **_GrabHandle** (р.131)

### `lib/widgets/osd_toast.dart` (185 р.)
Плашка OSD поверх відео (заголовок, значення, клавіші, смужка прогресу, помилка); плавна поява, не перехоплює кліки. `topInset` — відступ під виріз / рядок стану на телефоні.

- **OsdToast** (р.10)
- **_OsdPill** (р.45)
- **_OverlayKeyCap** (р.157)

### `lib/widgets/remote_panel.dart` (374 р.)
`RemotePanelBody(scale, driver, sheet, onEpisodeSelected)` — вміст бічної панелі / шторки для серій із сайтів: вкладки «Серії» (позначки «переглянуто» з `WatchStore`, поточна підсвічена, список сам прокручується до неї — `animate` лише при зміні серії), «Озвучка» (підпис «Вибір запам'ятовується»; для поточного варіанта з розбіжністю нумерації — компактний `EpisodeNote` над списком; рядки «вид · N з M сер. · джерело» з жовтим прапорцем; перемикання — `driver.switchGroup`), «Плеєр» (плеєр сайту й якість: `switchHoster`, `switchQuality`). `sheet: true` — вищі рядки під дотик (56 dp). Черги файлів тут немає: додавання, видалення й порядок не потрібні.

- **_RemoteTab** (р.12)
- **RemotePanelBody** (р.17)
- **_RemotePanelBodyState** (р.37)

### `lib/widgets/remote_status_overlay.dart` (155 р.)
`RemoteStatusOverlay(scale, driver, onOpenPanel, onClose)`: поки `driver.showsStatus` — картка поверх відео («Шукаю відео…», «Запускаю плеєр…», після збою — причина й дії: «Спробувати ще», «Інший плеєр» (`alternativeHoster`), «Озвучки та плеєри», «Наступна серія», «Закрити»). Поки відео йде — нічого не малює й не перехоплює дотики. Повертає `Positioned.fill` (потрібен `Stack`).

- **RemoteStatusOverlay** (р.12)

### `lib/widgets/settings_drawer.dart` (675 р.)
Випадне меню налаштувань/треків/швидкості; сторінка Anime4K (Fast / HQ, шість режимів із комбінаціями Ctrl+1…6, «Вимкнено» — Ctrl+0). `sheet: true` — режим меню-панелі для телефона (шапка 56 dp, рядки ≥ 48 dp, без підказок клавіш). Необовʼязковий `onAddSubtitleFile` → пункт «Додати файл субтитрів…» у меню субтитрів. У меню «Аудіодоріжка» під списком — `_AudioDelayRow` (крок 50 мс, ±10 с, кнопка скидання; `audioDelayKey` з контролера через `ControlsOverlay`/`SettingsDrawer` зберігає значення для твору).

- **SettingsDrawer** (р.14)

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

### `lib/widgets/side_panel.dart` (779 р.)
Бокова панель: черга / інфо / розділи (chapters). `sheet: true` — режим меню-панелі для телефона (великі кнопки, черга міняється порядок перетягуванням). Параметр `remote` (`RemoteDriver?`): коли `remote.active`, вкладка «Серії» показує `RemotePanelBody` (заголовок «Серії (N)»), а в «Інформації» замість шляху до файлу — серія, озвучка й плеєр (`_fileRows`).

- **SidePanelType** (р.16)
- **SidePanel** (р.18)
- **_SidePanelState** (р.63)

### `lib/widgets/side_panel_drawer.dart` (73 р.)
Анімована обгортка SidePanel. Параметр `remote` передається в `SidePanel`.

- **SidePanelDrawer** (р.8)

### `lib/widgets/skip_button.dart` (159 р.)
Кнопка пропуску глави/опенінгу. Стежить за `PlaybackClock` через `ClockValue` + `AppClockBuilder`: перебудовується лише коли кнопка з'являється/зникає. `touch: true` — телефон: висота 48 dp, стоїть над нижньою панеллю.

- **SkipButton** (р.11)
- **_SkipButtonState** (р.35)

### `lib/widgets/stats_overlay.dart` (421 р.)
Stats overlay (AppModalShell): вкладки «Огляд», «Логи libmpv», «Джерела» (`SourceLog`, автопрокрутка донизу, очищення); «Зберегти у файл» (`LogExport.save`: журнал сесії + поточний стан + логи libmpv) і значок копіювання звіту в буфер (`_videoBlock` — спільний блок).

- **StatsOverlay** (р.14)
- **_StatsOverlayState** (р.42)

### `lib/widgets/subtitle_settings_dialog.dart` (410 р.)
Діалог стилю субтитрів.

- **SubtitleSettingsDialog** (р.11)
  - `show()` р.21
- **_SubtitleSettingsDialogState** (р.33)

### `lib/widgets/top_dock.dart` (161 р.)
Верхня панель (тривалість — з `PlaybackClock`).

- **TopDock** (р.9)

### `lib/widgets/video_viewport.dart` (154 р.)
Відео + жести (гучність колесом, 2x утримання).

- **VideoViewport** (р.6)
- **_VideoViewportState** (р.35)

### `lib/widgets/watch_callout.dart` (71 р.)
Застереження про серії: `watchWarnColor()` (жовтий; темніший на світлій темі), `episodeCheckWarns(check)` (чи ставити жовтий прапорець: `incomplete` / `mismatch`), `WatchCallout` (плашка з іконкою) і `EpisodeNote(scale, check, compact)` — пояснення розбіжності нумерації з Hikka; використовують блок «Дивитись» і вкладка «Озвучка» в плеєрі.

- **WatchCallout** (р.14)
- **EpisodeNote** (р.48)

- **Телефон, налаштування**: у портреті `HomeHub.onOpenSettings` без розділу викликає `HikkaNav.openSettings()` (маршрут `HikkaRouteKind.settings`, сторінка поверх вкладки, нижня навігація видима; вміст — `AppSettingsDialog(embedded: true)` через `settingsBuilder`); на ПК й у альбомній — вікно. Стрічка календаря (`hikka_airing_strip.dart`) при відкритті прокручується до першої серії поточної години (інакше найближчої наступної), `HikkaAiring.isCurrent`.
- **Moon через офіційний API**: `SourcePrefs.effectiveMoonKey` = власний ключ із налаштувань (поле «Свій ключ Moon API» у `SourcesDialog`) або безкоштовний ключ із бекенду (`BackendClient.cachedMoonKey`, сервер віддає його через `config`); вбудованого ключа в застосунку немає (файл `moon_key.dart` прибрано). Без ключа чи при збої API діє розбір сторінки плеєра.
- **Умова Moon (Ashdi)**: `StreamResolver.withoutAshdiWhereMoon(hosters)` — де в серії є Moon, Ashdi прибирається і з вибору (`ResolvedStream.hosters`, «Інший плеєр», панель серій), і з автопідстановки; Ashdi лишається лише там, де Moon нема. У `SourcesDialog` «Плеєр за замовчуванням» = Авто / Moon.


### `lib/widgets/hikka/hikka_overview_page.dart` (157 р.)
`HikkaOverviewPage(scale, bottomInset, refreshToken)` — розділ «Усе» в Огляді (перший і типовий): стрічка календаря `HikkaAiringStrip`, полиця «Каталог», добірки по 3 «Колекції» й «Статті», полиця «Персонажі»; кнопка «Усі» відкриває повний розділ (`HikkaNav.setTab`).


### `lib/services/backend_client.dart` (~135 р.)
`BackendClient` (одинак `BackendClient.instance`, розділ сховища `backend`) — клієнт бекенду на Firebase Functions (проєкт `miki-miki-729d9`, `europe-west1`; код сервера — окремий архів `miki_backend`: `session`, `hikkaToken`, `config`). `ensureSession()` — анонімна сесія на 30 днів (заголовок `x-session`, одна спроба з новою при 401); `hikkaToken(ref)` — обмін коду входу Hikka на токен (секрет клієнта лише на сервері; власний клієнт з налаштувань і далі обмінюється напряму); `refreshMoonKey()` / `cachedMoonKey` — ключ Moon з бекенду (`SourcePrefs.effectiveMoonKey`: власний > з бекенду; вбудованого ключа нема). Запускається у фоні з `main`. Транспорт підміняється (`BackendTransport`); у тестах — `FakeBackend` (`test/support/hikka_account_fakes.dart`).

Примітка: `HikkaClientKey` (`services/hikka_client_key.dart`) тепер містить лише референс клієнта (замаскований; не секрет); секрету клієнта Hikka в застосунку немає — код входу міняє бекенд (`BackendClient.hikkaToken`). У тестах — `HikkaClientKey.testReference`.

Примітка (позначки й календар): `HikkaMyList.statusOf(slug)` / `loadIndex()` — статус кожного тайтлу зі списків (один прохід по всіх статусах, по 100 за запит; запускається з `main` і при вході); `HikkaAnimeCard(showStatus: true)` малює смужку зі статусом унизу постера (кольори `hikkaStatusColor`; у «Списках» вимкнено). `HikkaSchedulePage` — вкладки Пн–Нд (відкривається на сьогодні), серії найближчих 7 діб вибраного дня, свайп між днями (`HikkaSwipeTabs`). Заглушки замість кіл: `HikkaCardSkeleton` (сітка), `HikkaListSkeleton` (колекції, статті), `_ScheduleSkeleton`.

Примітка («Продовжити перегляд»): картки горизонтальні — `HikkaContinueCard` (`widgets/hikka/hikka_continue_card.dart`; мініатюра, назва, «Серія N · коли», кнопка ▶; довге натискання / права кнопка — прибрати з історії). Тап викликає `QuickPlay.resume(anime)` (`services/quick_play.dart`): запускає пошук озвучок (`WatchService.start`), чекає першу знайдену (до 25 с), бере варіант за замовчуванням і серію за `continuePoint`, відкриває плеєр через `WatchLauncher.play`; якщо не вийшло (нічого не знайдено, тайтл ліцензований, плеєр не готовий) — відкривається сторінка тайтлу. `HikkaShelf` / `HikkaShelfAsync` / `HikkaShelfSkeleton` мають `cardWidth` / `cardHeight` для нестандартних карток; `showHikkaRemoveMenu` — спільне меню «Прибрати зі списку».
