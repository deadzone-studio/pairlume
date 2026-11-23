// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.net.Uri
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone as Phones
import android.provider.ContactsContract.Contacts
import android.provider.Telephony.Sms
import android.telephony.SmsManager
import android.util.Base64
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import dev.pairlume.core.Message
import dev.pairlume.core.PairlumeException
import dev.pairlume.core.SmsRate
import dev.pairlume.core.longNumber
import dev.pairlume.core.maybeLong
import dev.pairlume.core.message
import dev.pairlume.core.number
import dev.pairlume.core.text
import dev.pairlume.core.texts
import dev.pairlume.core.type
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** what the owner of the phone switched on here; the computer has its own permission for the phone */
class Choices(c: Context) {
    private val app = c.applicationContext
    private val p = app.getSharedPreferences("choices", Context.MODE_PRIVATE)
    var read: Boolean
        get() = p.getBoolean("sms_read", false) && granted(*READ)
        set(v) = p.edit().putBoolean("sms_read", v).apply()
    var send: Boolean
        get() = p.getBoolean("sms_send", false) && granted(*SEND)
        set(v) = p.edit().putBoolean("sms_send", v).apply()
    private fun granted(vararg n: String) = n.all { app.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    companion object {
        val READ = arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS)
        val SEND = arrayOf(Manifest.permission.SEND_SMS)
    }
}

/** Texts are read when the computer asks, and only then. Nothing of them is kept here. */
class Texts(private val c: Context) {
    private val rate = SmsRate()
    private val names = HashMap<String, String>()

    /** the answer to a question of the computer, null when it is not about texts */
    fun answer(m: Message): Message? {
        val req = when (m.type) {
            "sms_list", "sms_read", "sms_photos", "sms_send" -> m.longNumber("req")
            else -> return null
        }
        fun no(why: String) = message("sms_error", "req" to req, "reason" to why)
        return try {
            if (m.type == "sms_send") {
                if (!Choices(c).send) return no(t("Sending texts is off in Pairlume on the phone"))
                if (!rate.take()) return no(t("Too many texts at once. Wait a minute"))
                send(m.text("to"), m.text("text"))
                message("sms_sent", "req" to req)
            } else {
                if (!Choices(c).read) return no(t("Reading texts is off in Pairlume on the phone"))
                when (m.type) {
                    "sms_photos" -> photos(req, m.texts("addresses").take(5))
                    "sms_list" -> threads(req, m.number("limit").coerceIn(1, 60), m.maybeLong("before"))
                    else -> texts(req, m.longNumber("thread"), m.number("limit").coerceIn(1, 60), m.maybeLong("before"))
                }
            }
        } catch (e: PairlumeException) {
            no(e.message ?: "")
        } catch (_: SecurityException) {
            no(t("Android does not let Pairlume use texts"))
        } catch (_: Exception) {
            no(t("The phone could not do that"))
        }
    }

    fun nameOf(address: String) = synchronized(names) { name(address) }
    fun photoOf(address: String) = synchronized(names) { photo(address) }

    private fun name(address: String): String = names.getOrPut(address) {
        if (c.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED || address.none(Char::isDigit)) return@getOrPut ""
        c.contentResolver.query(
            Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address)),
            arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null,
        )?.use { if (it.moveToFirst()) it.getString(0) else null } ?: ""
    }

    /** every contact with this number: the same person is often saved twice (SIM, Google, Samsung), and only one has the picture */
    private fun contacts(address: String): List<Uri> {
        val ids = LinkedHashMap<Long, Uri>()
        c.contentResolver.query(
            Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address)),
            arrayOf(ContactsContract.PhoneLookup._ID, ContactsContract.PhoneLookup.LOOKUP_KEY), null, null, null,
        )?.use { while (it.moveToNext()) ids[it.getLong(0)] = Contacts.getLookupUri(it.getLong(0), it.getString(1)) }
        val tail = address.filter(Char::isDigit).takeLast(9)
        if (tail.length == 9) c.contentResolver.query(
            Phones.CONTENT_URI, arrayOf(Phones.CONTACT_ID, Phones.LOOKUP_KEY, Phones.NUMBER), null, null, null,
        )?.use { while (it.moveToNext()) if ((it.getString(2) ?: "").filter(Char::isDigit).endsWith(tail)) ids[it.getLong(0)] = Contacts.getLookupUri(it.getLong(0), it.getString(1)) }
        return ids.values.filterNotNull()
    }

    private fun picture(uri: Uri): Bitmap? = try {
        // the small one first; some phones only keep the large one
        sequenceOf(false, true).firstNotNullOfOrNull { large ->
            Contacts.openContactPhotoInputStream(c.contentResolver, uri, large)?.use { s ->
                val b = s.readBytes()
                val size = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(b, 0, b.size, size)
                val how = BitmapFactory.Options().apply { inSampleSize = (minOf(size.outWidth, size.outHeight) / 224).coerceAtLeast(1) }
                BitmapFactory.decodeByteArray(b, 0, b.size, how)
            }
        }
    } catch (_: Exception) {
        null
    }

    /** the round picture of a contact; only while the computer asks, never kept */
    private fun photo(address: String): String? {
        if (c.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED || address.none(Char::isDigit)) return null
        val src = contacts(address).firstNotNullOfOrNull(::picture) ?: return null
        val side = minOf(src.width, src.height)
        for (size in listOf(128, 96, 72)) {
            val out = createBitmap(size, size)
            val from = Rect((src.width - side) / 2, (src.height - side) / 2, (src.width + side) / 2, (src.height + side) / 2)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            Canvas(out).run {
                drawCircle(size / 2f, size / 2f, size / 2f, paint)
                paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
                drawBitmap(src, from, Rect(0, 0, size, size), paint)
            }
            val png = ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
            if (png.size <= 35_000) return Base64.encodeToString(png, Base64.NO_WRAP)
        }
        return null
    }

    private fun photos(req: Long, addresses: List<String>) = JsonObject(message("sms_faces", "req" to req) + ("faces" to buildJsonArray {
        addresses.forEach { a -> photo(a)?.let { add(buildJsonObject { put("address", a); put("png", it) }) } }
    }))

    private fun thread(id: Long, address: String, body: String, date: Long, unread: Int) = buildJsonObject {
        put("id", id); put("address", address); put("name", name(address)); put("snippet", body.take(200)); put("date", date); put("unread", unread)
    }

    private class Row(q: Cursor) {
        val id = q.getLong(0)
        val thread = q.getLong(1)
        val address = q.getString(2) ?: ""
        val body = q.getString(3) ?: ""
        val date = q.getLong(4)
        val type = q.getInt(5)
        val unread = q.getInt(6) == 0 && type == Sms.MESSAGE_TYPE_INBOX
    }

    private inline fun rows(where: String?, args: Array<String>, each: (Row) -> Boolean) {
        val cols = arrayOf(Sms._ID, Sms.THREAD_ID, Sms.ADDRESS, Sms.BODY, Sms.DATE, Sms.TYPE, Sms.READ)
        val real = "${Sms.TYPE} != ${Sms.MESSAGE_TYPE_DRAFT}"
        c.contentResolver.query(Sms.CONTENT_URI, cols, if (where == null) real else "$real AND $where", args, "${Sms.DATE} DESC")?.use { q ->
            while (q.moveToNext()) if (!each(Row(q))) break
        }
    }

    private fun threads(req: Long, limit: Int, before: Long?): Message {
        // the newest text of every conversation; `before` is the date of the last conversation the computer has
        val first = LinkedHashMap<Long, Row>()
        val unread = HashMap<Long, Int>()
        var seen = 0
        rows(null, emptyArray()) { r ->
            if (r.thread !in first) first[r.thread] = r
            if (r.unread) unread.merge(r.thread, 1, Int::plus)
            ++seen < 8000
        }
        val all = first.values.filter { before == null || it.date < before }
        val list = all.take(limit)
        return JsonObject(message("sms_threads", "req" to req, "more" to (all.size > list.size)) + ("threads" to JsonArray(list.map { thread(it.thread, it.address, it.body, it.date, unread[it.thread] ?: 0) })))
    }

    private fun texts(req: Long, id: Long, limit: Int, before: Long?): Message {
        val list = ArrayList<Row>()
        var more = false
        var size = 0
        val where = "${Sms.THREAD_ID} = ?" + if (before != null) " AND ${Sms.DATE} < ?" else ""
        rows(where, listOfNotNull(id.toString(), before?.toString()).toTypedArray()) { r ->
            size += r.body.length * 3 + 100 // what it takes in JSON, roughly
            if (list.size == limit || size > 150_000) { more = true; false } else list.add(r)
        }
        return JsonObject(message("sms_messages", "req" to req, "thread" to id, "more" to more) + ("messages" to buildJsonArray {
            list.asReversed().forEach { add(text(it.id, it.type != Sms.MESSAGE_TYPE_INBOX, it.body, it.date, it.type == Sms.MESSAGE_TYPE_FAILED)) }
        }))
    }

    private fun text(id: Long, out: Boolean, body: String, date: Long, failed: Boolean) = buildJsonObject {
        put("id", id); put("out", out); put("text", body.take(8000)); put("date", date)
        if (failed) put("failed", true)
    }

    /** returns when the network took every part; an exception says it did not */
    private fun send(to: String, body: String) {
        if (!SmsRate.isNumber(to)) throw PairlumeException(t("Texts go to phone numbers only"))
        if (body.isBlank() || body.length > 2000) throw PairlumeException(t("A text has 1 to 2000 characters"))
        val sms = if (android.os.Build.VERSION.SDK_INT >= 31) c.getSystemService(SmsManager::class.java) else @Suppress("DEPRECATION") SmsManager.getDefault()
        val parts = sms.divideMessage(body)
        val left = CountDownLatch(parts.size)
        val bad = AtomicInteger(0)
        val action = "dev.pairlume.SENT.${System.nanoTime()}"
        val done = object : BroadcastReceiver() {
            override fun onReceive(x: Context, i: Intent) {
                if (resultCode != android.app.Activity.RESULT_OK) bad.incrementAndGet()
                left.countDown()
            }
        }
        ContextCompat.registerReceiver(c, done, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED)
        try {
            val hear = parts.indices.map { PendingIntent.getBroadcast(c, it, Intent(action).setPackage(c.packageName), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT) }
            sms.sendMultipartTextMessage(to, null, parts, ArrayList(hear), null)
            // longer than that: the phone goes on by itself, the computer is told it is not known
            if (!left.await(17, TimeUnit.SECONDS)) throw PairlumeException(t("The phone did not answer in time"))
            if (bad.get() > 0) throw PairlumeException(t("The network did not take the text"))
        } finally {
            c.unregisterReceiver(done)
        }
    }

    /** a text that has just come */
    fun came(address: String, body: String): Message? {
        if (!Choices(c).read) return null
        var id = 0L
        rows("${Sms.ADDRESS} = ?", arrayOf(address)) { id = it.thread; false }
        if (id == 0L) id = android.provider.Telephony.Threads.getOrCreateThreadId(c, address)
        val now = System.currentTimeMillis()
        return JsonObject(message("sms_new") + ("thread" to thread(id, address, body, now, 1)) + ("message" to text(now, false, body, now, false)))
    }
}

/** only Android itself can send this (BROADCAST_SMS) */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (i.action != Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Sms.Intents.getMessagesFromIntent(i) ?: return
        val from = parts.firstOrNull()?.displayOriginatingAddress ?: return
        LinkService.textCame(from, parts.joinToString("") { it.displayMessageBody ?: "" })
    }
}
