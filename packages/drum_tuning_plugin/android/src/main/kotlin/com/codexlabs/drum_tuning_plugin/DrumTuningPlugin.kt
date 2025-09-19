package com.codexlabs.drum_tuning_plugin

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.annotation.UiThread
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.sqrt

class DrumTuningPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var applicationContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionListener: PluginRegistry.RequestPermissionsResultListener? = null

    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopRecording()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> handleStart(result)
            "stop" -> {
                stopRecording()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleStart(result: MethodChannel.Result) {
        if (!hasAudioPermission()) {
            val currentActivity = activity
            if (currentActivity == null) {
                result.error(
                    "NO_ACTIVITY",
                    "Cannot request microphone permission without an attached Activity.",
                    null
                )
                return
            }
            pendingPermissionResult?.error(
                "CANCELLED",
                "Superseded by a new permission request.",
                null
            )
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(
                currentActivity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                AUDIO_PERMISSION_REQUEST
            )
            return
        }

        startRecording()
        result.success(null)
    }

    @UiThread
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    @UiThread
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun hasAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun startRecording() {
        if (isRecording.get()) {
            return
        }

        val minBufferBytes = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT
        )
        if (minBufferBytes == AudioRecord.ERROR || minBufferBytes == AudioRecord.ERROR_BAD_VALUE) {
            eventSink?.error(
                "AUDIO_INIT_FAILED",
                "Unable to determine minimum buffer size for AudioRecord.",
                null
            )
            return
        }

        val bufferBytes = (minBufferBytes * 2).coerceAtLeast(minBufferBytes)
        val frameCount = bufferBytes / Float.SIZE_BYTES
        if (frameCount <= 0) {
            eventSink?.error(
                "AUDIO_INIT_FAILED",
                "Calculated buffer frame count was zero.",
                null
            )
            return
        }

        audioRecord = buildAudioRecord(MediaRecorder.AudioSource.UNPROCESSED, bufferBytes)
            ?: buildAudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, bufferBytes)
            ?: buildAudioRecord(MediaRecorder.AudioSource.DEFAULT, bufferBytes)

        if (audioRecord == null || audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord?.release()
            audioRecord = null
            eventSink?.error(
                "AUDIO_INIT_FAILED",
                "AudioRecord failed to initialize.",
                null
            )
            return
        }

        audioRecord?.startRecording()
        isRecording.set(true)
        recordingThread = Thread(AudioReader(frameCount)).also { it.start() }
    }

    private fun stopRecording() {
        isRecording.set(false)
        recordingThread?.interrupt()
        recordingThread = null

        audioRecord?.run {
            try {
                stop()
            } catch (_: IllegalStateException) {
            }
            release()
        }
        audioRecord = null
    }

    private fun buildAudioRecord(source: Int, bufferBytes: Int): AudioRecord? {
        return try {
            AudioRecord.Builder()
                .setAudioSource(source)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(SAMPLE_RATE)
                        .build()
                )
                .setBufferSizeInBytes(bufferBytes)
                .build()
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private inner class AudioReader(frameCount: Int) : Runnable {
        private val floatBuffer = FloatArray(frameCount)
        private var lastEmissionMs = 0L

        override fun run() {
            val recorder = audioRecord ?: return
            while (isRecording.get() && !Thread.currentThread().isInterrupted) {
                val read = recorder.read(floatBuffer, 0, floatBuffer.size, AudioRecord.READ_BLOCKING)
                if (read <= 0) {
                    continue
                }
                val now = System.currentTimeMillis()
                if (now - lastEmissionMs < STRIKE_COOLDOWN_MS) {
                    continue
                }

                val rmsValue = rms(floatBuffer, read)
                if (rmsValue < RMS_THRESHOLD) {
                    continue
                }

                val frequency = estimateFrequency(floatBuffer, read)
                val confidence = (rmsValue / TARGET_RMS).coerceIn(0f, 1f).toDouble()

                publishResult(frequency, confidence)
                lastEmissionMs = now
            }
        }

        private fun publishResult(freq: Double?, confidence: Double) {
            val timestamp = System.currentTimeMillis()
            val (note, cents) = if (freq != null) {
                val midi = 69.0 + 12.0 * logBase(freq / 440.0, 2.0)
                val nearestMidi = midi.roundToInt()
                Pair(noteName(nearestMidi), (midi - nearestMidi) * 100.0)
            } else {
                Pair(null, null)
            }

            val payload = mapOf(
                "f0Hz" to freq,
                "f1Hz" to null,
                "rtf" to null,
                "noteName" to note,
                "cents" to cents,
                "confidence" to confidence,
                "peaks" to emptyList<Map<String, Any?>>(),
                "timestampMs" to timestamp
            )

            eventSink?.let { sink ->
                mainHandler.post { sink.success(payload) }
            }
        }

        private fun rms(samples: FloatArray, length: Int): Float {
            var sum = 0.0
            for (i in 0 until length) {
                val value = samples[i]
                sum += value * value
            }
            return sqrt((sum / length).toFloat())
        }

        private fun estimateFrequency(samples: FloatArray, length: Int): Double? {
            var crossings = 0
            var prev = samples[0]
            for (i in 1 until length) {
                val current = samples[i]
                if ((prev >= 0f && current < 0f) || (prev <= 0f && current > 0f)) {
                    crossings++
                }
                prev = current
            }
            if (crossings < 2) {
                return null
            }
            val zeroCrossRate = crossings * SAMPLE_RATE / (2.0 * length)
            if (zeroCrossRate < 30.0 || zeroCrossRate > 1200.0) {
                return null
            }
            return zeroCrossRate
        }
    }

    private fun logBase(value: Double, base: Double): Double {
        return ln(value) / ln(base)
    }

    private fun noteName(midi: Int): String {
        val octave = (midi / 12) - 1
        val noteIndex = ((midi % 12) + 12) % 12
        return NOTE_NAMES[noteIndex] + octave
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        val listener = PluginRegistry.RequestPermissionsResultListener { requestCode, _, grantResults ->
            if (requestCode != AUDIO_PERMISSION_REQUEST) {
                return@RequestPermissionsResultListener false
            }
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val result = pendingPermissionResult
            pendingPermissionResult = null
            if (granted) {
                startRecording()
                result?.success(null)
            } else {
                result?.error(
                    "PERMISSION_DENIED",
                    "Microphone permission denied by user.",
                    null
                )
            }
            true
        }
        permissionListener = listener
        binding.addRequestPermissionsResultListener(listener)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        clearActivityBinding()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        permissionListener?.let { binding.addRequestPermissionsResultListener(it) }
    }

    override fun onDetachedFromActivity() {
        clearActivityBinding()
    }

    private fun clearActivityBinding() {
        val listener = permissionListener
        if (listener != null) {
            activityBinding?.removeRequestPermissionsResultListener(listener)
        }
        activityBinding = null
        activity = null
    }

    companion object {
        private const val METHOD_CHANNEL = "drum_tuning_plugin/methods"
        private const val EVENT_CHANNEL = "drum_tuning_plugin/analysis"
        private const val AUDIO_PERMISSION_REQUEST = 0x4452
        private const val SAMPLE_RATE = 44100
        private const val RMS_THRESHOLD = 0.015f
        private const val TARGET_RMS = 0.12f
        private const val STRIKE_COOLDOWN_MS = 180L
        private val NOTE_NAMES = arrayOf(
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
        )
    }
}
