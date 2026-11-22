// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.core

import kotlinx.serialization.json.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SocketChannel
import java.nio.file.Files
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit.SECONDS

/** the Kotlin phone against the real Rust pairlumed */
class InteropTest {
    private val bin = File(System.getProperty("user.dir")).resolve("../../target/debug/pairlumed").canonicalFile
    private val dir: File = Files.createTempDirectory("pairlume").toFile()
    private val sock = dir.resolve("s")
    private val port = ServerSocket(0).use { it.localPort }
    private val to = InetSocketAddress("127.0.0.1", port)
    private lateinit var pc: Process

    @Before
    fun start() {
        assumeTrue("no $bin: cargo build", bin.exists())
        pc = ProcessBuilder(bin.path, "--port", "$port", "--listen", "127.0.0.1", "--no-mdns", "--name", "Desk").apply {
            environment()["PAIRLUME_DIR"] = dir.resolve("pc").path
            environment()["PAIRLUME_SOCKET"] = sock.path
            redirectErrorStream(true)
            redirectOutput(dir.resolve("log"))
        }.start()
        repeat(50) { if (!sock.exists()) Thread.sleep(100) }
    }

    @After
    fun stop() {
        if (::pc.isInitialized) pc.destroy().also { pc.waitFor(3, SECONDS) }
        dir.deleteRecursively()
    }

    private inner class Control : AutoCloseable {
        private val c = SocketChannel.open(StandardProtocolFamily.UNIX).apply { connect(UnixDomainSocketAddress.of(sock.path)) }
        private val buf = StringBuilder()
        fun send(json: String) { c.write(ByteBuffer.wrap((json + "\n").toByteArray())) }
        fun line(): JsonObject {
            while ('\n' !in buf) {
                val b = ByteBuffer.allocate(4096)
                if (c.read(b) < 0) error("pairlumed closed")
                buf.append(String(b.array(), 0, b.position()))
            }
            val l = buf.substring(0, buf.indexOf("\n"))
            buf.delete(0, l.length + 1)
            return Json.parseToJsonElement(l).jsonObject
        }
        fun ask(json: String): JsonObject { send(json); return line() }
        fun event(name: String): JsonObject { while (true) line().let { if (it["event"]?.jsonPrimitive?.content == name) return it } }
        override fun close() = c.close()
    }

    private fun newPhone(): Identity {
        val f = dir.resolve("phone-${System.nanoTime()}.p12")
        val r = ProcessBuilder(
            System.getProperty("java.home") + "/bin/keytool", "-genkeypair", "-alias", "p", "-keyalg", "EC", "-groupname", "secp256r1",
            "-dname", "CN=pairlume", "-validity", "3650", "-keystore", f.path, "-storetype", "PKCS12", "-storepass", "secret",
        ).redirectErrorStream(true).start()
        val out = r.inputStream.bufferedReader().readText()
        assertEquals(out, 0, r.waitFor())
        val ks = KeyStore.getInstance("PKCS12").apply { f.inputStream().use { load(it, "secret".toCharArray()) } }
        return Identity(ks.getKey("p", "secret".toCharArray()) as PrivateKey, ks.getCertificate("p") as X509Certificate)
    }

    private fun Control.open(): JsonObject = ask("""{"cmd":"pair"}""")["pairing"]!!.jsonObject
    private fun fails(f: () -> Unit) = assertThrows(Exception::class.java) { f() }

    @Test
    fun shakeThenReconnectThenBattery() {
        val id = newPhone()
        Control().use { ctl ->
            Control().use { ev ->
                ev.ask("""{"cmd":"watch"}""")
                ctl.open()
                val here = CompletableFuture<String>()
                val done = CompletableFuture.runAsync {
                    Link.open(id, "Kotlin phone", to, null).use { l -> l.patience = Link.HUMAN; l.pairing().shake { here.complete(it) } }
                }
                val e = ev.event("pairing_code")
                assertEquals("Kotlin phone", e["name"]!!.jsonPrimitive.content)
                assertEquals(here.get(5, SECONDS), e["code"]!!.jsonPrimitive.content)
                assertTrue(ctl.ask("""{"cmd":"answer","yes":true}""")["ok"]!!.jsonPrimitive.boolean)
                done.get(5, SECONDS)
                val pcId = Fingerprint.parse(ev.event("paired")["id"]!!.jsonPrimitive.content).also { assertEquals(id.fingerprint, it) }
                assertEquals(id.fingerprint, pcId)
            }
            val computer = Link.open(id, "Kotlin phone", to, null).use { it.computer }
            Link.open(id, "Kotlin phone", to, computer).use { l ->
                assertEquals("Desk", l.name)
                assertEquals(emptySet<String>(), l.wire.expect("allowed").texts("caps"))
                val battery = message("battery", "percent" to 42, "charging" to true)
                l.wire.send(battery)
                assertEquals("battery", l.wire.expect("denied").text("cap"))
                ctl.ask("""{"cmd":"allow","device":"Kotlin phone","cap":"battery","on":true}""")
                assertEquals(setOf("battery"), l.wire.expect("allowed").texts("caps"))
                l.wire.send(battery)
                l.wire.send(message("ping"))
                l.wire.expect("pong")
                val d = ctl.ask("""{"cmd":"status"}""")["devices"]!!.jsonArray.single().jsonObject
                assertEquals("[42,true]", d["battery"].toString())
            }
            fails { Link.open(id, "Kotlin phone", to, Fingerprint(ByteArray(32))) }
        }
    }

    @Test
    fun digitsRightAndWrong() {
        Control().use { ctl ->
            val digits = ctl.open()["digits"]!!.jsonPrimitive.content
            Link.open(newPhone(), "A", to, null).use { it.pairing().digits(digits) }
            val again = ctl.open()["digits"]!!.jsonPrimitive.content
            val wrong = "%06d".format((again.toInt() + 1) % 1_000_000)
            fails { Link.open(newPhone(), "B", to, null).use { it.pairing().digits(wrong) } }
            fails { Link.open(newPhone(), "C", to, null).use { it.pairing().digits(again) } }
            assertEquals(1, ctl.ask("""{"cmd":"status"}""")["devices"]!!.jsonArray.size)
        }
    }

    @Test
    fun qrRightAndWrong() {
        Control().use { ctl ->
            val qr = QrCode.parse(ctl.open()["qr"]!!.jsonPrimitive.content)
            Link.open(newPhone(), "A", qr.address, qr.fingerprint).use { it.pairing().qr(qr.secret) }
            ctl.open()
            fails { Link.open(newPhone(), "B", qr.address, qr.fingerprint).use { it.pairing().qr(qr.secret) } }
            assertEquals(1, ctl.ask("""{"cmd":"status"}""")["devices"]!!.jsonArray.size)
        }
    }

    @Test
    fun refusedHereAndNotPairing() {
        Control().use { ctl ->
            ctl.open()
            fails { Link.open(newPhone(), "A", to, null).use { l -> l.pairing().shake { false } } }
            fails { Link.open(newPhone(), "B", to, null).use { l -> l.pairing().digits("000000") } }
            assertEquals(0, ctl.ask("""{"cmd":"status"}""")["devices"]!!.jsonArray.size)
        }
    }
}

class PiecesTest {
    @Test
    fun hexAndNames() {
        assertArrayEquals(byteArrayOf(0, 1, -2, -1), unhex("0001feff"))
        assertEquals("0001feff", hex(byteArrayOf(0, 1, -2, -1)))
        listOf("abc", "zz", "+1").forEach { assertThrows(PairlumeException::class.java) { unhex(it) } }
        assertEquals("My phone", cleanName("My\u001b\n‮ phone"))
        assertEquals("Unnamed device", cleanName(" \t"))
    }

    @Test
    fun addresses() {
        assertEquals(47321, parseAddress("192.168.1.2:47321").port)
        assertEquals(5, parseAddress("[fe80::1]:5").port)
        listOf("example.org:1", "1.2.3:1", "1.2.3.400:1", "1.2.3.4", "1.2.3.4:0", ":1", "dead.beef:1", "abc:1").forEach {
            assertThrows(it, PairlumeException::class.java) { parseAddress(it) }
        }
    }

    @Test
    fun codes() {
        listOf("https://example.org", "pairlume://pair?v=2", "pairlume://pair?v=1&a=1.2.3.4:5&f=00&s=00").forEach {
            assertThrows(it, PairlumeException::class.java) { QrCode.parse(it) }
        }
        assertTrue(Pairing.isDigits("012345"))
        listOf("12345", "1234567", "12345x", "١٢٣٤٥٦").forEach { assertFalse(Pairing.isDigits(it)) }
    }
}
