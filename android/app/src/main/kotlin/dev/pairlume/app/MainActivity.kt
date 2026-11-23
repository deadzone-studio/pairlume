// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import kotlinx.coroutines.delay

private val Night = darkColorScheme(
    primary = Color(0xFF7AA2FF), onPrimary = Color(0xFF0B1020), tertiary = Color(0xFFC08BFF), background = Color(0xFF0B1020),
    surface = Color(0xFF0E1424), onSurface = Color(0xFFE8EDF8), onSurfaceVariant = Color(0xFF9AA6C4), surfaceVariant = Color(0xFF1A2340),
)

class MainActivity : ComponentActivity() {
    private lateinit var pairer: Pairer

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        enableEdgeToEdge()
        pairer = Pairer(this)
        setContent {
            MaterialTheme(if (Build.VERSION.SDK_INT >= 31) dynamicDarkColorScheme(this) else Night) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { App(pairer) }
            }
        }
    }

    override fun onDestroy() {
        pairer.cancel()
        super.onDestroy()
    }
}

@Composable
private fun App(pairer: Pairer) {
    val context = LocalContext.current
    var computer by remember { mutableStateOf(Saved(context).computer) }
    val notify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33) notify.launch(Manifest.permission.POST_NOTIFICATIONS)
        LinkService.start(context)
    }
    val step = pairer.step
    LaunchedEffect(step) { if (step is Step.Done) { delay(2400); computer = Saved(context).computer; pairer.cancel() } }
    val tint = MaterialTheme.colorScheme
    Box(
        Modifier.fillMaxSize()
            .background(Brush.verticalGradient(listOf(tint.primary.copy(alpha = 0.14f), Color.Transparent, tint.tertiary.copy(alpha = 0.08f))))
            .safeDrawingPadding(),
    ) {
        val c = computer
        if (c != null && step !is Step.Done) Home(c) {
            Saved(context).computer = null
            LinkService.stop(context)
            computer = null
        } else Pair(pairer)
    }
}

// ---------- paired ----------
@Composable
private fun Home(c: Computer, forget: () -> Unit) {
    val context = LocalContext.current
    var sure by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(48.dp))
        Lumen(LinkState.connected)
        Spacer(Modifier.height(28.dp))
        Text(c.name, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text(
            when {
                LinkState.connected -> "Connected"
                else -> "Looking for it on this network"
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(32.dp))
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp)) {
            Column(Modifier.padding(20.dp)) {
                Text("What the computer lets this phone do", fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(6.dp))
                Text(
                    when {
                        !LinkState.connected -> "Not connected"
                        LinkState.allowed.isEmpty() -> "Nothing yet. On the computer: pairlume allow \"${Phone.name(context)}\" sms"
                        else -> LinkState.allowed.sorted().joinToString(", ")
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        TextChoices(c.name)
        Spacer(Modifier.height(12.dp))
        CallSwitches(c.name)
        Spacer(Modifier.height(12.dp))
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp)) {
            Column(Modifier.padding(20.dp)) {
                Text("Keeps dropping out?", fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(6.dp))
                Text("Some phones stop apps in the background. Let Pairlume use the battery without limits.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton({ context.open(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS) }) { Text("Battery settings") }
            }
        }
        Spacer(Modifier.height(20.dp))
        TextButton({ sure = true }) { Text("Forget this computer") }
    }
    if (sure) AlertDialog(
        onDismissRequest = { sure = false },
        title = { Text("Forget ${c.name}?") },
        text = { Text("You can pair again later. The computer keeps this phone in its list until you unpair it there.") },
        confirmButton = { TextButton({ sure = false; forget() }) { Text("Forget") } },
        dismissButton = { TextButton({ sure = false }) { Text("Keep") } },
    )
}

/** what this phone gives; the computer's own permission comes on top */
@Composable
private fun TextChoices(computer: String) {
    val context = LocalContext.current
    val choices = remember { Choices(context) }
    var read by remember { mutableStateOf(choices.read) }
    var send by remember { mutableStateOf(choices.send) }
    val askRead = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { got ->
        // the names from the contacts are nice to have, the texts work without
        choices.read = Choices.READ.all { got[it] == true || context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        read = choices.read
    }
    val askSend = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { got ->
        choices.send = got.values.all { it }
        send = choices.send
    }
    LifecycleResumeEffect(Unit) { read = choices.read; send = choices.send; onPauseOrDispose { } }
    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp)) {
        Column(Modifier.padding(20.dp)) {
            Text("Texts", fontWeight = FontWeight.SemiBold)
            Choice("Show on $computer", "It asks for conversations when you open them there. Nothing is saved.", read) { on ->
                if (on) askRead.launch(Choices.READ + Manifest.permission.READ_CONTACTS) else { choices.read = false; read = false }
            }
            Choice("Send from $computer", "Texts cost what your plan says. At most 8 a minute, never to short numbers.", send) { on ->
                if (on) askSend.launch(Choices.SEND) else { choices.send = false; send = false }
            }
        }
    }
}

/** calls: shown on the computer, and answered or made from it */
@Composable
private fun CallSwitches(computer: String) {
    val context = LocalContext.current
    val choices = remember { CallChoices(context) }
    var show by remember { mutableStateOf(choices.show) }
    var act by remember { mutableStateOf(choices.act) }
    val askShow = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { got ->
        choices.show = CallChoices.SHOW.all { got[it] == true || context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        show = choices.show
    }
    val askAct = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { got ->
        choices.act = CallChoices.ACT.all { got[it] == true || context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        act = choices.act
    }
    LifecycleResumeEffect(Unit) { show = choices.show; act = choices.act; onPauseOrDispose { } }
    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp)) {
        Column(Modifier.padding(20.dp)) {
            Text("Calls", fontWeight = FontWeight.SemiBold)
            Choice("Show on $computer", "Who calls, with the name and picture from your contacts. Nothing is saved.", show) { on ->
                if (on) askShow.launch(CallChoices.SHOW + Manifest.permission.READ_CONTACTS) else { choices.show = false; show = false }
            }
            Choice("Answer and call from $computer", "It never calls codes with * or #.", act) { on ->
                if (on) askAct.launch(CallChoices.ACT) else { choices.act = false; act = false }
            }
            VoiceRow(computer)
        }
    }
}

/** the voice of calls on the computer: one button, the rest is Bluetooth's own question */
@Composable
private fun VoiceRow(computer: String) {
    val context = LocalContext.current
    val address = LinkState.bluetooth
    var paired by remember { mutableStateOf(false) }
    var asked by remember { mutableStateOf(false) }
    fun look() { paired = address != null && Voice.paired(context, address) }
    LaunchedEffect(address, asked) { while (true) { look(); delay(1500) } }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok && address != null) asked = Voice.pair(context, address)
    }
    Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text("Voice on $computer")
            Text(
                when {
                    address == null -> "$computer has no Bluetooth, or is not connected"
                    paired -> "Ready. Calls you answer there are heard there, through Bluetooth."
                    !Voice.on(context) -> "Turn Bluetooth on first"
                    asked -> "Say yes on both screens: the same code is on $computer"
                    else -> "Talk through the computer's speakers and microphone"
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (address != null && !paired && Voice.on(context)) Button({
            if (Voice.permitted(context)) asked = Voice.pair(context, address)
            else if (Build.VERSION.SDK_INT >= 31) ask.launch(Manifest.permission.BLUETOOTH_CONNECT)
        }) { Text("Connect") }
    }
}

@Composable
private fun Choice(what: String, about: String, on: Boolean, change: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(what)
            Text(about, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
        Switch(on, change, Modifier.semantics { contentDescription = what })
    }
}

private fun Context.open(action: String) = try { startActivity(Intent(action)) } catch (_: Exception) { }

/** two lights: apart while looking, one while connected */
@Composable
private fun Lumen(one: Boolean) {
    val c = MaterialTheme.colorScheme
    val gap by animateFloatAsState(if (one) 0.24f else 0.62f, spring(dampingRatio = 0.45f, stiffness = 120f), label = "gap")
    val breath by rememberInfiniteTransition(label = "breath").animateFloat(0.94f, 1.06f, infiniteRepeatable(tween(1900, easing = EaseInOutSine), RepeatMode.Reverse), label = "breath")
    Canvas(Modifier.size(220.dp, 140.dp).semantics { contentDescription = if (one) "Connected" else "Not connected" }) {
        val r = size.height * 0.32f * breath
        val d = size.width * gap / 2
        listOf(-d to c.primary, d to c.tertiary).forEach { (x, color) ->
            val at = center + Offset(x, 0f)
            drawCircle(Brush.radialGradient(listOf(color.copy(alpha = 0.55f), Color.Transparent), at, r * 1.9f), r * 1.9f, at)
            drawCircle(color.copy(alpha = 0.85f), r, at)
        }
    }
}

// ---------- pairing ----------
private enum class Way(val label: String) { Shake("Shake"), Qr("QR code"), Digits("Digits") }

@Composable
private fun Pair(pairer: Pairer) {
    val context = LocalContext.current
    var way by rememberSaveable { mutableStateOf(Way.Shake) }
    var found by remember { mutableStateOf(emptyList<Found>()) }
    /** several computers are pairing: which one, and what then */
    var choose by remember { mutableStateOf<((Found) -> Unit)?>(null) }
    val discovery = remember { Discovery(context) { found = it } }
    LifecycleResumeEffect(Unit) { discovery.start(); onPauseOrDispose { discovery.stop(); found = emptyList() } }

    val ready = rememberUpdatedState(found.filter { it.pairing })
    fun withComputer(f: (Found) -> Unit) = when (ready.value.size) {
        0 -> pairer.say("No computer here is pairing. Start it there: pairlume-ui")
        1 -> f(ready.value.first())
        else -> choose = f
    }
    val shaker = remember {
        Shaker(context) {
            if (!pairer.busy && pairer.step !is Step.Done) {
                context.getSystemService(Vibrator::class.java).vibrate(VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE))
                withComputer(pairer::shake)
            }
        }
    }
    if (way == Way.Shake && !pairer.busy) LifecycleResumeEffect(Unit) { shaker.start(); onPauseOrDispose { shaker.stop() } }
    BackHandler(pairer.step !is Step.Idle && pairer.step !is Step.Done) { pairer.cancel() }

    AnimatedContent(
        pairer.step,
        transitionSpec = { (fadeIn() + scaleIn(spring(0.6f, 300f), 0.92f)) togetherWith fadeOut(tween(120)) },
        contentKey = { it::class },
        label = "step",
    ) { step ->
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(32.dp))
            when (step) {
                Step.Idle -> {
                    Title(when (way) { Way.Shake -> "Shake your phone"; Way.Qr -> "Scan the code"; Way.Digits -> "Type the digits" },
                        ready.value.firstOrNull()?.let { "${it.name} is pairing" } ?: "Open pairing on your computer, on the same Wi-Fi")
                    Box(Modifier.weight(1f).fillMaxWidth(), Alignment.Center) {
                        when (way) {
                            Way.Shake -> if (shaker.available) Waiting() else Text("This phone has no motion sensor. Use the code or the digits.")
                            Way.Qr -> Camera { if (!pairer.busy) pairer.qr(it) }
                            Way.Digits -> Typing { d -> withComputer { pairer.digits(it, d) } }
                        }
                    }
                    SingleChoiceSegmentedButtonRow(Modifier.padding(bottom = 16.dp)) {
                        Way.entries.forEachIndexed { i, w -> SegmentedButton(way == w, { way = w }, SegmentedButtonDefaults.itemShape(i, Way.entries.size)) { Text(w.label) } }
                    }
                }
                Step.Connecting -> {
                    Title("Connecting", "")
                    Box(Modifier.weight(1f), Alignment.Center) { CircularProgressIndicator(Modifier.size(72.dp), strokeWidth = 6.dp) }
                    TextButton(pairer::cancel) { Text("Stop") }
                }
                is Step.Code -> {
                    Title(step.name, "Is the same code on its screen?")
                    Box(Modifier.weight(1f), Alignment.Center) { Digits(step.code) }
                    var armed by remember { mutableStateOf(false) }
                    LaunchedEffect(Unit) { delay(900); armed = true }
                    Row(Modifier.padding(bottom = 24.dp), Arrangement.spacedBy(12.dp)) {
                        FilledTonalButton({ pairer.answer(false) }, enabled = armed) { Text("Not the same") }
                        Button({ pairer.answer(true) }, enabled = armed) { Text("They match") }
                    }
                }
                is Step.Done -> {
                    Title("Connected", step.name)
                    Box(Modifier.weight(1f), Alignment.Center) {
                        var one by remember { mutableStateOf(false) }
                        LaunchedEffect(Unit) { one = true }
                        Lumen(one)
                    }
                }
                is Step.Failed -> {
                    Title("That did not work", step.why)
                    Spacer(Modifier.weight(1f))
                    Button(pairer::cancel, Modifier.padding(bottom = 24.dp)) { Text("Try again") }
                }
            }
        }
    }
    choose?.let { f ->
        AlertDialog(
            onDismissRequest = { choose = null },
            title = { Text("Which computer?") },
            text = { Column { ready.value.forEach { c -> TextButton({ choose = null; f(c) }, Modifier.fillMaxWidth()) { Text("${c.name} (${c.id})") } } } },
            confirmButton = {},
        )
    }
}

@Composable
private fun Title(big: String, small: String) {
    Text(big, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
    Spacer(Modifier.height(8.dp))
    Text(small, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
}

/** rings of light and a phone that shows what to do */
@Composable
private fun Waiting() {
    val c = MaterialTheme.colorScheme
    val all = rememberInfiniteTransition(label = "rings")
    val rings = List(4) { i -> all.animateFloat(0f, 1f, infiniteRepeatable(tween(2800, easing = LinearOutSlowInEasing), initialStartOffset = StartOffset(i * 700)), label = "ring") }
    val turn by all.animateFloat(0f, 0f, infiniteRepeatable(keyframes {
        durationMillis = 1900
        0f at 900; -13f at 990; 12f at 1110; -9f at 1220; 6f at 1320; 0f at 1500
    }), label = "turn")
    Canvas(Modifier.size(300.dp)) {
        rings.forEachIndexed { i, r ->
            drawCircle((if (i % 2 == 0) c.primary else c.tertiary).copy(alpha = (1 - r.value) * 0.6f), size.minDimension * (0.15f + 0.35f * r.value), style = Stroke(2.dp.toPx()))
        }
        val w = 64.dp.toPx()
        val h = 124.dp.toPx()
        val at = center - Offset(w / 2, h / 2)
        rotate(turn, Offset(center.x, center.y + h / 2)) {
            drawRoundRect(Brush.verticalGradient(listOf(c.tertiary, c.primary), at.y, at.y + h), at, Size(w, h), CornerRadius(16.dp.toPx()))
            val m = 4.dp.toPx()
            drawRoundRect(c.surface, at + Offset(m, m), Size(w - 2 * m, h - 2 * m), CornerRadius(12.dp.toPx()))
        }
    }
}

@Composable
private fun Digits(code: String) {
    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = code.toList().joinToString(" ") }, Arrangement.spacedBy(8.dp)) {
        code.forEachIndexed { i, d ->
            if (i == 3) Spacer(Modifier.width(6.dp))
            var here by remember { mutableStateOf(false) }
            LaunchedEffect(Unit) { delay(i * 70L); here = true }
            val s by animateFloatAsState(if (here) 1f else 0.3f, spring(0.45f, 380f), label = "digit")
            Box(
                Modifier.graphicsLayer { scaleX = s; scaleY = s; alpha = if (here) 1f else 0f }.size(46.dp, 62.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)),
                Alignment.Center,
            ) { Text(d.toString(), fontSize = 30.sp, fontWeight = FontWeight.Bold) }
        }
    }
}

@Composable
private fun Typing(onDone: (String) -> Unit) {
    var t by rememberSaveable { mutableStateOf("") }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        OutlinedTextField(
            t, { t = it.filter { c -> c in '0'..'9' }.take(6) },
            textStyle = LocalTextStyle.current.copy(fontSize = 34.sp, textAlign = TextAlign.Center, letterSpacing = 8.sp, fontWeight = FontWeight.Bold),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            singleLine = true,
            shape = RoundedCornerShape(24.dp),
            modifier = Modifier.width(280.dp).semantics { contentDescription = "Six digits from the computer" },
        )
        Button({ val d = t; t = ""; onDone(d) }, enabled = t.length == 6) { Text("Pair") }
    }
}

@Composable
private fun Camera(onText: (String) -> Unit) {
    val context = LocalContext.current
    var ok by remember { mutableStateOf(context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok = it }
    if (ok) {
        Scanner(Modifier.size(300.dp).clip(RoundedCornerShape(36.dp)), onText)
    } else {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("The camera is only used to read the code.", textAlign = TextAlign.Center)
            Button({ ask.launch(Manifest.permission.CAMERA) }) { Text("Use the camera") }
        }
    }
}
