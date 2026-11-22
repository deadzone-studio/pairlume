// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.core

import java.io.Closeable
import java.net.InetSocketAddress
import java.net.Socket
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.*

/** this phone: its key (on Android it never leaves the key store) and its certificate */
class Identity(val key: PrivateKey, val certificate: X509Certificate) {
    val fingerprint = Fingerprint.of(certificate.encoded)
}

private class OwnKey(private val id: Identity) : X509ExtendedKeyManager() {
    override fun chooseClientAlias(t: Array<out String>?, i: Array<out Principal>?, s: Socket?) = "pairlume"
    override fun chooseEngineClientAlias(t: Array<out String>?, i: Array<out Principal>?, e: SSLEngine?) = "pairlume"
    override fun getClientAliases(t: String?, i: Array<out Principal>?) = arrayOf("pairlume")
    override fun getServerAliases(t: String?, i: Array<out Principal>?): Array<String>? = null
    override fun chooseServerAlias(t: String?, i: Array<out Principal>?, s: Socket?): String? = null
    override fun getCertificateChain(a: String?) = arrayOf(id.certificate)
    override fun getPrivateKey(a: String?) = id.key
}

/**
 * The computer's certificate is its own: it is the fingerprint that counts. Without one (while pairing) everyone gets
 * this far, and the pairing decides. That the computer has the certificate's key is checked by TLS itself.
 */
private class Pinned(private val expect: Fingerprint?) : X509ExtendedTrustManager() {
    private fun check(chain: Array<out X509Certificate>?) {
        val c = chain?.firstOrNull() ?: throw CertificateException("no certificate")
        if (expect != null && Fingerprint.of(c.encoded) != expect) throw CertificateException("another computer")
    }
    override fun checkServerTrusted(c: Array<out X509Certificate>?, a: String?) = check(c)
    override fun checkServerTrusted(c: Array<out X509Certificate>?, a: String?, s: Socket?) = check(c)
    override fun checkServerTrusted(c: Array<out X509Certificate>?, a: String?, e: SSLEngine?) = check(c)
    private fun never(): Nothing = throw CertificateException("a phone is not a server")
    override fun checkClientTrusted(c: Array<out X509Certificate>?, a: String?) = never()
    override fun checkClientTrusted(c: Array<out X509Certificate>?, a: String?, s: Socket?) = never()
    override fun checkClientTrusted(c: Array<out X509Certificate>?, a: String?, e: SSLEngine?) = never()
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

/** a connection to a computer */
class Link private constructor(private val socket: SSLSocket, val wire: Wire, val computer: Fingerprint, val name: String, private val id: Identity) : Closeable {
    fun pairing() = Pairing(wire, computer, id.fingerprint)

    /** how long to wait for the other side, in ms */
    var patience: Int
        get() = socket.soTimeout
        set(v) { socket.soTimeout = v }

    /** also ends a read that another thread is waiting in */
    override fun close() = try { socket.close() } catch (_: Exception) { }

    companion object {
        const val STEP = 15_000
        /** pairing: the person at the computer has to look first */
        const val HUMAN = 110_000

        /** @param expect only this computer (null only while pairing) */
        fun open(id: Identity, name: String, to: InetSocketAddress, expect: Fingerprint?): Link {
            val ctx = SSLContext.getInstance("TLSv1.3")
            ctx.init(arrayOf(OwnKey(id)), arrayOf(Pinned(expect)), null)
            val tcp = Socket()
            try {
                tcp.connect(to, STEP)
                tcp.tcpNoDelay = true
                tcp.soTimeout = STEP
                val s = ctx.socketFactory.createSocket(tcp, to.address.hostAddress, to.port, true) as SSLSocket
                s.enabledProtocols = arrayOf("TLSv1.3")
                s.sslParameters = s.sslParameters.apply { applicationProtocols = arrayOf("pairlume/1") }
                s.startHandshake()
                val peer = Fingerprint.of(s.session.peerCertificates.first().encoded)
                val wire = Wire(s.inputStream, s.outputStream)
                wire.send(message("hello", "v" to PROTOCOL, "name" to name))
                val hello = wire.expect("hello")
                if (hello.number("v") != PROTOCOL) throw PairlumeException("the computer has another version of Pairlume")
                return Link(s, wire, peer, cleanName(hello.text("name")), id)
            } catch (e: Throwable) {
                try { tcp.close() } catch (_: Exception) { }
                throw e
            }
        }
    }
}
