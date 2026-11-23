// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import dev.pairlume.core.Link
import dev.pairlume.core.Pairing
import dev.pairlume.core.PairlumeException
import dev.pairlume.core.QrCode
import java.net.InetSocketAddress
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

sealed interface Step {
    data object Idle : Step
    data object Connecting : Step
    data class Code(val name: String, val code: String) : Step
    data class Done(val name: String) : Step
    data class Failed(val why: String) : Step
}

/** one pairing at a time; the state is set on the main thread */
class Pairer(context: Context) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var answer: CompletableFuture<Boolean>? = null
    @Volatile private var link: Link? = null
    @Volatile private var round = 0
    var step: Step by mutableStateOf(Step.Idle)
        private set
    val busy get() = step is Step.Connecting || step is Step.Code

    private fun go(to: InetSocketAddress, qr: QrCode?, talk: (Link, Int) -> Unit) {
        if (busy) return
        val me = ++round
        step = Step.Connecting
        Thread({
            val end: Step = try {
                Link.open(Phone.identity(), Phone.name(app), to, qr?.fingerprint).use { l ->
                    link = l
                    talk(l, me)
                    if (round != me) throw PairlumeException("stopped")
                    Saved(app).computer = Computer(l.computer, l.name, to)
                    Step.Done(l.name)
                }
            } catch (e: Exception) {
                Step.Failed(if (e is PairlumeException) t(e.message ?: "") else t("The computer did not answer. Is it pairing, on the same Wi-Fi?"))
            }
            main.post {
                if (round != me) return@post
                link = null
                answer = null
                step = end
                if (end is Step.Done) { LinkService.stop(app); LinkService.start(app) }
            }
        }, "pairlume-pair").start()
    }

    fun shake(f: Found) = go(f.address, null) { l, me ->
        l.patience = Link.HUMAN
        l.pairing().shake { code ->
            val a = CompletableFuture<Boolean>()
            main.post { if (round == me) { answer = a; step = Step.Code(l.name, code) } else a.complete(false) }
            try { a.get(90, TimeUnit.SECONDS) } catch (_: Exception) { false }
        }
    }

    fun digits(f: Found, digits: String) {
        if (!Pairing.isDigits(digits)) { step = Step.Failed(t("The code has six digits")); return }
        if (!Saved(app).firstTry(digits)) { step = Step.Failed(t("These digits were already tried. Make new ones on the computer")); return }
        go(f.address, null) { l, _ -> l.pairing().digits(digits) }
    }

    fun qr(text: String): Boolean {
        val qr = try { QrCode.parse(text) } catch (_: Exception) { return false }
        go(qr.address, qr) { l, _ -> l.pairing().qr(qr.secret) }
        return true
    }

    fun answer(yes: Boolean) { answer?.complete(yes); answer = null; if (yes) step = Step.Connecting }

    fun cancel() {
        round++
        answer?.complete(false)
        answer = null
        link?.let { l -> Thread { l.close() }.start() }
        link = null
        step = Step.Idle
    }

    fun say(why: String) { if (!busy) step = Step.Failed(why) }
}
