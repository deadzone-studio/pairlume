// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import dev.pairlume.core.Link
import dev.pairlume.core.Message
import dev.pairlume.core.message
import dev.pairlume.core.texts
import dev.pairlume.core.type
import java.net.InetSocketAddress
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

/** what the screen shows of the connection; set on the main thread */
object LinkState {
    var connected by mutableStateOf(false)
    var allowed by mutableStateOf(emptySet<String>())
}

/** keeps the connection to the paired computer */
class LinkService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val wake = Semaphore(0)
    @Volatile private var running = true
    @Volatile private var link: Link? = null
    @Volatile private var battery: Message? = null
    @Volatile private var seenAt: InetSocketAddress? = null
    private lateinit var discovery: Discovery

    private val power = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level < 0 || scale <= 0) return
            val m = message("battery", "percent" to level * 100 / scale, "charging" to (i.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0))
            if (m != battery) { battery = m; wake.release() }
        }
    }
    private val network = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(n: Network) { wake.release() }
        override fun onLost(n: Network) { link?.close() }
    }

    override fun onBind(i: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("link", getString(R.string.link_channel), NotificationManager.IMPORTANCE_LOW))
        startForeground(1, note(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        registerReceiver(power, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(network)
        discovery = Discovery(this) { list ->
            val c = Saved(this).computer ?: return@Discovery
            list.firstOrNull { it.id == c.id.short }?.let { if (it.address != seenAt) { seenAt = it.address; wake.release() } }
        }
        Thread(::work, "pairlume-link").start()
    }

    override fun onStartCommand(i: Intent?, flags: Int, id: Int): Int {
        if (Saved(this).computer == null) { stopSelf(); return START_NOT_STICKY }
        wake.release()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        wake.release()
        link?.let { l -> Thread { l.close() }.start() }
        discovery.stop()
        unregisterReceiver(power)
        getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(network)
        LinkState.connected = false
        LinkState.allowed = emptySet()
        super.onDestroy()
    }

    private fun note(): Notification {
        val c = Saved(this).computer?.name ?: ""
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "link")
            .setSmallIcon(R.drawable.ic_note)
            .setContentTitle(getString(if (LinkState.connected) R.string.link_connected else R.string.link_looking, c))
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    private fun show(connected: Boolean) = main.post {
        if (!running) return@post
        LinkState.connected = connected
        if (!connected) LinkState.allowed = emptySet()
        if (connected) discovery.stop() else discovery.start()
        getSystemService(NotificationManager::class.java).notify(1, note())
    }

    private fun work() {
        var pause = 2L
        while (running) {
            val c = Saved(this).computer ?: break
            show(false)
            // where it was seen now, then where it was the last time
            for (a in listOfNotNull(seenAt, c.address).distinct()) {
                if (!running) return
                try {
                    Link.open(Phone.identity(), Phone.name(this), a, c.id).use { l ->
                        link = l
                        if (!running) return
                        if (l.name != c.name || a != c.address) Saved(this).run { if (computer?.id == c.id) computer = Computer(c.id, l.name, a) }
                        pause = 2
                        talk(l)
                    }
                } catch (_: Exception) {
                    // tried again below
                } finally {
                    link = null
                }
            }
            show(false)
            wake.drainPermits()
            wake.tryAcquire(pause, TimeUnit.SECONDS)
            pause = (pause * 2).coerceAtMost(60)
        }
        main.post { stopSelf() }
    }

    /** until the connection ends */
    private fun talk(l: Link) {
        l.patience = 40_000
        // the computer turns a phone it does not know away right after the handshake: it counts once it speaks
        var m = l.wire.receive()
        show(true)
        val writer = Thread({
            try {
                var sent: Message? = null
                while (running && link === l) {
                    l.wire.send(message("ping"))
                    val b = battery
                    if (b != null && b != sent) { l.wire.send(b); sent = b }
                    wake.drainPermits()
                    wake.tryAcquire(12, TimeUnit.SECONDS)
                }
            } catch (_: Exception) {
                l.close()
            }
        }, "pairlume-write").apply { start() }
        try {
            while (running) {
                when (m.type) {
                    "allowed" -> {
                        val caps = m.texts("caps")
                        main.post { if (running) LinkState.allowed = caps }
                        // a battery that was refused before is told again
                        battery?.let { if ("battery" in caps) l.wire.send(it) }
                    }
                }
                m = l.wire.receive()
            }
        } finally {
            l.close()
            writer.interrupt()
        }
    }

    companion object {
        fun start(c: Context) { if (Saved(c).computer != null) c.startForegroundService(Intent(c, LinkService::class.java)) }
        fun stop(c: Context) { c.stopService(Intent(c, LinkService::class.java)) }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED || i.action == Intent.ACTION_MY_PACKAGE_REPLACED) LinkService.start(c)
    }
}
