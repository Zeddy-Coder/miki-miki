package com.mikimiki.app

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * Крім звичайної активності Flutter надає Dart-коду те, чого немає у фреймворку:
 * картинку в картинці (PiP), яскравість екрана, системну гучність і відкриття посилань у браузері.
 * Канал `miki_miki/system`, методи описані в `lib/services/system_controls.dart`.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Входити в PiP автоматично, коли користувач виходить із застосунку (лише під час відтворення) */
    private var pipAuto = false
    private var pipRatio = Rational(16, 9)

    /** Посилання `miki://open/…`, з яким запустили застосунок (віддається Dart один раз) */
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLink = mikiLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = mikiLink(intent) ?: return
        val ch = channel
        if (ch != null) ch.invokeMethod("deepLink", link) else pendingLink = link
    }

    private fun mikiLink(i: Intent?): String? {
        val uri = i?.data ?: return null
        return if (i.action == Intent.ACTION_VIEW && uri.scheme == "miki") uri.toString() else null
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
                else -> result.notImplemented()
            }
        }
    }

    // ── Картинка в картинці ──────────────────────────────────────────────────

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** Android приймає пропорції лише в межах 1:2.39 … 2.39:1 */
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
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipRatio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: вхід у PiP жестом «додому» без onUserLeaveHint
            builder.setAutoEnterEnabled(pipAuto)
        }
        return builder.build()
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
        // До Android 12 автоматичного входу немає — входимо самі
        if (pipAuto && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    // ── Посилання ────────────────────────────────────────────────────────────

    /** Відкриває http(s)-посилання у браузері; [chooser] — показати вибір програми. false — адреса недійсна або браузера немає */
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

    // ── Яскравість і гучність ────────────────────────────────────────────────

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
            // Від'ємне значення — повернути системну яскравість (на головній сторінці)
            WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        } else {
            // 0 на деяких пристроях вимикає підсвітку повністю — лишаємо мінімум
            value.coerceIn(0.01, 1.0).toFloat()
        }
        window.attributes = params
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

    // ── Діагностика (для журналу) ────────────────────────────────────────────

    /** Пристрій, памʼять, енергозбереження, частота екрана й маршрут звуку. Лише читання. */
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
}
