// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import dev.pairlume.core.Message
import dev.pairlume.core.PairlumeException
import dev.pairlume.core.longNumber
import dev.pairlume.core.message
import dev.pairlume.core.text
import dev.pairlume.core.type
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject

/** what the owner switched on here for calls; the computer has its own permission */
class CallChoices(c: Context) {
    private val app = c.applicationContext
    private val p = app.getSharedPreferences("choices", Context.MODE_PRIVATE)
    var show: Boolean
        get() = p.getBoolean("calls_show", false) && granted(*SHOW)
        set(v) = p.edit().putBoolean("calls_show", v).apply()
    var act: Boolean
        get() = p.getBoolean("calls_act", false) && granted(*ACT)
        set(v) = p.edit().putBoolean("calls_act", v).apply()
    private fun granted(vararg n: String) = n.all { app.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    companion object {
        // the number of who calls needs the call log permission
        val SHOW = arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_CALL_LOG)
        val ACT = arrayOf(Manifest.permission.ANSWER_PHONE_CALLS, Manifest.permission.CALL_PHONE)

        /** what the computer may dial: 3 to 15 digits, no codes */
        fun dialable(n: String): Boolean {
            val t = n.trim()
            val digits = t.count(Char::isDigit)
            return digits in 3..15 && t.all { it.isDigit() || it in " +-()" } && t.lastIndexOf('+') <= 0
        }
    }
}

/**
 * Follows the phone's call and tells the computer. Android says only ringing, off the hook, and idle, so a call this
 * phone makes is "talking" from the start.
 */
class Calls(private val c: Context, private val texts: Texts, private val tell: (Message) -> Unit) {
    private var state = TelephonyManager.EXTRA_STATE_IDLE
    private var number = ""
    private var rang = false
    private var answered = false
    private var dialed = ""

    val hear = object : BroadcastReceiver() {
        override fun onReceive(x: Context, i: Intent) {
            if (i.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
            @Suppress("DEPRECATION") val n = i.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
            changed(i.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return, n)
        }
    }

    @Synchronized
    private fun changed(s: String, n: String) {
        // Android says it twice, once without the number
        if (s == state && (n.isEmpty() || n == number)) return
        val first = s != state
        state = s
        if (n.isNotEmpty()) number = n
        if (!CallChoices(c).show) return
        when (s) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                if (first) { rang = true; answered = false }
                tell(call("ringing", picture = true))
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                if (!first) return
                if (rang) answered = true else if (number.isEmpty()) number = dialed
                tell(call("talking"))
            }
            else -> {
                tell(call("ended", missed = rang && !answered))
                number = ""; dialed = ""; rang = false; answered = false
            }
        }
    }

    private fun call(state: String, missed: Boolean = false, picture: Boolean = false): Message {
        val m = message("call", "state" to state, "number" to number, "name" to (if (number.isEmpty()) "" else texts.nameOf(number)), "missed" to missed)
        val png = if (picture && number.isNotEmpty()) texts.photoOf(number) else null
        return if (png == null) m else JsonObject(m + ("png" to JsonPrimitive(png)))
    }

    /** the answer to call_do */
    @SuppressLint("MissingPermission")
    fun answer(m: Message): Message {
        val req = m.longNumber("req")
        fun no(why: String) = message("call_error", "req" to req, "reason" to why)
        if (!CallChoices(c).act) return no("Answering and making calls is off in Pairlume on the phone")
        val t = c.getSystemService(TelecomManager::class.java) ?: return no("This phone has no calls")
        return try {
            when (m.text("what")) {
                "answer" -> {
                    if (state != TelephonyManager.EXTRA_STATE_RINGING) return no("Nothing rings")
                    @Suppress("DEPRECATION") t.acceptRingingCall()
                }
                "end" -> {
                    if (state == TelephonyManager.EXTRA_STATE_IDLE) return no("There is no call")
                    @Suppress("DEPRECATION") if (!t.endCall()) return no("Android did not end the call")
                }
                "dial" -> {
                    val n = m.text("number")
                    if (!CallChoices.dialable(n)) return no("That is not a phone number")
                    if (state != TelephonyManager.EXTRA_STATE_IDLE) return no("There is a call already")
                    synchronized(this) { dialed = n }
                    t.placeCall(Uri.fromParts("tel", n, null), Bundle())
                }
                else -> return no("The phone does not know that")
            }
            message("call_done", "req" to req)
        } catch (e: PairlumeException) {
            no(e.message ?: "")
        } catch (_: SecurityException) {
            no("Android does not let Pairlume do that")
        } catch (_: Exception) {
            no("The phone could not do that")
        }
    }
}
