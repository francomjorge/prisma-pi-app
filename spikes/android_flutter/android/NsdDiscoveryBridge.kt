package com.prismapi.prisma_mobile_spike

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import java.nio.charset.StandardCharsets

/**
 * M0-only Android NSD adapter spike for PRISMA appliance discovery.
 *
 * This intentionally uses the broadly available NsdManager API surface so the
 * platform boundary compiles independently of the production permission UX.
 * Android 17 local-network permission / system-picker behavior is handled as a
 * separate product decision before this code can become production code.
 */
class NsdDiscoveryBridge(context: Context) {
    interface Listener {
        fun onService(record: Map<String, Any?>)
        fun onError(code: String, detail: String)
    }

    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    fun start(listener: Listener) {
        if (discoveryListener != null) return

        val callbacks = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (!serviceInfo.serviceType.contains("_prisma-pi._tcp")) return
                resolve(serviceInfo, listener)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                listener.onError("NSD_START_FAILED", errorCode.toString())
                stop()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                listener.onError("NSD_STOP_FAILED", errorCode.toString())
            }
        }

        discoveryListener = callbacks
        try {
            nsdManager.discoverServices(
                SERVICE_TYPE,
                NsdManager.PROTOCOL_DNS_SD,
                callbacks,
            )
        } catch (error: SecurityException) {
            discoveryListener = null
            listener.onError("LOCAL_NETWORK_PERMISSION", error.message ?: "permission denied")
        } catch (error: RuntimeException) {
            discoveryListener = null
            listener.onError("NSD_RUNTIME", error.message ?: error.javaClass.simpleName)
        }
    }

    fun stop() {
        val listener = discoveryListener ?: return
        discoveryListener = null
        try {
            nsdManager.stopServiceDiscovery(listener)
        } catch (_: RuntimeException) {
            // Best-effort shutdown for the diagnostic spike.
        }
    }

    @Suppress("DEPRECATION")
    private fun resolve(serviceInfo: NsdServiceInfo, listener: Listener) {
        try {
            nsdManager.resolveService(
                serviceInfo,
                object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        listener.onError("NSD_RESOLVE_FAILED", errorCode.toString())
                    }

                    override fun onServiceResolved(info: NsdServiceInfo) {
                        val txt = info.attributes.mapValues { (_, value) ->
                            String(value, StandardCharsets.UTF_8)
                        }
                        listener.onService(
                            mapOf(
                                "service_name" to info.serviceName,
                                "service_type" to info.serviceType,
                                "host" to info.host?.hostAddress,
                                "port" to info.port,
                                "txt" to txt,
                            ),
                        )
                    }
                },
            )
        } catch (error: SecurityException) {
            listener.onError("LOCAL_NETWORK_PERMISSION", error.message ?: "permission denied")
        } catch (error: RuntimeException) {
            listener.onError("NSD_RESOLVE_RUNTIME", error.message ?: error.javaClass.simpleName)
        }
    }

    companion object {
        const val SERVICE_TYPE = "_prisma-pi._tcp."
    }
}
