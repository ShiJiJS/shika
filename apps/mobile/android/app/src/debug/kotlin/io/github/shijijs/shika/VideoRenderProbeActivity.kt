package io.github.shijijs.shika

import android.app.Activity
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Debug-only, fixed public asset. No server, arbitrary URI, or private media access. */
class VideoRenderProbeActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var ownedSurface: Surface? = null
    private lateinit var root: FrameLayout
    private lateinit var sample: File
    private lateinit var runId: String
    private lateinit var mode: String
    private lateinit var sourceSha: String
    private var destroyed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(Build.HARDWARE.contains("ranchu") || Build.HARDWARE.contains("goldfish"))
        check(intent.getStringExtra("fixture") == "owned-public-video-probe")
        mode = intent.getStringExtra("mode") ?: "surface"
        check(mode in setOf("surface", "texture", "codec"))
        runId = intent.getStringExtra("run_id") ?: error("Missing run ID")
        check(runId.matches(Regex("[a-z0-9-]{1,64}")))
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)
        root = FrameLayout(this).also { it.setBackgroundColor(Color.BLACK) }
        setContentView(root)
        sample = File(cacheDir, "public-video-render-probe.mp4")
        assets.open("flutter_assets/assets/media/flower-landscape.mp4").use { input ->
            sample.outputStream().use { input.copyTo(it) }
        }
        sourceSha = MessageDigest.getInstance("SHA-256").digest(sample.readBytes())
            .joinToString("") { "%02x".format(it) }
        write("loading")
        if (mode == "codec") {
            root.addView(TextView(this).also { it.text = "Public codec probe"; it.setTextColor(Color.WHITE) })
            Thread { decodeFormat() }.start()
        } else if (mode == "surface") {
            val view = SurfaceView(this)
            root.addView(view, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
            view.holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) = start(holder.surface, view)
                override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
                override fun surfaceDestroyed(holder: SurfaceHolder) { releasePlayer() }
            })
        } else {
            val view = TextureView(this)
            root.addView(view, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
            view.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                    ownedSurface = Surface(texture)
                    start(ownedSurface!!, view)
                }
                override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {}
                override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
                override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                    releasePlayer(); ownedSurface?.release(); ownedSurface = null
                    return true
                }
            }
        }
    }

    private fun start(surface: Surface, view: View) {
        if (player != null || destroyed) return
        val current = MediaPlayer()
        player = current
        current.setSurface(surface)
        current.setDataSource(sample.absolutePath)
        current.setOnErrorListener { _, what, extra ->
            write("error", JSONObject().put("what", what).put("extra", extra)); true
        }
        var rendered = false
        var sought = false
        var pauseScheduled = false
        fun pauseAfterFrame() {
            if (!rendered || !sought || pauseScheduled) return
            pauseScheduled = true
            handler.postDelayed({
                if (destroyed || player !== current) return@postDelayed
                current.pause()
                val details = JSONObject().put("video_width", current.videoWidth).put("video_height", current.videoHeight)
                    .put("position_ms", current.currentPosition).put("playing", current.isPlaying)
                    .put("surface_type", view.javaClass.simpleName).put("metrics", current.metrics.toString())
                    .put("view_width", view.width).put("view_height", view.height)
                    .put("rendering_started", rendered).put("seek_completed", sought)
                    .put("root_width", root.width).put("root_height", root.height)
                write("ready", details)
            }, 500)
        }
        current.setOnInfoListener { _, what, _ ->
            if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) {
                rendered = true
                pauseAfterFrame()
            }
            false
        }
        current.setOnPreparedListener { p ->
            val startWhenLaidOut = object : Runnable {
                override fun run() {
                    if (destroyed || player !== p) return
                    if (root.width <= root.height || root.height == 0) {
                        handler.postDelayed(this, 40)
                        return
                    }
                    val scale = minOf(root.width.toDouble() / p.videoWidth, root.height.toDouble() / p.videoHeight)
                    val width = (p.videoWidth * scale).toInt()
                    val height = (p.videoHeight * scale).toInt()
                    if (view.width != width || view.height != height) {
                        view.layoutParams = FrameLayout.LayoutParams(width, height, Gravity.CENTER)
                        handler.postDelayed(this, 40)
                        return
                    }
                    p.start()
                    p.seekTo(3000L, MediaPlayer.SEEK_CLOSEST)
                }
            }
            handler.post(startWhenLaidOut)
        }
        current.setOnSeekCompleteListener { _ -> sought = true; pauseAfterFrame() }
        current.prepareAsync()
    }

    private fun decodeFormat() {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(sample.absolutePath)
            val track = (0 until extractor.trackCount).first { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)!!.startsWith("video/") }
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val inputDescription = format.toString()
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            val details = JSONObject().put("decoder", decoder.name).put("input_format", inputDescription)
                .put("output_request", "YUV420Flexible; byte-buffer mode, separate from surface playback")
            val deadline = android.os.SystemClock.elapsedRealtime() + 12000
            val info = MediaCodec.BufferInfo()
            var ended = false
            while (android.os.SystemClock.elapsedRealtime() < deadline) {
                if (!ended) {
                    val input = decoder.dequeueInputBuffer(10000)
                    if (input >= 0) {
                        val size = extractor.readSampleData(decoder.getInputBuffer(input)!!, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            ended = true
                        } else {
                            decoder.queueInputBuffer(input, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val output = decoder.dequeueOutputBuffer(info, 10000)
                if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    details.put("output_format", decoder.outputFormat.toString())
                } else if (output >= 0) {
                    details.put("output_format", decoder.getOutputFormat(output).toString())
                        .put("output_bytes", info.size).put("pts_us", info.presentationTimeUs)
                    decoder.getOutputImage(output)?.use { image ->
                        details.put("image_width", image.width).put("image_height", image.height)
                            .put("crop", image.cropRect.toShortString())
                            .put("planes", JSONArray().also { planes -> image.planes.forEach { plane ->
                                planes.put(JSONObject().put("row_stride", plane.rowStride).put("pixel_stride", plane.pixelStride).put("remaining", plane.buffer.remaining()))
                            } })
                    }
                    decoder.releaseOutputBuffer(output, false)
                    write("ready", details)
                    return
                }
            }
            error("Decoder output deadline exceeded")
        } catch (error: Exception) {
            write("error", JSONObject().put("error", error.toString()))
        } finally {
            try { codec?.stop() } finally { codec?.release(); extractor.release() }
        }
    }

    @Synchronized private fun write(status: String, details: JSONObject = JSONObject()) {
        val value = JSONObject().put("run_id", runId).put("mode", mode).put("status", status)
            .put("source_sha256", if (::sourceSha.isInitialized) sourceSha else "")
            .put("details", details)
        val target = File(cacheDir, "video-render-probe.json")
        val temporary = File(cacheDir, "video-render-probe.json.tmp")
        temporary.writeText(value.toString(2))
        check(temporary.renameTo(target))
        android.util.Log.i("VV_RENDER_PROBE", value.toString())
    }

    private fun releasePlayer() { player?.release(); player = null }
    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacksAndMessages(null)
        releasePlayer(); ownedSurface?.release(); ownedSurface = null
        super.onDestroy()
    }
}
