package io.github.xkeyc.fl_caption

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Adds system audio capture for Dart: `fl_caption/playback` methods
 * `start` (asks for the screen capture consent, then starts
 * [PlaybackCaptureService]; returns whether it started) and `stop`, and the
 * `fl_caption/playback_audio` event stream of 16 kHz mono 16-bit PCM chunks
 * (an error event when capturing stops). `fl_caption/overlay`: the floating
 * caption window ([CaptionOverlay]): `allowed`, `requestPermission`, `show`,
 * `hide`, `update` {lines: [{source, translation}], oldest first},
 * `configure` {history, fontSize}; it calls `closed` when the user closes it.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_CAPTURE = 4712
    }

    private var pendingStart: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val overlay = MethodChannel(messenger, "fl_caption/overlay")
        CaptionOverlay.onClosed = { overlay.invokeMethod("closed", null) }
        overlay.setMethodCallHandler { call, result ->
            when (call.method) {
                "allowed" -> result.success(CaptionOverlay.canShow(this))
                "requestPermission" -> {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
                    )
                    result.success(null)
                }
                "show" -> {
                    if (!CaptionOverlay.canShow(this)) {
                        result.success(false)
                    } else {
                        CaptionOverlay.show(this)
                        result.success(true)
                    }
                }
                "hide" -> {
                    CaptionOverlay.hide()
                    result.success(null)
                }
                "update" -> {
                    val lines = call.argument<List<Map<String, String>>>("lines") ?: emptyList()
                    CaptionOverlay.update(lines.map { (it["source"] ?: "") to (it["translation"] ?: "") })
                    result.success(null)
                }
                "configure" -> {
                    CaptionOverlay.configure(
                        this,
                        call.argument<Int>("history") ?: 1,
                        (call.argument<Double>("fontSize") ?: 19.0).toFloat(),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "fl_caption/playback").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(Build.VERSION.SDK_INT >= 29)
                "start" -> {
                    if (Build.VERSION.SDK_INT < 29) {
                        result.error("unsupported", "System audio capture needs Android 10 or later", null)
                        return@setMethodCallHandler
                    }
                    pendingStart?.success(false)
                    pendingStart = result
                    val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    @Suppress("DEPRECATION")
                    startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CAPTURE)
                }
                "stop" -> {
                    stopService(Intent(this, PlaybackCaptureService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "fl_caption/playback_audio").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                PlaybackCaptureService.onAudio = { chunk -> events.success(chunk) }
                PlaybackCaptureService.onError = { message -> events.error("capture", message, null) }
            }

            override fun onCancel(arguments: Any?) {
                PlaybackCaptureService.onAudio = null
                PlaybackCaptureService.onError = null
            }
        })
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        val result = pendingStart ?: return
        pendingStart = null
        if (resultCode != RESULT_OK || data == null) {
            result.success(false)
            return
        }
        val intent = Intent(this, PlaybackCaptureService::class.java)
            .putExtra(PlaybackCaptureService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(PlaybackCaptureService.EXTRA_DATA, data)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        result.success(true)
    }
}
