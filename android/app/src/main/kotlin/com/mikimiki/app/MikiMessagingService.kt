package com.mikimiki.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Notification channels of the app (heads-up importance: a pop-up window, not only an icon in the status bar) */
object PushChannels {
    const val EPISODES = "episodes_alert"
    const val NEWS = "news"

    fun ensure(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        // Importance of an existing channel cannot be raised from code, so the pop-up channels have new ids
        nm.deleteNotificationChannel("episodes")
        val episodes = NotificationChannel(EPISODES, "Нові серії", NotificationManager.IMPORTANCE_HIGH)
        episodes.description = "Сповіщення про нові серії в озвученні, яке ви дивитесь"
        nm.createNotificationChannel(episodes)
        // Announcements from the developer and "new version" notices (sent by the backend's pushAdmin)
        val news = NotificationChannel(NEWS, "Новини та оновлення", NotificationManager.IMPORTANCE_HIGH)
        news.description = "Повідомлення від розробника та новини про оновлення застосунку"
        nm.createNotificationChannel(news)
    }
}

/**
 * The backend sends data-only messages (`type`, `title`, `body`, `slug`, `image`, …), so this runs whether the app is open or
 * closed: it shows the notification itself and ALSO writes it to a small inbox (SharedPreferences) that Dart empties into the
 * "Сповіщення" tab (`pushInbox` on the system channel). That is how every push, including manual test ones, ends up in the app.
 */
class MikiMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // Dart asks for the token itself and re-registers when it changes (PushNotifications.sync)
    }

    override fun onMessageReceived(msg: RemoteMessage) {
        val d = msg.data
        val title = d["title"] ?: msg.notification?.title ?: return
        val body = d["body"] ?: msg.notification?.body ?: ""
        val type = d["type"] ?: "episode"
        val slug = d["slug"] ?: ""
        val image = d["image"]?.takeIf { it.startsWith("https://") }
        val now = System.currentTimeMillis()
        val id = d["id"] ?: (msg.messageId ?: "push|$now")

        store(this, JSONObject().apply {
            put("id", id)
            put("type", type)
            put("title", title)
            put("body", body)
            put("slug", slug)
            if (image != null) put("image", image)
            put("episode", d["episode"] ?: "")
            put("team", d["team"] ?: "")
            put("kind", d["kind"] ?: "")
            put("release", d["release"] ?: "")
            put("t", now)
        })
        show(title, body, type, slug, image, id)
    }

    private fun show(title: String, body: String, type: String, slug: String, image: String?, id: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        PushChannels.ensure(this)
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val channel = if (type == "episode") PushChannels.EPISODES else PushChannels.NEWS
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            when {
                // "New version": the tap opens the update window
                type == "update" -> putExtra("push_open", "update")
                slug.isNotEmpty() -> putExtra("push_slug", slug)
                // An announcement without a title opens the "Сповіщення" page, where it is shown whole
                type == "news" -> putExtra("push_open", "notifications")
            }
        }
        val notifId = if (slug.isNotEmpty() && type == "episode") slug.hashCode() else id.hashCode()
        val tap = PendingIntent.getActivity(this, notifId, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channel) else Notification.Builder(this)
        // The status bar draws only the shape of the small icon: a white silhouette, not the colored launcher icon
        b.setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) b.setPriority(Notification.PRIORITY_HIGH)
        if (image != null) download(image)?.let { b.setLargeIcon(it) }
        nm.notify(notifId, b.build())
    }

    /** The poster for the notification; on any failure there is simply no picture */
    private fun download(url: String): Bitmap? = try {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 5000
        c.readTimeout = 5000
        c.inputStream.use { BitmapFactory.decodeStream(it) }
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val PREFS = "miki_push_inbox"
        private const val KEY = "items"
        private const val MAX = 100
        private val lock = Any()

        private fun store(ctx: Context, item: JSONObject) = synchronized(lock) {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val old = try { JSONArray(p.getString(KEY, "[]")) } catch (_: Exception) { JSONArray() }
            val out = JSONArray()
            out.put(item)
            for (i in 0 until minOf(old.length(), MAX - 1)) out.put(old.get(i))
            p.edit().putString(KEY, out.toString()).apply()
        }

        /** The saved pushes as a JSON array; the inbox is emptied */
        fun drain(ctx: Context): String = synchronized(lock) {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val s = p.getString(KEY, "[]") ?: "[]"
            p.edit().remove(KEY).apply()
            s
        }
    }
}
