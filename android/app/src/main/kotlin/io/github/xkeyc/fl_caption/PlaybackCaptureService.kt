package io.github.xkeyc.fl_caption

import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Records what other apps play (Android 10+ AudioPlaybackCapture) as
 * 16 kHz mono 16-bit PCM and hands it to [onAudio] on the main thread.
 *
 * Android 14 requires this order: the user's MediaProjection consent, then
 * this foreground service of type mediaProjection, then the projection.
 */
@TargetApi(Build.VERSION_CODES.Q)
class PlaybackCaptureService : Service() {
    companion object {
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA = "data"
        private const val CHANNEL_ID = "fl_caption_playback"
        private const val NOTIFICATION_ID = 4711
        const val SAMPLE_RATE = 16000

        /** Receives the PCM chunks (set by MainActivity's event channel). */
        @Volatile
        var onAudio: ((ByteArray) -> Unit)? = null

        /** Called with a message when capturing cannot start or stops. */
        @Volatile
        var onError: ((String) -> Unit)? = null
    }

    private var projection: MediaProjection? = null
    private var record: AudioRecord? = null
    @Volatile
    private var running = false
    private var thread: Thread? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    @SuppressLint("MissingPermission")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent?.getParcelableExtra(EXTRA_DATA)
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            fail("screen capture permission was not granted")
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = manager.getMediaProjection(resultCode, data)
            if (projection == null) {
                fail("the screen capture permission is no longer valid")
                return START_NOT_STICKY
            }
            this.projection = projection
            val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .build()
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            )
            val record = AudioRecord.Builder()
                .setAudioFormat(format)
                .setBufferSizeInBytes(maxOf(minBuffer, SAMPLE_RATE / 5 * 2))
                .setAudioPlaybackCaptureConfig(config)
                .build()
            this.record = record
            record.startRecording()
            running = true
            thread = Thread {
                // 100 ms chunks.
                val buffer = ByteArray(SAMPLE_RATE / 10 * 2)
                while (running) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) {
                        val chunk = buffer.copyOf(read)
                        main.post { onAudio?.invoke(chunk) }
                    } else if (read < 0) {
                        fail("playback capture stopped ($read)")
                        break
                    }
                }
            }.apply {
                name = "fl-playback-capture"
                start()
            }
        } catch (e: Exception) {
            fail("playback capture failed: ${e.message}")
        }
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "System audio capture", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val notification = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else
            @Suppress("DEPRECATION") Notification.Builder(this))
            .setContentTitle("FL Caption")
            .setContentText("Sending system audio to the computer for captions")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun fail(message: String) {
        main.post { onError?.invoke(message) }
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        thread?.join(500)
        record?.run {
            try { stop() } catch (_: Exception) {}
            release()
        }
        record = null
        projection?.stop()
        projection = null
        super.onDestroy()
    }
}
