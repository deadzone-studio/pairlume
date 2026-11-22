// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import dev.pairlume.core.cleanName
import java.net.Inet4Address
import java.net.InetSocketAddress

/** what a computer says about itself on the network: hints, nothing to trust */
data class Found(val service: String, val id: String, val name: String, val pairing: Boolean, val address: InetSocketAddress)

/** computers with Pairlume on this network. Everything happens on the main thread. */
class Discovery(c: Context, private val onChange: (List<Found>) -> Unit) {
    private val nsd = c.getSystemService(NsdManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val seen = LinkedHashMap<String, NsdServiceInfo>()
    private val found = LinkedHashMap<String, Found>()
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var listener: NsdManager.DiscoveryListener? = null

    // whether a computer is pairing changes without a word from NsdManager: asked again now and then
    private val again = object : Runnable {
        override fun run() {
            if (listener == null) return
            if (queue.isEmpty()) queue.addAll(seen.values)
            next()
            main.postDelayed(this, 2000)
        }
    }

    fun start() {
        if (listener != null) return
        val l = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(s: NsdServiceInfo) = on { seen[s.serviceName] = s; queue.add(s); next() }
            override fun onServiceLost(s: NsdServiceInfo) = on { seen.remove(s.serviceName); found.remove(s.serviceName); tell() }
            override fun onDiscoveryStarted(t: String) {}
            override fun onDiscoveryStopped(t: String) {}
            override fun onStartDiscoveryFailed(t: String, e: Int) = on { listener = null }
            override fun onStopDiscoveryFailed(t: String, e: Int) {}
            private fun on(f: () -> Unit) { main.post { if (listener === this) f() } }
        }
        listener = l
        nsd.discoverServices("_pairlume._tcp", NsdManager.PROTOCOL_DNS_SD, l)
        main.postDelayed(again, 2000)
    }

    fun stop() {
        val l = listener ?: return
        listener = null
        main.removeCallbacks(again)
        try { nsd.stopServiceDiscovery(l) } catch (_: IllegalArgumentException) { }
        seen.clear(); found.clear(); queue.clear()
        resolving = false
    }

    private fun tell() = onChange(found.values.toList())

    @Suppress("DEPRECATION") // the new call needs Android 14
    private fun next() {
        if (resolving || listener == null) return
        val s = queue.removeFirstOrNull() ?: return
        val mine = listener
        resolving = true
        fun done(f: () -> Unit) = main.post { if (listener === mine) { resolving = false; f(); next() } }
        try {
            nsd.resolveService(s, object : NsdManager.ResolveListener {
                override fun onResolveFailed(i: NsdServiceInfo, e: Int) { done { } }
                override fun onServiceResolved(i: NsdServiceInfo) {
                    done {
                        val host = i.host as? Inet4Address ?: return@done
                        fun txt(k: String) = i.attributes[k]?.decodeToString() ?: ""
                        if (txt("v") == "1") {
                            found[i.serviceName] = Found(i.serviceName, txt("id").take(8), cleanName(txt("name")), txt("pairing") == "1", InetSocketAddress(host, i.port))
                            tell()
                        }
                    }
                }
            })
        } catch (_: IllegalArgumentException) {
            resolving = false
        }
    }
}
