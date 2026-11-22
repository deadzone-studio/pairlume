// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.core

/** A program on the computer that went wrong must not be able to send hundreds of texts. */
class SmsRate(private val perMinute: Int = 8, private val perDay: Int = 150, private val now: () -> Long = System::currentTimeMillis) {
    private val sent = ArrayDeque<Long>()

    @Synchronized
    fun take(): Boolean {
        val t = now()
        while (sent.isNotEmpty() && t - sent.first() > 86_400_000) sent.removeFirst()
        if (sent.size >= perDay || sent.count { t - it < 60_000 } >= perMinute) return false
        sent.addLast(t)
        return true
    }

    companion object {
        /** a phone number. Short ones (often paid services) and codes like *100# are not sent to */
        fun isNumber(s: String): Boolean = s.all { it in "0123456789+ -()" } && s.lastIndexOf('+') <= 0 && s.count { it in '0'..'9' } in 7..15
    }
}
