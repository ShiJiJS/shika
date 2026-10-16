package io.github.shijijs.video_viewer

import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private var originalBrightness: Float? = null
    private val audio get() = getSystemService(AUDIO_SERVICE) as AudioManager
    private fun minimumVolume() = if (Build.VERSION.SDK_INT >= 28) audio.getStreamMinVolume(AudioManager.STREAM_MUSIC) else 0
    private fun levels(): Map<String, Double> {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val min = minimumVolume()
        val volume = (audio.getStreamVolume(AudioManager.STREAM_MUSIC) - min).toDouble() / (max - min).coerceAtLeast(1)
        val current = window.attributes.screenBrightness
        val brightness = if (current >= 0) current.toDouble() else
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
        return mapOf("volume" to volume, "brightness" to brightness.coerceIn(0.0, 1.0),
            "windowBrightness" to current.toDouble())
    }
    private fun restoreBrightness() {
        originalBrightness?.let { value ->
            window.attributes = window.attributes.apply { screenBrightness = value }
        }
        originalBrightness = null
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "video_viewer/playback").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "levels" -> result.success(levels())
                    "brightness" -> {
                        val value = (call.argument<Number>("value")?.toDouble() ?: error("Missing brightness")).coerceIn(0.02, 1.0)
                        if (originalBrightness == null) originalBrightness = window.attributes.screenBrightness
                        window.attributes = window.attributes.apply { screenBrightness = value.toFloat() }
                        result.success(levels())
                    }
                    "volume" -> {
                        val value = (call.argument<Number>("value")?.toDouble() ?: error("Missing volume")).coerceIn(0.0, 1.0)
                        val min = minimumVolume()
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        audio.setStreamVolume(AudioManager.STREAM_MUSIC, min + ((max - min) * value).roundToInt(), 0)
                        result.success(levels())
                    }
                    "restoreBrightness" -> { restoreBrightness(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("PLAYBACK_CONTROL", error.message, null)
            }
        }
    }
    override fun onPause() { restoreBrightness(); super.onPause() }
    override fun onDestroy() { restoreBrightness(); super.onDestroy() }
}
