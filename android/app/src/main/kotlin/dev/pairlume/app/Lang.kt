// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.util.Locale

/**
 * The words of the app, from share/lang/<code>.json (the same files the computer and the installer read). English is the
 * key; a word that is not translated stays English. %1, %2 are filled in.
 */
object Lang {
    /** English first, then the languages of Poland, then the others */
    val codes = listOf("en", "pl", "szl", "csb", "de", "es", "fr", "it", "pt", "uk", "cs")
    private lateinit var app: Context
    private var words: Map<String, String> = emptyMap()
    private val names = HashMap<String, String>()
    /** the chosen one, "" for the phone's own language */
    var chosen by mutableStateOf("")
        private set
    /** read by every word, so that the screen follows a change at once */
    private var round by mutableIntStateOf(0)

    fun init(c: Context) {
        if (::app.isInitialized) return
        app = c.applicationContext
        chosen = app.getSharedPreferences("choices", Context.MODE_PRIVATE).getString("lang", "") ?: ""
        load()
    }

    fun choose(code: String) {
        chosen = if (code in codes) code else ""
        app.getSharedPreferences("choices", Context.MODE_PRIVATE).edit().putString("lang", chosen).apply()
        load()
    }

    /** what is used now */
    fun current(): String = chosen.ifEmpty { Locale.getDefault().language.let { if (it in codes) it else "en" } }

    /** the name of a language in itself: Polski, Ślōnsko godka, Kaszëbsczi */
    fun name(code: String): String = names.getOrPut(code) { (file(code)?.get("name") as? JsonPrimitive)?.content ?: code }

    private fun file(code: String): JsonObject? = try {
        app.assets.open("lang/$code.json").use { Json.parseToJsonElement(it.readBytes().decodeToString()).jsonObject }
    } catch (_: Exception) { null }

    private fun load() {
        words = (file(current())?.get("phone") as? JsonObject)?.mapValues { (_, v) -> (v as? JsonPrimitive)?.content ?: "" }?.filterValues { it.isNotEmpty() } ?: emptyMap()
        round++
    }

    fun t(key: String, vararg args: Any): String {
        round
        var s = if (::app.isInitialized) words[key] ?: key else key
        args.forEachIndexed { i, a -> s = s.replace("%${i + 1}", a.toString()) }
        return s
    }
}

fun t(key: String, vararg args: Any) = Lang.t(key, *args)
