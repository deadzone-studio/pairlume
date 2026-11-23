// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/** the computer as this phone's hands-free set, over Bluetooth: then the voice of a call is there */
object Voice {
    fun permitted(c: Context) = Build.VERSION.SDK_INT < 31 || c.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun device(c: Context, address: String): BluetoothDevice? =
        try { c.getSystemService(BluetoothManager::class.java)?.adapter?.takeIf { it.isEnabled }?.getRemoteDevice(address) } catch (_: Exception) { null }

    fun on(c: Context) = c.getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled == true

    @SuppressLint("MissingPermission")
    fun paired(c: Context, address: String) = permitted(c) && device(c, address)?.bondState == BluetoothDevice.BOND_BONDED

    /** the computer opens its pairing, a moment later the phone asks; Android shows its own question with the code */
    @SuppressLint("MissingPermission")
    fun pair(c: Context, address: String): Boolean {
        val d = device(c, address) ?: return false
        LinkService.askBluetooth()
        Handler(Looper.getMainLooper()).postDelayed({ try { d.createBond() } catch (_: Exception) { } }, 700)
        return true
    }
}
