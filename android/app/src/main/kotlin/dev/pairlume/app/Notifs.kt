// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import androidx.annotation.WorkerThread
import androidx.core.graphics.createBitmap
import dev.pairlume.core.Message
import dev.pairlume.core.longNumber
import dev.pairlume.core.maybeLong
import dev.pairlume.core.message
import dev.pairlume.core.text
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** what the owner switched on here for notifications, and the apps left out */
class NotifChoices(c: Context) {
    private val app = c.applicationContext
    private val p = app.getSharedPreferences("choices", Context.MODE_PRIVATE)
    var on: Boolean
        get() = p.getBoolean("notifs_on", false) && granted(app)
        set(v) = p.edit().putBoolean("notifs_on", v).apply()
    var skipped: Set<String>
        get() = p.getStringSet("notifs_skip", emptySet()) ?: emptySet()
        set(v) = p.edit().putStringSet("notifs_skip", v).apply()
    /** apps that showed something lately, for the list to leave out */
    var seen: Set<String>
        get() = p.getStringSet("notifs_seen", emptySet()) ?: emptySet()
        set(v) = p.edit().putStringSet("notifs_seen", v).apply()

    companion object {
        /** Android's own switch: Settings, Notification access */
        fun granted(c: Context): Boolean {
            val me = ComponentName(c, Notifs::class.java).flattenToString()
            return (Settings.Secure.getString(c.contentResolver, "enabled_notification_listeners") ?: "").split(':').contains(me)
        }
        fun openAccess(c: Context) = try {
            c.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) { }
    }
}

/**
 * Reads the notifications of the phone, only after the owner gave Pairlume notification access, and only while the
 * switch is on. Nothing is kept: the computer gets them, the phone forgets.
 */
class Notifs : NotificationListenerService() {
    // Android calls in on the main thread; describing a notification (its app's icon among it) is work for another one
    private val work = Executors.newSingleThreadExecutor()

    override fun onListenerConnected() {
        current = this
        work.execute(::sendAll)
    }

    override fun onDestroy() {
        work.shutdown()
        super.onDestroy()
    }

    override fun onListenerDisconnected() {
        if (current === this) current = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        work.execute { describe(sbn)?.let(LinkService::notify) }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (!NotifChoices(this).on) return
        LinkService.notify(message("notif_gone", "key" to sbn.key))
    }

    /** all there are now, as when the computer connects */
    @WorkerThread
    fun sendAll() {
        if (!NotifChoices(this).on) return
        try { activeNotifications?.forEach { s -> describe(s)?.let(LinkService::notify) } } catch (_: Exception) { }
    }

    @WorkerThread
    private fun describe(sbn: StatusBarNotification): Message? {
        val choices = NotifChoices(this)
        if (!choices.on) return null
        val n = sbn.notification ?: return null
        if (sbn.packageName == packageName || sbn.isOngoing || n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return null
        if (n.visibility == Notification.VISIBILITY_SECRET) return null
        if (sbn.packageName in choices.skipped) return null
        choices.seen = (choices.seen + sbn.packageName).let { if (it.size > 80) it.drop(it.size - 80).toSet() else it }
        val x = n.extras
        val title = (x.getCharSequence(Notification.EXTRA_TITLE) ?: "").toString()
        val text = (x.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: x.getCharSequence(Notification.EXTRA_TEXT) ?: "").toString()
        if (title.isBlank() && text.isBlank()) return null
        val actions = (n.actions ?: emptyArray()).take(3)
        val base = message("notif", "key" to sbn.key, "app" to sbn.packageName, "app_name" to appName(sbn.packageName),
            "title" to title.take(200), "text" to text.take(2000), "when" to sbn.postTime)
        val withActions = JsonObject(base + ("actions" to JsonArray(actions.map { a ->
            buildJsonObject { put("title", (a.title ?: "").toString().take(40)); if (!a.remoteInputs.isNullOrEmpty()) put("reply", true) }
        })))
        val icon = LinkService.iconFor(sbn.packageName) { icon(sbn.packageName) }
        return if (icon == null) withActions else JsonObject(withActions + ("icon" to JsonPrimitive(icon)))
    }

    private fun appName(pkg: String) = try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString() } catch (_: Exception) { pkg }

    /** the app's icon, 64 px, as base64 PNG */
    private fun icon(pkg: String): String? = try {
        val d = packageManager.getApplicationIcon(pkg)
        val b = createBitmap(64, 64)
        d.setBounds(0, 0, 64, 64)
        d.draw(Canvas(b))
        val png = ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        if (png.size <= 40_000) Base64.encodeToString(png, Base64.NO_WRAP) else null
    } catch (_: Exception) { null }

    /** the answer to notif_do */
    fun answer(m: Message): Message {
        val req = m.longNumber("req")
        fun no(why: String) = message("notif_error", "req" to req, "reason" to why)
        if (!NotifChoices(this).on) return no(t("Notifications are off in Pairlume on the phone"))
        val key = m.text("key")
        val sbn = try { activeNotifications?.firstOrNull { it.key == key } } catch (_: Exception) { null } ?: return no(t("That notification is gone"))
        return try {
            when (m.text("what")) {
                "dismiss" -> cancelNotification(key)
                "action", "reply" -> {
                    val i = m.maybeLong("action")?.toInt() ?: return no(t("Which button?"))
                    val a = sbn.notification.actions?.getOrNull(i) ?: return no(t("It has no such button"))
                    if (m.text("what") == "reply") {
                        val inputs = a.remoteInputs ?: return no(t("That button takes no answer"))
                        val text = m.text("text")
                        if (text.isBlank() || text.length > 2000) return no(t("An answer has 1 to 2000 characters"))
                        val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, text) } }
                        val fill = Intent().addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
                        RemoteInput.addResultsToIntent(inputs, fill, results)
                        a.actionIntent.send(this, 0, fill)
                    } else {
                        a.actionIntent.send()
                    }
                }
                else -> return no(t("The phone does not know that"))
            }
            message("notif_done", "req" to req)
        } catch (_: PendingIntent.CanceledException) {
            no(t("The app no longer takes that"))
        } catch (_: Exception) {
            no(t("The phone could not do that"))
        }
    }

    companion object {
        @Volatile var current: Notifs? = null
    }
}
