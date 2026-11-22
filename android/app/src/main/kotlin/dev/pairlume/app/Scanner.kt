// SPDX-License-Identifier: GPL-3.0-or-later
package dev.pairlume.app

import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors

/** The camera. Pictures are only looked at here, for a code; nothing is kept. */
@Composable
fun Scanner(modifier: Modifier, onText: (String) -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val found = rememberUpdatedState(onText)
    val view = remember { PreviewView(context) }
    DisposableEffect(owner) {
        val worker = Executors.newSingleThreadExecutor()
        val reader = MultiFormatReader().apply { setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))) }
        val future = ProcessCameraProvider.getInstance(context)
        var gone = false
        val main = ContextCompat.getMainExecutor(context)
        future.addListener({
            if (!gone) try {
                val preview = Preview.Builder().build().apply { surfaceProvider = view.surfaceProvider }
                val size = ResolutionSelector.Builder().setResolutionStrategy(ResolutionStrategy(Size(1280, 720), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)).build()
                val look = ImageAnalysis.Builder().setResolutionSelector(size).build()
                look.setAnalyzer(worker) { img -> img.use { read(reader, it) }?.let { t -> main.execute { if (!gone) found.value(t) } } }
                future.get().run { unbindAll(); bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, look) }
            } catch (_: Exception) {
                // no camera to use: the other ways are still there
            }
        }, main)
        onDispose {
            gone = true
            if (future.isDone) try { future.get().unbindAll() } catch (_: Exception) { }
            worker.shutdown()
        }
    }
    AndroidView({ view }, modifier)
}

private fun read(reader: MultiFormatReader, img: ImageProxy): String? {
    val p = img.planes[0]
    val b = ByteArray(p.buffer.remaining()).also { p.buffer.get(it) }
    // the last row can be shorter than the others
    val h = if (b.size >= p.rowStride * img.height) img.height else b.size / p.rowStride
    if (h < 1) return null
    val src = PlanarYUVLuminanceSource(b, p.rowStride, h, 0, 0, img.width.coerceAtMost(p.rowStride), h, false)
    return try {
        reader.decodeWithState(BinaryBitmap(HybridBinarizer(src))).text
    } catch (_: ReaderException) {
        null
    } finally {
        reader.reset()
    }
}
