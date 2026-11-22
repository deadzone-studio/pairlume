// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.core.content.edit
import dev.pairlume.core.Fingerprint
import dev.pairlume.core.Identity
import dev.pairlume.core.cleanName
import dev.pairlume.core.parseAddress
import java.net.InetSocketAddress
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.security.auth.x500.X500Principal

private const val ALIAS = "pairlume"

/** This phone's key. It is made in Android's key store and cannot be read out of it, not even by this app. */
object Phone {
    @Synchronized
    fun identity(): Identity {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(ALIAS)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").run {
                initialize(
                    KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                        .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                        .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
                        .setCertificateSubject(X500Principal("CN=pairlume"))
                        .setCertificateNotBefore(Date(0))
                        .setCertificateNotAfter(Date(4102444800000)) // 2100
                        .build(),
                )
                generateKeyPair()
            }
        }
        return Identity(ks.getKey(ALIAS, null) as PrivateKey, ks.getCertificate(ALIAS) as X509Certificate)
    }

    fun name(c: Context): String =
        cleanName(Settings.Global.getString(c.contentResolver, Settings.Global.DEVICE_NAME) ?: "${Build.MANUFACTURER} ${Build.MODEL}")
}

/** the computer this phone is paired with */
class Computer(val id: Fingerprint, val name: String, val address: InetSocketAddress?)

class Saved(c: Context) {
    private val p = c.getSharedPreferences("pairlume", Context.MODE_PRIVATE)

    var computer: Computer?
        get() {
            val id = p.getString("id", null) ?: return null
            return try {
                Computer(Fingerprint.parse(id), p.getString("name", null) ?: "Computer", p.getString("address", null)?.let(::parseAddress))
            } catch (_: Exception) {
                null
            }
        }
        set(v) = p.edit {
            if (v == null) { remove("id"); remove("name"); remove("address") } else {
                putString("id", v.id.toString())
                putString("name", v.name)
                putString("address", v.address?.let { a -> a.address.hostAddress!!.let { if (':' in it) "[${it.substringBefore('%')}]" else it } + ":" + a.port })
            }
        }

    /** digits that were tried are never tried again: a failed try can give some of them away */
    fun firstTry(digits: String): Boolean {
        if (p.getString("digits", null) == digits) return false
        p.edit(commit = true) { putString("digits", digits) }
        return true
    }
}
