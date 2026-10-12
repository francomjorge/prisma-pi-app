package com.prismapi.prisma_mobile_spike

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prisma.pi/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> result.success(mapOf("platform" to "android", "boundary" to "ok"))
                    else -> result.notImplemented()
                }
            }
    }
}
