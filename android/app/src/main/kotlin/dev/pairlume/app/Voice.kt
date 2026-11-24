// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/** the computer as this phone's hands-free set, over Bluetooth: then the voice of a call is there */
object Voice {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var headset: BluetoothHeadset? = null

    fun permitted(c: Context) = Build.VERSION.SDK_INT < 31 || c.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun adapter(c: Context) = c.getSystemService(BluetoothManager::class.java)?.adapter

    fun on(c: Context) = adapter(c)?.isEnabled == true

    private fun device(c: Context, address: String): BluetoothDevice? =
        try { adapter(c)?.takeIf { it.isEnabled }?.getRemoteDevice(address) } catch (_: Exception) { null }

    /** the hands-free link, asked for once; until it comes, nothing counts as connected */
    private fun watch(c: Context) {
        if (headset != null || !permitted(c)) return
        adapter(c)?.getProfileProxy(c.applicationContext, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(p: Int, proxy: BluetoothProfile) { headset = proxy as? BluetoothHeadset }
            override fun onServiceDisconnected(p: Int) { headset = null }
        }, BluetoothProfile.HEADSET)
    }

    /** BluetoothDevice.BOND_NONE, BOND_BONDING or BOND_BONDED; NONE when it cannot be read */
    @SuppressLint("MissingPermission")
    fun bondState(c: Context, address: String) =
        if (permitted(c)) device(c, address)?.bondState ?: BluetoothDevice.BOND_NONE else BluetoothDevice.BOND_NONE

    @SuppressLint("MissingPermission")
    fun bonded(c: Context, address: String) = permitted(c) && device(c, address)?.bondState == BluetoothDevice.BOND_BONDED

    /** paired, and the computer is this phone's hands-free set right now */
    @SuppressLint("MissingPermission")
    fun connected(c: Context, address: String): Boolean {
        if (!permitted(c)) return false
        watch(c)
        val d = device(c, address) ?: return false
        return try { headset?.getConnectionState(d) == BluetoothProfile.STATE_CONNECTED } catch (_: Exception) { false }
    }

    /**
     * The computer opens its pairing, a moment later the phone asks; Android shows its own question with the code.
     * A pairing the phone remembers from before (another system on the same computer) is no use: it goes first.
     */
    @SuppressLint("MissingPermission")
    fun pair(c: Context, address: String): Boolean {
        val d = device(c, address) ?: return false
        watch(c)
        LinkService.askBluetooth()
        val start = {
            main.postDelayed({ try { d.createBond() } catch (_: Exception) { } }, 700)
        }
        if (d.bondState != BluetoothDevice.BOND_BONDED) { start(); return true }
        try { d.javaClass.getMethod("removeBond").invoke(d) } catch (_: Exception) { }
        // then pair anew, once the old one is gone
        var tries = 0
        lateinit var wait: Runnable
        wait = Runnable {
            if (d.bondState == BluetoothDevice.BOND_NONE || ++tries > 20) start() else main.postDelayed(wait, 250)
        }
        main.postDelayed(wait, 250)
        return true
    }
}
