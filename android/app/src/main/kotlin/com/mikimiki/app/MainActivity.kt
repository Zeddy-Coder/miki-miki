package com.mikimiki.app

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioDeviceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.graphics.drawable.Icon
import android.os.PowerManager
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import com.google.firebase.FirebaseApp
import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * Besides the regular Flutter activity, this gives Dart code what the framework lacks:
 * picture-in-picture (PiP), screen brightness, system volume and opening links in a browser.
 * Channel `miki_miki/system`; the methods are described in `lib/services/system_controls.dart`.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Enter PiP automatically when the user leaves the app (only during playback) */
    private var pipAuto = false
    private var pipRatio = Rational(16, 9)

    /** Playback is running: decides the icon of the "pause / play" button in the PiP window */
    private var pipPlaying = false
    private var pipReceiver: BroadcastReceiver? = null

    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false

    /** Посилання `miki://open/…`, з яким запустили застосунок (віддається Dart один раз) */
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLink = mikiLink(intent)
        registerPipReceiver()
        createPushChannel()
    }

    override fun onDestroy() {
        pipReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        pipReceiver = null
        abandonAudioFocus()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = mikiLink(intent) ?: return
        val ch = channel
        if (ch != null) ch.invokeMethod("deepLink", link) else pendingLink = link
    }

    private fun mikiLink(i: Intent?): String? {
        // A tap on a push notification "new episode": FCM puts the data fields into the launch intent
        val own = i?.extras?.getString("push_slug") // our own notification (MikiMessagingService)
        if (!own.isNullOrEmpty()) return "miki://open/anime/" + Uri.encode(own)
        val slug = i?.extras?.getString("slug")
        if (!slug.isNullOrEmpty() && i.extras?.containsKey("google.message_id") == true) {
            return "miki://open/anime/" + Uri.encode(slug)
        }
        val uri = i?.data ?: return null
        return if (i.action == Intent.ACTION_VIEW && uri.scheme == "miki") uri.toString() else null
    }

    // ── Push (FCM) ───────────────────────────────────────────────────────────

    private fun createPushChannel() = PushChannels.ensure(this)

    /**
     * FCM token of this device. An error (with the reason) if Firebase is not set up in this build or the token cannot be got.
     * If the first try fails, the stale Firebase Installations / FCM state of this phone is reset and the token is asked once more
     * (a leftover registration from a removed or recreated Firebase app answers FIS_AUTH_ERROR for ever).
     */
    private fun pushToken(result: MethodChannel.Result) {
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                result.error("no_firebase", "FirebaseApp is not initialized: google-services.json was not in this build", null)
                return
            }
            val messaging = FirebaseMessaging.getInstance()
            messaging.token.addOnCompleteListener { first ->
                if (first.isSuccessful) {
                    result.success(first.result)
                    return@addOnCompleteListener
                }
                val firstError = first.exception?.toString() ?: "unknown error"
                try {
                    FirebaseInstallations.getInstance().delete().addOnCompleteListener {
                        messaging.deleteToken().addOnCompleteListener {
                            messaging.token.addOnCompleteListener { second ->
                                if (second.isSuccessful) {
                                    result.success(second.result)
                                } else {
                                    result.error("token_failed", "${second.exception} (first try: $firstError)", null)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    result.error("token_failed", "$e (first try: $firstError)", null)
                }
            }
        } catch (e: Exception) {
            result.error("exception", e.toString(), null)
        }
    }

    /**
     * Why the token cannot be got: repeats from this phone the request Firebase Installations makes, and reports the answer of
     * Google, the Play services version and how far the phone's clock is from Google's. Runs off the main thread.
     */
    private fun pushDiagnose(result: MethodChannel.Result) {
        Thread {
            val out = StringBuilder()
            try {
                val o = FirebaseApp.getInstance().options
                val pkg = packageName
                val sig = packageManager.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo?.apkContentsSigners?.firstOrNull()
                val sha1 = sig?.let {
                    java.security.MessageDigest.getInstance("SHA-1").digest(it.toByteArray()).joinToString("") { b -> "%02X".format(b) }
                } ?: "?"
                val gms = try { packageManager.getPackageInfo("com.google.android.gms", 0).versionName } catch (_: Exception) { "NOT INSTALLED" }
                out.append("app=$pkg sha1=${sha1.take(8)}… gms=$gms\n")
                val rnd = ByteArray(17)
                java.security.SecureRandom().nextBytes(rnd)
                rnd[0] = ((rnd[0].toInt() and 0x0F) or 0x70).toByte()
                val fid = android.util.Base64.encodeToString(rnd, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING).take(22)
                val conn = java.net.URL("https://firebaseinstallations.googleapis.com/v1/projects/${o.projectId}/installations")
                    .openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("x-goog-api-key", o.apiKey)
                conn.setRequestProperty("X-Android-Package", pkg)
                conn.setRequestProperty("X-Android-Cert", sha1)
                conn.outputStream.use {
                    it.write("""{"fid":"$fid","appId":"${o.applicationId}","authVersion":"FIS_v2","sdkVersion":"a:17.2.0"}""".toByteArray())
                }
                val code = conn.responseCode
                val body = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: ""
                val server = conn.getHeaderFieldDate("Date", 0L)
                val skew = if (server > 0) (System.currentTimeMillis() - server) / 1000 else null
                out.append("FIS create: HTTP $code")
                if (code !in 200..299) out.append(" ${body.replace(Regex("\\s+"), " ").take(260)}")
                out.append("\nclock skew vs Google: ${skew ?: "?"} s")
            } catch (e: Exception) {
                out.append("diagnose failed: $e")
            }
            runOnUiThread { result.success(out.toString()) }
        }.start()
    }

    private var pushPermissionResult: MethodChannel.Result? = null

    /** Android 13+: asks for the notification permission; true if notifications are allowed */
    private fun requestPushPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pushPermissionResult?.success(false)
        pushPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4711)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4711) {
            pushPermissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pushPermissionResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "miki_miki/system")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "pipSupported" -> result.success(pipSupported())
                "pipEnter" -> {
                    updateRatio(call.argument<Int>("w"), call.argument<Int>("h"))
                    result.success(enterPip())
                }
                "pipAuto" -> {
                    pipAuto = call.argument<Boolean>("enabled") ?: false
                    updateRatio(call.argument<Int>("w"), call.argument<Int>("h"))
                    applyPipParams()
                    result.success(null)
                }
                "pipPlaying" -> {
                    pipPlaying = call.argument<Boolean>("playing") ?: false
                    applyPipParams()
                    result.success(null)
                }
                "audioFocus" -> {
                    if (call.argument<Boolean>("enabled") == true) requestAudioFocus() else abandonAudioFocus()
                    result.success(hasFocus)
                }
                "getBrightness" -> result.success(currentBrightness())
                "setBrightness" -> {
                    setBrightness(call.argument<Double>("value") ?: 0.5)
                    result.success(null)
                }
                "getVolume" -> result.success(currentVolume())
                "setVolume" -> {
                    setVolume(call.argument<Double>("value") ?: 0.5)
                    result.success(null)
                }
                "openUrl" -> result.success(openUrl(call.argument<String>("url"), call.argument<Boolean>("chooser") ?: false))
                "initialLink" -> {
                    val link = pendingLink
                    pendingLink = null
                    result.success(link)
                }
                "deviceInfo" -> result.success(deviceInfo())
                "pushInbox" -> result.success(MikiMessagingService.drain(this))
                "pushToken" -> pushToken(result)
                "pushDiagnose" -> pushDiagnose(result)
                "pushPermission" -> requestPushPermission(result)
                else -> result.notImplemented()
            }
        }
    }

    // ── Picture-in-picture ──────────────────────────────────────────────────

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** Android accepts aspect ratios only within 1:2.39 … 2.39:1 */
    private fun updateRatio(w: Int?, h: Int?) {
        if (w == null || h == null || w <= 0 || h <= 0) return
        val r = w.toDouble() / h.toDouble()
        pipRatio = when {
            r > 2.39 -> Rational(239, 100)
            r < 1.0 / 2.39 -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipRatio).setActions(pipActions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: PiP entry via the "home" gesture without onUserLeaveHint
            builder.setAutoEnterEnabled(pipAuto)
        }
        return builder.build()
    }

    /** "Pause / play" button in the PiP window: the tap arrives in [pipReceiver] and goes to Dart */
    private fun pipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        val icon = Icon.createWithResource(
            this,
            if (pipPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
        )
        val title = if (pipPlaying) "Пауза" else "Відтворити"
        val intent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(ACTION_PIP_TOGGLE).setPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return listOf(RemoteAction(icon, title, title, intent))
    }

    private fun registerPipReceiver() {
        if (!pipSupported()) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_PIP_TOGGLE) channel?.invokeMethod("pipToggle", null)
            }
        }
        val filter = IntentFilter(ACTION_PIP_TOGGLE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        pipReceiver = receiver
    }

    private fun applyPipParams() {
        if (!pipSupported()) return
        try {
            setPictureInPictureParams(buildPipParams())
        } catch (_: Exception) {
        }
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        return try {
            enterPictureInPictureMode(buildPipParams())
        } catch (_: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Before Android 12 there is no automatic entry, so we enter ourselves
        if (pipAuto && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    // ── Links ────────────────────────────────────────────────────────────

    /** Opens an http(s) link in a browser; [chooser] shows the app picker. false: the address is invalid or there is no browser */
    private fun openUrl(url: String?, chooser: Boolean = false): Boolean {
        if (url.isNullOrBlank()) return false
        val uri = Uri.parse(url)
        if (uri.scheme != "http" && uri.scheme != "https") return false
        return try {
            val view = Intent(Intent.ACTION_VIEW, uri)
            val intent = if (chooser) Intent.createChooser(view, "Відкрити в…") else view
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    // ── Brightness and volume ────────────────────────────────────────────

    private fun currentBrightness(): Double {
        val own = window.attributes.screenBrightness
        if (own >= 0f) return own.toDouble()
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
        } catch (_: Exception) {
            0.5
        }
    }

    private fun setBrightness(value: Double) {
        val params = window.attributes
        params.screenBrightness = if (value < 0) {
            // A negative value restores the system brightness (on the home page)
            WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        } else {
            // 0 turns the backlight off entirely on some devices, so we keep a minimum
            value.coerceIn(0.01, 1.0).toFloat()
        }
        window.attributes = params
    }

    // ── Audio focus: other background music is paused while a video plays ──

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        val event = when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> "loss"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "transient"
            AudioManager.AUDIOFOCUS_GAIN -> "gain"
            else -> null // "Duck" is ignored: the video plays at full volume
        }
        if (event != null) runOnUiThread { channel?.invokeMethod("audioFocus", event) }
    }

    private fun requestAudioFocus() {
        if (hasFocus) return
        val am = audio()
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build(),
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        hasFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocus() {
        if (!hasFocus && focusRequest == null) return
        val am = audio()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
        focusRequest = null
        hasFocus = false
    }

    private fun audio(): AudioManager = getSystemService(AUDIO_SERVICE) as AudioManager

    private fun currentVolume(): Double {
        val am = audio()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return if (max > 0) am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max else 0.0
    }

    private fun setVolume(value: Double) {
        val am = audio()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, (value.coerceIn(0.0, 1.0) * max).roundToInt(), 0)
    }

    // ── Diagnostics (for the log) ────────────────────────────────────────────

    /** Device, memory, power saving, screen refresh rate and audio route. Read-only. */
    @Suppress("DEPRECATION")
    private fun deviceInfo(): Map<String, Any?> {
        val info = HashMap<String, Any?>()
        info["model"] = "${Build.MANUFACTURER} ${Build.MODEL}"
        info["android"] = "${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
        info["hardware"] = "${Build.HARDWARE} / ${Build.SUPPORTED_ABIS.firstOrNull() ?: "?"}"
        try {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am.getMemoryInfo(mi)
            info["ramTotalMb"] = (mi.totalMem / (1024 * 1024)).toInt()
            info["ramFreeMb"] = (mi.availMem / (1024 * 1024)).toInt()
            info["lowMemory"] = mi.lowMemory
        } catch (_: Exception) {
        }
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            info["powerSave"] = pm.isPowerSaveMode
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info["thermal"] = pm.currentThermalStatus
        } catch (_: Exception) {
        }
        try {
            info["refreshHz"] = windowManager.defaultDisplay.refreshRate.toDouble()
        } catch (_: Exception) {
        }
        try {
            val am = audio()
            info["audioRate"] = am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
            info["audioFrames"] = am.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                info["audioOut"] = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { audioTypeName(it.type) }.distinct()
            }
            info["bluetoothA2dp"] = am.isBluetoothA2dpOn
            info["wiredHeadset"] = am.isWiredHeadsetOn
        } catch (_: Exception) {
        }
        return info
    }

    private fun audioTypeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "слуховий динамік"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "динамік"
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "дротові навушники"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth (гарнітура)"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth (A2DP)"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "USB"
        26 -> "Bluetooth LE (навушники)"
        27 -> "Bluetooth LE (динамік)"
        else -> "тип $type"
    }

    companion object {
        private const val ACTION_PIP_TOGGLE = "com.mikimiki.app.PIP_TOGGLE"
    }
}
