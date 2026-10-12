package com.prismapi.prisma_mobile_spike

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var discoveryBridge: NsdDiscoveryBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prisma.pi/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> result.success(mapOf("platform" to "android", "boundary" to "ok"))
                    else -> result.notImplemented()
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

    override fun onDestroy() {
        discoveryBridge?.stop()
        discoveryBridge = null
        super.onDestroy()
    }
}
