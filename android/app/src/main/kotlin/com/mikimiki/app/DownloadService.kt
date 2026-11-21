package com.mikimiki.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps episode downloads going while the app is in the background or the screen is off: a foreground service
 * (type `dataSync`) with a progress notification and a partial wake lock. The downloading itself is Dart's
 * (`DownloadManager`, which lives in the activity's engine): this only keeps the process awake and shows the progress
 * Dart sends over `downloadService`. The notification's button pauses everything (Dart gets `downloadsAction`), a tap
 * opens the downloads page (`push_open=downloads` → `miki://open/downloads`).
 */
class DownloadService : Service() {
    companion object {
        private const val CHANNEL = "downloads"
        private const val NOTIFICATION_ID = 4107
        private const val ACTION_SHOW = "com.mikimiki.app.downloads.SHOW"
        private const val ACTION_PAUSE = "com.mikimiki.app.downloads.PAUSE"

        /** A safety limit of the wake lock: a forgotten one must not drain the battery */
        private const val WAKE_LIMIT_MS = 6L * 60 * 60 * 1000

        @Volatile
        var running = false
            private set

        /** The notification's "Пауза": the activity forwards it to Dart */
        var onAction: ((String) -> Unit)? = null

        /**
         * Shows (or updates) the progress. The first call starts the service; later ones only replace the notification:
         * starting a foreground service from the background is forbidden since Android 12, updating it is not.
         */
        fun show(ctx: Context, title: String, text: String, progress: Int) {
            if (running) {
                post(ctx, build(ctx, title, text, progress))
                return
            }
            val i = Intent(ctx, DownloadService::class.java)
                .setAction(ACTION_SHOW)
                .putExtra("title", title)
                .putExtra("text", text)
                .putExtra("progress", progress)
            try {
                ContextCompat.startForegroundService(ctx, i)
            } catch (_: Exception) {
                // In the background on Android 12+: downloads go on while the app is open, no notification
            }
        }

        fun stop(ctx: Context) {
            if (!running) return
            try {
                ctx.stopService(Intent(ctx, DownloadService::class.java))
            } catch (_: Exception) {
            }
        }

        private fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL) != null) return
            val ch = NotificationChannel(CHANNEL, "Завантаження серій", NotificationManager.IMPORTANCE_LOW)
            ch.description = "Хід завантаження серій для перегляду без інтернету"
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }

        private fun post(ctx: Context, n: Notification) {
            try {
                ctx.getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, n)
            } catch (_: Exception) {
            }
        }

        private fun build(ctx: Context, title: String, text: String, progress: Int): Notification {
            ensureChannel(ctx)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val open = Intent(ctx, MainActivity::class.java)
                .putExtra("push_open", "downloads")
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pause = Intent(ctx, DownloadService::class.java).setAction(ACTION_PAUSE)
            return NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_notify)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setProgress(100, progress.coerceIn(0, 100), progress < 0)
                .setContentIntent(PendingIntent.getActivity(ctx, 41071, open, flags))
                .addAction(0, "Пауза", PendingIntent.getService(ctx, 41072, pause, flags))
                .build()
        }
    }

    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_PAUSE) {
            onAction?.invoke("pause")
            if (wake == null) stopSelf()
            return START_NOT_STICKY
        }
        val n = build(
            this,
            intent?.getStringExtra("title") ?: "Завантаження серій",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("progress", -1) ?: -1,
        )
        try {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
            ServiceCompat.startForeground(this, NOTIFICATION_ID, n, type)
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (wake == null) {
            try {
                val pm = getSystemService(POWER_SERVICE) as PowerManager
                wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MikiMiki:downloads").apply {
                    setReferenceCounted(false)
                    acquire(WAKE_LIMIT_MS)
                }
            } catch (_: Exception) {
            }
        }
        // Dart owns the queue: after the process dies nothing is downloading, so the service must not come back by itself
        return START_NOT_STICKY
    }

    /** The app was swiped away: Dart (and with it the downloads) is gone, the notification must not lie */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    /** Android 15: a `dataSync` service may run 6 hours a day; after that it has to stop (downloads go on when the app is open) */
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        try {
            wake?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wake = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
