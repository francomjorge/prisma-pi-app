package com.prismapi.prisma_mobile_spike

import android.app.Activity
import android.content.Intent
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_PICK_REQUEST_CODE = 41021
    }

    private var discoveryBridge: NsdDiscoveryBridge? = null
    private var pendingMediaPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "prisma.pi/native_media_surface",
            AndroidMediaSurfaceFactory(this),
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "prisma.pi/gpu_video_surface",
            AndroidGpuVideoSurfaceFactory(),
        )

        val mediaBridge = AndroidMediaBridge(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prisma.pi/media")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "ping" -> result.success(
                            mapOf("platform" to "android", "boundary" to "ok")
                        )
                        "appPaths" -> result.success(
                            mapOf(
                                "files_dir" to filesDir.absolutePath,
                                "cache_dir" to cacheDir.absolutePath,
                            )
                        )
                        "resourceSnapshot" -> result.success(
                            AndroidMediaResourceTracker.snapshot()
                        )
                        "pickMedia" -> launchMediaPicker(result)
                        "inspectUri" -> {
                            val uri = call.argument<String>("uri")
                                ?: error("uri is required")
                            result.success(mediaBridge.inspectUri(uri))
                        }
                        "copyUriToFile" -> {
                            val uri = call.argument<String>("uri")
                                ?: error("uri is required")
                            val targetPath = call.argument<String>("target_path")
                                ?: error("target_path is required")
                            result.success(mediaBridge.copyUriToFile(uri, targetPath))
                        }
                        "probeManagedFile" -> {
                            val path = call.argument<String>("path")
                                ?: error("path is required")
                            result.success(mediaBridge.probeManagedFile(path))
                        }
                        "decodeImageFile" -> {
                            val path = call.argument<String>("path")
                                ?: error("path is required")
                            result.success(mediaBridge.decodeImageFile(path))
                        }
                        "decodeVideoFrame" -> {
                            val path = call.argument<String>("path")
                                ?: error("path is required")
                            val timeMs = call.argument<Number>("time_ms")?.toLong() ?: 0L
                            result.success(mediaBridge.decodeVideoFrame(path, timeMs))
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    if (call.method == "pickMedia") {
                        pendingMediaPickResult = null
                    }
                    result.error(
                        "MEDIA_BRIDGE_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prisma.pi/security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "secureStoreProbe" -> {
                        try {
                            result.success(KeystoreSecretBridge(applicationContext).runProbe())
                        } catch (error: Exception) {
                            result.error(
                                "KEYSTORE_PROBE_FAILED",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "prisma.pi/discovery")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val bridge = NsdDiscoveryBridge(applicationContext)
                    discoveryBridge?.stop()
                    discoveryBridge = bridge
                    bridge.start(object : NsdDiscoveryBridge.Listener {
                        override fun onService(record: Map<String, Any?>) {
                            runOnUiThread { events.success(record) }
                        }

                        override fun onError(code: String, detail: String) {
                            runOnUiThread { events.error(code, detail, null) }
                        }
                    })
                }

                override fun onCancel(arguments: Any?) {
                    discoveryBridge?.stop()
                    discoveryBridge = null
                }
            })
    }

    private fun launchMediaPicker(result: MethodChannel.Result) {
        if (pendingMediaPickResult != null) {
            result.error(
                "MEDIA_PICK_IN_PROGRESS",
                "A media picker request is already active",
                null,
            )
            return
        }

        pendingMediaPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivityForResult(intent, MEDIA_PICK_REQUEST_CODE)
    }

    @Deprecated("Deprecated in Android API; retained only for this disposable M0 spike")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != MEDIA_PICK_REQUEST_CODE) return

        val pending = pendingMediaPickResult ?: return
        pendingMediaPickResult = null

        if (resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            pending.error(
                "MEDIA_PICK_EMPTY_RESULT",
                "Android document picker returned no URI",
                null,
            )
            return
        }

        pending.success(uri.toString())
    }

    override fun onDestroy() {
        discoveryBridge?.stop()
        discoveryBridge = null
        pendingMediaPickResult?.error(
            "MEDIA_PICK_CANCELLED",
            "Activity destroyed before media picker completed",
            null,
        )
        pendingMediaPickResult = null
        super.onDestroy()
    }
}
