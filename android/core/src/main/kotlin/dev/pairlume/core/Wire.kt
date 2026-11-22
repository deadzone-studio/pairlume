// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.core

import kotlinx.serialization.json.*
import java.io.DataInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

const val PROTOCOL = 1
const val MAX_FRAME = 256 * 1024

/** something the other side said or did that ends the conversation */
class PairlumeException(message: String) : IOException(message)

fun hex(b: ByteArray): String = buildString(b.size * 2) { b.forEach { append("%02x".format(it.toInt() and 0xff)) } }

fun unhex(s: String): ByteArray {
    if (s.length % 2 != 0) throw PairlumeException("odd number of hex digits")
    fun digit(c: Char) = when (c) {
        in '0'..'9' -> c - '0'
        in 'a'..'f' -> c - 'a' + 10
        in 'A'..'F' -> c - 'A' + 10
        else -> throw PairlumeException("not a hex digit")
    }
    return ByteArray(s.length / 2) { (digit(s[it * 2]) * 16 + digit(s[it * 2 + 1])).toByte() }
}

/** SHA-256 of a certificate: what pairing remembers */
class Fingerprint(val bytes: ByteArray) {
    init { require(bytes.size == 32) { "a fingerprint is 32 bytes" } }
    override fun equals(other: Any?) = other is Fingerprint && MessageDigest.isEqual(bytes, other.bytes)
    override fun hashCode() = bytes.contentHashCode()
    override fun toString() = hex(bytes)
    val short get() = toString().take(8)

    companion object {
        fun of(der: ByteArray) = Fingerprint(MessageDigest.getInstance("SHA-256").digest(der))
        fun parse(s: String): Fingerprint = unhex(s).let { if (it.size == 32) Fingerprint(it) else throw PairlumeException("not a fingerprint") }
    }
}

typealias Message = JsonObject

fun message(type: String, vararg fields: Pair<String, Any>): Message = buildJsonObject {
    put("t", type)
    fields.forEach { (k, v) ->
        when (v) {
            is Boolean -> put(k, v)
            is Number -> put(k, v)
            else -> put(k, v.toString())
        }
    }
}

val Message.type: String get() = text("t")
fun Message.text(k: String): String = (get(k) as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw PairlumeException("a message without $k")
fun Message.flag(k: String): Boolean = (get(k) as? JsonPrimitive)?.booleanOrNull ?: throw PairlumeException("a message without $k")
fun Message.number(k: String): Int = (get(k) as? JsonPrimitive)?.intOrNull ?: throw PairlumeException("a message without $k")
fun Message.texts(k: String): Set<String> = (get(k) as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }?.toSet() ?: emptySet()

/** 4 bytes length (big endian), then JSON */
class Wire(input: InputStream, private val output: OutputStream) {
    private val input = DataInputStream(input)

    @Synchronized
    fun send(m: Message) {
        val b = m.toString().toByteArray()
        if (b.size > MAX_FRAME) throw PairlumeException("message too large")
        val out = ByteArray(b.size + 4)
        for (i in 0..3) out[i] = (b.size ushr (24 - 8 * i)).toByte()
        b.copyInto(out, 4)
        output.write(out)
        output.flush()
    }

    fun receive(): Message {
        val n = input.readInt()
        if (n < 1 || n > MAX_FRAME) throw PairlumeException("bad message length")
        val b = ByteArray(n)
        input.readFully(b)
        return try {
            Json.parseToJsonElement(b.decodeToString()).jsonObject
        } catch (_: IllegalArgumentException) {
            throw PairlumeException("not a message")
        }
    }

    /** one step of a conversation */
    fun expect(type: String): Message {
        val m = receive()
        if (m.type == "fail") throw PairlumeException("the computer stopped: ${cleanName(m.text("reason"))}")
        if (m.type != type) throw PairlumeException("expected $type, got ${m.type}")
        return m
    }
}

/** one short line, nothing that plays with the screen */
fun cleanName(s: String): String {
    val n = s.filterNot { it.isISOControl() || it in '​'..'‏' || it in '‪'..'‮' || it in '⁠'..'⁯' || it == '﻿' }.take(48).trim()
    return n.ifEmpty { "Unnamed device" }
}
