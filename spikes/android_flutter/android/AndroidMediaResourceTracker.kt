package com.prismapi.prisma_mobile_spike

import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Process-local diagnostic counters for expensive native media/GPU resources.
 *
 * This is intentionally simple and lock-free. Production resource ownership
 * will be driven by platform-neutral registries plus native adapters, but M0
 * needs evidence that Bitmap/decoder/surface/texture/framebuffer ownership
 * returns to baseline when a source view or processing plan is disposed.
 */
object AndroidMediaResourceTracker {
    private val decodedImageBytes = AtomicLong(0)
    private val activeVideoDecoders = AtomicInteger(0)
    private val activeRenderSurfaces = AtomicInteger(0)
    private val activeGpuTextures = AtomicInteger(0)
    private val activeGpuFramebuffers = AtomicInteger(0)

    fun imageAcquired(bytes: Long) {
        require(bytes >= 0) { "decoded image bytes must be non-negative" }
        decodedImageBytes.addAndGet(bytes)
        activeRenderSurfaces.incrementAndGet()
    }

    fun imageReleased(bytes: Long) {
        decodedImageBytes.updateAndGet { current -> (current - bytes).coerceAtLeast(0) }
        activeRenderSurfaces.updateAndGet { current -> (current - 1).coerceAtLeast(0) }
    }

    fun videoAcquired() {
        activeVideoDecoders.incrementAndGet()
        activeRenderSurfaces.incrementAndGet()
    }

    fun videoReleased() {
        activeVideoDecoders.updateAndGet { current -> (current - 1).coerceAtLeast(0) }
        activeRenderSurfaces.updateAndGet { current -> (current - 1).coerceAtLeast(0) }
    }

    fun gpuTexturesAcquired(count: Int = 1) {
        require(count >= 0) { "GPU texture count must be non-negative" }
        activeGpuTextures.addAndGet(count)
    }

    fun gpuTexturesReleased(count: Int = 1) {
        require(count >= 0) { "GPU texture count must be non-negative" }
        activeGpuTextures.updateAndGet { current -> (current - count).coerceAtLeast(0) }
    }

    fun gpuFramebuffersAcquired(count: Int = 1) {
        require(count >= 0) { "GPU framebuffer count must be non-negative" }
        activeGpuFramebuffers.addAndGet(count)
    }

    fun gpuFramebuffersReleased(count: Int = 1) {
        require(count >= 0) { "GPU framebuffer count must be non-negative" }
        activeGpuFramebuffers.updateAndGet { current -> (current - count).coerceAtLeast(0) }
    }

    fun snapshot(): Map<String, Any> = mapOf(
        "decoded_image_bytes" to decodedImageBytes.get(),
        "active_video_decoders" to activeVideoDecoders.get(),
        "active_render_surfaces" to activeRenderSurfaces.get(),
        "active_gpu_textures" to activeGpuTextures.get(),
        "active_gpu_framebuffers" to activeGpuFramebuffers.get(),
    )
}
