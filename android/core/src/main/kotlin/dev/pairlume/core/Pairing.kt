// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.core

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.net.InetSocketAddress
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** The phone's half of docs/protocol.md */
class Pairing(private val wire: Wire, private val computer: Fingerprint, private val phone: Fingerprint) {
    private val random = SecureRandom()

    private fun mix(label: String, rest: Array<out ByteArray>) = ByteArrayOutputStream().apply {
        write("pairlume 1 $label\u0000".toByteArray())
        write(computer.bytes)
        write(phone.bytes)
        rest.forEach { write(it) }
    }.toByteArray()

    private fun mac(key: ByteArray, label: String, vararg rest: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key, "HmacSHA256")); doFinal(mix(label, rest)) }

    private fun check(got: String, key: ByteArray, label: String, vararg rest: ByteArray) {
        if (!MessageDigest.isEqual(unhex(got), mac(key, label, *rest))) throw PairlumeException("the codes do not match")
    }

    private fun nonce() = ByteArray(32).also(random::nextBytes)
    private fun theirNonce() = unhex(wire.expect("nonce").text("nonce")).also { if (it.size != 32) throw PairlumeException("a random number of the wrong size") }

    internal fun code(nc: ByteArray, np: ByteArray): String {
        val d = MessageDigest.getInstance("SHA-256").digest(mix("code", arrayOf(nc, np)))
        return "%06d".format(BigInteger(1, d.copyOf(8)).mod(BigInteger.valueOf(1_000_000)).toInt())
    }

    /** @param ask shows the code and says whether the computer shows the same */
    fun shake(ask: (String) -> Boolean) {
        wire.send(message("pair_start", "mode" to "shake"))
        val np = nonce()
        wire.send(message("commit", "mac" to hex(mac(np, "shake"))))
        val nc = theirNonce()
        wire.send(message("nonce", "nonce" to hex(np)))
        val ok = ask(code(nc, np))
        wire.send(message("confirm", "ok" to ok))
        if (!ok) throw PairlumeException("not confirmed here")
        if (!wire.expect("confirm").flag("ok")) throw PairlumeException("not confirmed on the computer")
    }

    fun qr(secret: ByteArray) {
        wire.send(message("pair_start", "mode" to "qr"))
        wire.send(message("proof", "mac" to hex(mac(secret, "qr phone"))))
        check(wire.expect("proof").text("mac"), secret, "qr computer")
    }

    fun digits(digits: String) {
        if (!isDigits(digits)) throw PairlumeException("the code has six digits")
        val n = digits.toInt()
        wire.send(message("pair_start", "mode" to "digits"))
        for (i in 0 until 20) {
            val part = byteArrayOf(i.toByte(), (n shr i and 1).toByte())
            val np = nonce()
            val theirs = wire.expect("commit").text("mac")
            wire.send(message("commit", "mac" to hex(mac(np, "digit phone", part))))
            check(theirs, theirNonce(), "digit computer", part)
            wire.send(message("nonce", "nonce" to hex(np)))
        }
        if (!wire.expect("confirm").flag("ok")) throw PairlumeException("not confirmed on the computer")
    }

    companion object {
        fun isDigits(s: String) = s.length == 6 && s.all { it in '0'..'9' }
    }
}

/** what the QR code on the computer holds */
class QrCode(val address: InetSocketAddress, val fingerprint: Fingerprint, val secret: ByteArray) {
    companion object {
        fun parse(s: String): QrCode {
            val q = s.removePrefix("pairlume://pair?").also { if (it == s) throw PairlumeException("not a Pairlume code") }
            val f = q.split('&').associate { it.substringBefore('=') to it.substringAfter('=', "") }
            fun field(k: String) = f[k] ?: throw PairlumeException("the code has no $k")
            if (field("v") != "1") throw PairlumeException("the code is from another version of Pairlume")
            val secret = unhex(field("s")).also { if (it.size != 16) throw PairlumeException("the code is damaged") }
            return QrCode(parseAddress(field("a")), Fingerprint.parse(field("f")), secret)
        }
    }
}

/** an IP address and a port; never a name, so nothing is looked up */
fun parseAddress(s: String): InetSocketAddress {
    val host = s.substringBeforeLast(':', "").removeSurrounding("[", "]")
    val port = s.substringAfterLast(':').toIntOrNull()?.takeIf { it in 1..65535 } ?: throw PairlumeException("bad address")
    if (host.isEmpty() || !host.all { it in "0123456789abcdefABCDEF.:" }) throw PairlumeException("bad address")
    val v4 = host.split('.').let { p -> p.size == 4 && p.all { x -> x.isNotEmpty() && x.length <= 3 && x.all(Char::isDigit) && x.toInt() <= 255 } }
    if (!v4 && ':' !in host) throw PairlumeException("bad address")
    return InetSocketAddress(java.net.InetAddress.getByName(host), port)
}
