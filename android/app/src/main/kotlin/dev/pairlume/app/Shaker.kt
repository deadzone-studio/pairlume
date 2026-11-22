// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.abs
import kotlin.math.sqrt

/** calls back when the phone is shaken: a few hard turns within a second */
class Shaker(c: Context, private val onShake: () -> Unit) : SensorEventListener {
    private val sensors = c.getSystemService(SensorManager::class.java)
    private val sensor: Sensor? = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val hits = ArrayDeque<Long>()
    private var last = 0L
    val available get() = sensor != null

    fun start() { sensor?.let { sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) } }
    fun stop() { sensors.unregisterListener(this); hits.clear() }

    override fun onSensorChanged(e: SensorEvent) {
        val (x, y, z) = e.values
        if (abs(sqrt(x * x + y * y + z * z) - SensorManager.GRAVITY_EARTH) < 11f) return
        val now = e.timestamp / 1_000_000
        if (hits.isNotEmpty() && now - hits.last() < 70) return
        hits.addLast(now)
        while (now - hits.first() > 1000) hits.removeFirst()
        if (hits.size >= 4 && now - last > 2500) { last = now; hits.clear(); onShake() }
    }
    override fun onAccuracyChanged(s: Sensor?, a: Int) {}
}
