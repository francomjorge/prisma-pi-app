package com.prismapi.prisma_mobile_spike

import android.content.Context
import android.graphics.SurfaceTexture
import android.net.Uri
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.view.Surface
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * M0 ordered GPU-processing spike:
 *
 * Media3 decoder -> Surface -> SurfaceTexture -> GL_TEXTURE_EXTERNAL_OES ->
 * aspect/input pass -> ping-pong 2D render targets -> ordered PRISMA nodes ->
 * native render target.
 *
 * Raw video frames never cross the Flutter method channel. The native adapter
 * consumes a schema-versioned processing plan compiled from the platform-neutral
 * PRISMA ProcessingGraph. OpenGL texture/FBO identifiers remain private here.
 */
@UnstableApi
class AndroidGpuVideoSurfaceFactory :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = (args as? Map<*, *>) ?: emptyMap<String, Any?>()
        return AndroidGpuVideoPlatformView(context, params)
    }
}

@UnstableApi
private class AndroidGpuVideoPlatformView(
    context: Context,
    private val params: Map<*, *>,
) : PlatformView {
    private val path = params["path"] as? String
        ?: error("GPU video surface requires path")
    private val fit = ((params["fit"] as? String) ?: "contain").lowercase()
    private val autoplay = params["autoplay"] as? Boolean ?: true
    private val loop = params["loop"] as? Boolean ?: true
    private val muted = params["muted"] as? Boolean ?: true
    private val processing = DiagnosticProcessingConfig.fromParams(params)

    private var player: ExoPlayer? = null
    private var tracked = false
    private var disposed = false

    private val gpuView = PrismaGpuVideoView(
        context = context,
        fit = fit,
        processingNodes = processing.nodes,
        onSurfaceReady = surfaceReady@{ surface, renderer ->
            if (disposed || player != null) return@surfaceReady
            require(File(path).isFile) { "GPU video path does not exist: $path" }

            val exo = ExoPlayer.Builder(context).build().apply {
                repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                volume = if (muted) 0f else 1f
                addListener(object : Player.Listener {
                    override fun onVideoSizeChanged(videoSize: VideoSize) {
                        if (videoSize.width <= 0 || videoSize.height <= 0) return
                        renderer.setVideoAspectRatio(
                            (videoSize.width * videoSize.pixelWidthHeightRatio) /
                                videoSize.height.toFloat(),
                        )
                    }
                })
                setVideoSurface(surface)
                setMediaItem(MediaItem.fromUri(Uri.fromFile(File(path))))
                prepare()
                playWhenReady = autoplay
            }
            player = exo
            AndroidMediaResourceTracker.videoAcquired()
            tracked = true
        },
    )

    override fun getView(): View = gpuView

    override fun dispose() {
        if (disposed) return
        disposed = true

        player?.clearVideoSurface()
        player?.release()
        player = null

        if (tracked) {
            AndroidMediaResourceTracker.videoReleased()
            tracked = false
        }

        gpuView.releaseGpuResources()
    }
}

private data class DiagnosticProcessingNode(
    val nodeId: String,
    val type: String,
    val amount: Float,
    val posterizeLevels: Float,
) {
    val effectMode: Float
        get() = when (type) {
            "GRAYSCALE" -> 1f
            "POSTER" -> 2f
            else -> 0f
        }
}

private data class DiagnosticProcessingConfig(
    val nodes: List<DiagnosticProcessingNode>,
) {
    companion object {
        private const val MAX_DIAGNOSTIC_NODES = 4

        fun fromParams(params: Map<*, *>): DiagnosticProcessingConfig {
            val plan = params["processing_plan"] as? Map<*, *>
                ?: return DiagnosticProcessingConfig(emptyList())

            val schemaVersion = (plan["schema_version"] as? Number)?.toInt()
                ?: error("processing plan requires schema_version")
            require(schemaVersion == 1) {
                "unsupported processing plan schema_version: $schemaVersion"
            }

            val rawNodes = plan["nodes"] as? List<*>
                ?: error("processing plan requires nodes")
            require(rawNodes.size <= MAX_DIAGNOSTIC_NODES) {
                "M0 Android GPU adapter supports at most $MAX_DIAGNOSTIC_NODES active nodes"
            }

            val parsed = rawNodes.mapIndexed { index, raw ->
                val node = raw as? Map<*, *>
                    ?: error("processing node at index $index must be an object")
                val nodeId = node["node_id"] as? String
                    ?: error("processing node at index $index requires node_id")
                val type = (node["type"] as? String)?.uppercase()
                    ?: error("processing node $nodeId requires type")
                val order = (node["order"] as? Number)?.toInt()
                    ?: error("processing node $nodeId requires order")
                require(order == index) {
                    "processing plan order must be contiguous; $nodeId has order=$order at index=$index"
                }
                require(type == "POSTER" || type == "GRAYSCALE") {
                    "unsupported processing node $type ($nodeId) for M0 Android GPU adapter"
                }

                val parameters = (node["parameters"] as? Map<*, *>)
                    ?: emptyMap<String, Any?>()
                val amount = ((parameters["amount"] as? Number)?.toFloat() ?: 1f)
                    .coerceIn(0f, 1f)
                val levels = ((parameters["levels"] as? Number)?.toFloat() ?: 6f)
                    .coerceIn(2f, 32f)

                DiagnosticProcessingNode(
                    nodeId = nodeId,
                    type = type,
                    amount = amount,
                    posterizeLevels = levels,
                )
            }

            return DiagnosticProcessingConfig(parsed)
        }
    }
}

private class PrismaGpuVideoView(
    context: Context,
    fit: String,
    processingNodes: List<DiagnosticProcessingNode>,
    onSurfaceReady: (Surface, OesVideoRenderer) -> Unit,
) : GLSurfaceView(context) {
    private val videoRenderer = OesVideoRenderer(
        hostView = this,
        fit = fit,
        processingNodes = processingNodes,
        onSurfaceReady = onSurfaceReady,
    )
    private var released = false

    init {
        setEGLContextClientVersion(2)
        setRenderer(videoRenderer)
        renderMode = RENDERMODE_WHEN_DIRTY
        preserveEGLContextOnPause = false
    }

    fun releaseGpuResources() {
        if (released) return
        released = true
        queueEvent { videoRenderer.release() }
        onPause()
    }
}

private class OesVideoRenderer(
    private val hostView: GLSurfaceView,
    private val fit: String,
    private val processingNodes: List<DiagnosticProcessingNode>,
    private val onSurfaceReady: (Surface, OesVideoRenderer) -> Unit,
) : GLSurfaceView.Renderer {
    private val vertices: FloatBuffer = floatBufferOf(
        -1f, -1f,
        1f, -1f,
        -1f, 1f,
        1f, 1f,
    )
    private val textureCoordinates: FloatBuffer = floatBufferOf(
        0f, 0f,
        1f, 0f,
        0f, 1f,
        1f, 1f,
    )
    private val textureMatrix = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    private val pingTextures = IntArray(2)
    private val pingFramebuffers = IntArray(2)

    @Volatile
    private var frameAvailable = false

    @Volatile
    private var videoAspectRatio = 16f / 9f

    private var viewportWidth = 1
    private var viewportHeight = 1
    private var intermediateWidth = 0
    private var intermediateHeight = 0
    private var externalTextureId = 0
    private var inputProgram = 0
    private var effectProgram = 0
    private var surfaceTexture: SurfaceTexture? = null
    private var surface: Surface? = null
    private var externalTextureTracked = false
    private var trackedPingTextures = 0
    private var trackedFramebuffers = 0
    private var released = false

    fun setVideoAspectRatio(aspectRatio: Float) {
        if (aspectRatio <= 0f) return
        videoAspectRatio = aspectRatio
        hostView.requestRender()
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        if (released) return

        inputProgram = buildProgram(INPUT_VERTEX_SHADER, INPUT_FRAGMENT_SHADER)
        effectProgram = buildProgram(EFFECT_VERTEX_SHADER, EFFECT_FRAGMENT_SHADER)
        externalTextureId = createExternalTexture()
        AndroidMediaResourceTracker.gpuTexturesAcquired()
        externalTextureTracked = true

        val st = SurfaceTexture(externalTextureId)
        st.setOnFrameAvailableListener {
            frameAvailable = true
            hostView.requestRender()
        }
        surfaceTexture = st
        val outputSurface = Surface(st)
        surface = outputSurface

        hostView.post {
            if (!released) onSurfaceReady(outputSurface, this)
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        val newWidth = width.coerceAtLeast(1)
        val newHeight = height.coerceAtLeast(1)
        if (newWidth != viewportWidth || newHeight != viewportHeight) {
            releaseIntermediateTargets()
        }
        viewportWidth = newWidth
        viewportHeight = newHeight
        GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
    }

    override fun onDrawFrame(gl: GL10?) {
        if (released || inputProgram == 0 || externalTextureId == 0) return

        if (frameAvailable) {
            frameAvailable = false
            surfaceTexture?.let { st ->
                st.updateTexImage()
                st.getTransformMatrix(textureMatrix)
            }
        }

        if (processingNodes.isEmpty()) {
            drawExternalInput(targetFramebuffer = 0)
            return
        }

        ensureIntermediateTargets(viewportWidth, viewportHeight)

        // Convert/sample the OES decoder texture once into a regular 2D texture.
        // The input pass also resolves presentation geometry, so processing
        // passes can operate full-screen on regular textures without raw-frame
        // readback or exposing GL handles outside this adapter.
        drawExternalInput(targetFramebuffer = pingFramebuffers[0])

        var currentTextureIndex = 0
        processingNodes.forEachIndexed { index, node ->
            val isLast = index == processingNodes.lastIndex
            val targetTextureIndex = 1 - currentTextureIndex
            val targetFramebuffer = if (isLast) {
                0
            } else {
                pingFramebuffers[targetTextureIndex]
            }

            drawEffectPass(
                sourceTexture = pingTextures[currentTextureIndex],
                targetFramebuffer = targetFramebuffer,
                node = node,
            )

            if (!isLast) currentTextureIndex = targetTextureIndex
        }
    }

    private fun drawExternalInput(targetFramebuffer: Int) {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, targetFramebuffer)
        prepareTarget()
        GLES20.glUseProgram(inputProgram)

        val positionLocation = GLES20.glGetAttribLocation(inputProgram, "aPosition")
        val texCoordLocation = GLES20.glGetAttribLocation(inputProgram, "aTexCoord")
        val matrixLocation = GLES20.glGetUniformLocation(inputProgram, "uTexMatrix")
        val scaleLocation = GLES20.glGetUniformLocation(inputProgram, "uScale")
        val textureLocation = GLES20.glGetUniformLocation(inputProgram, "uTexture")

        bindQuad(positionLocation, texCoordLocation)

        val scale = resolveFitScale(
            fit = fit,
            sourceAspect = videoAspectRatio,
            viewportAspect = viewportWidth.toFloat() / viewportHeight.toFloat(),
        )
        GLES20.glUniform2f(scaleLocation, scale.first, scale.second)
        GLES20.glUniformMatrix4fv(matrixLocation, 1, false, textureMatrix, 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, externalTextureId)
        GLES20.glUniform1i(textureLocation, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        unbindQuad(positionLocation, texCoordLocation)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
    }

    private fun drawEffectPass(
        sourceTexture: Int,
        targetFramebuffer: Int,
        node: DiagnosticProcessingNode,
    ) {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, targetFramebuffer)
        prepareTarget()
        GLES20.glUseProgram(effectProgram)

        val positionLocation = GLES20.glGetAttribLocation(effectProgram, "aPosition")
        val texCoordLocation = GLES20.glGetAttribLocation(effectProgram, "aTexCoord")
        val textureLocation = GLES20.glGetUniformLocation(effectProgram, "uTexture")
        val effectModeLocation = GLES20.glGetUniformLocation(effectProgram, "uEffectMode")
        val effectAmountLocation = GLES20.glGetUniformLocation(effectProgram, "uEffectAmount")
        val posterizeLevelsLocation = GLES20.glGetUniformLocation(effectProgram, "uPosterizeLevels")

        bindQuad(positionLocation, texCoordLocation)
        GLES20.glUniform1f(effectModeLocation, node.effectMode)
        GLES20.glUniform1f(effectAmountLocation, node.amount)
        GLES20.glUniform1f(posterizeLevelsLocation, node.posterizeLevels)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, sourceTexture)
        GLES20.glUniform1i(textureLocation, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        unbindQuad(positionLocation, texCoordLocation)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
    }

    private fun bindQuad(positionLocation: Int, texCoordLocation: Int) {
        require(positionLocation >= 0 && texCoordLocation >= 0) {
            "required shader attributes are missing"
        }

        vertices.position(0)
        GLES20.glEnableVertexAttribArray(positionLocation)
        GLES20.glVertexAttribPointer(
            positionLocation,
            2,
            GLES20.GL_FLOAT,
            false,
            0,
            vertices,
        )

        textureCoordinates.position(0)
        GLES20.glEnableVertexAttribArray(texCoordLocation)
        GLES20.glVertexAttribPointer(
            texCoordLocation,
            2,
            GLES20.GL_FLOAT,
            false,
            0,
            textureCoordinates,
        )
    }

    private fun unbindQuad(positionLocation: Int, texCoordLocation: Int) {
        GLES20.glDisableVertexAttribArray(positionLocation)
        GLES20.glDisableVertexAttribArray(texCoordLocation)
    }

    private fun prepareTarget() {
        GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
    }

    private fun ensureIntermediateTargets(width: Int, height: Int) {
        if (
            intermediateWidth == width &&
            intermediateHeight == height &&
            pingTextures.all { it != 0 } &&
            pingFramebuffers.all { it != 0 }
        ) {
            return
        }

        releaseIntermediateTargets()

        GLES20.glGenTextures(2, pingTextures, 0)
        require(pingTextures.all { it != 0 }) { "failed to allocate ping-pong textures" }
        AndroidMediaResourceTracker.gpuTexturesAcquired(2)
        trackedPingTextures = 2

        pingTextures.forEach { texture ->
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_MIN_FILTER,
                GLES20.GL_LINEAR,
            )
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_MAG_FILTER,
                GLES20.GL_LINEAR,
            )
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_WRAP_S,
                GLES20.GL_CLAMP_TO_EDGE,
            )
            GLES20.glTexParameteri(
                GLES20.GL_TEXTURE_2D,
                GLES20.GL_TEXTURE_WRAP_T,
                GLES20.GL_CLAMP_TO_EDGE,
            )
            GLES20.glTexImage2D(
                GLES20.GL_TEXTURE_2D,
                0,
                GLES20.GL_RGBA,
                width,
                height,
                0,
                GLES20.GL_RGBA,
                GLES20.GL_UNSIGNED_BYTE,
                null,
            )
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)

        GLES20.glGenFramebuffers(2, pingFramebuffers, 0)
        require(pingFramebuffers.all { it != 0 }) { "failed to allocate ping-pong framebuffers" }
        AndroidMediaResourceTracker.gpuFramebuffersAcquired(2)
        trackedFramebuffers = 2

        pingFramebuffers.forEachIndexed { index, framebuffer ->
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebuffer)
            GLES20.glFramebufferTexture2D(
                GLES20.GL_FRAMEBUFFER,
                GLES20.GL_COLOR_ATTACHMENT0,
                GLES20.GL_TEXTURE_2D,
                pingTextures[index],
                0,
            )
            val status = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
            require(status == GLES20.GL_FRAMEBUFFER_COMPLETE) {
                "incomplete processing framebuffer[$index]: 0x${status.toString(16)}"
            }
        }
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)

        intermediateWidth = width
        intermediateHeight = height
    }

    private fun releaseIntermediateTargets() {
        if (pingFramebuffers.any { it != 0 }) {
            GLES20.glDeleteFramebuffers(2, pingFramebuffers, 0)
            pingFramebuffers.fill(0)
        }
        if (trackedFramebuffers > 0) {
            AndroidMediaResourceTracker.gpuFramebuffersReleased(trackedFramebuffers)
            trackedFramebuffers = 0
        }

        if (pingTextures.any { it != 0 }) {
            GLES20.glDeleteTextures(2, pingTextures, 0)
            pingTextures.fill(0)
        }
        if (trackedPingTextures > 0) {
            AndroidMediaResourceTracker.gpuTexturesReleased(trackedPingTextures)
            trackedPingTextures = 0
        }

        intermediateWidth = 0
        intermediateHeight = 0
    }

    fun release() {
        if (released) return
        released = true

        surface?.release()
        surface = null
        surfaceTexture?.setOnFrameAvailableListener(null)
        surfaceTexture?.release()
        surfaceTexture = null

        releaseIntermediateTargets()

        if (externalTextureId != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(externalTextureId), 0)
            externalTextureId = 0
        }
        if (externalTextureTracked) {
            AndroidMediaResourceTracker.gpuTexturesReleased()
            externalTextureTracked = false
        }

        if (inputProgram != 0) {
            GLES20.glDeleteProgram(inputProgram)
            inputProgram = 0
        }
        if (effectProgram != 0) {
            GLES20.glDeleteProgram(effectProgram)
            effectProgram = 0
        }
    }

    private fun resolveFitScale(
        fit: String,
        sourceAspect: Float,
        viewportAspect: Float,
    ): Pair<Float, Float> {
        if (sourceAspect <= 0f || viewportAspect <= 0f) return 1f to 1f

        return when (fit) {
            "fill" -> 1f to 1f
            "cover" -> {
                if (sourceAspect >= viewportAspect) {
                    (sourceAspect / viewportAspect) to 1f
                } else {
                    1f to (viewportAspect / sourceAspect)
                }
            }
            "fitwidth" -> 1f to (viewportAspect / sourceAspect)
            "fitheight" -> (sourceAspect / viewportAspect) to 1f
            else -> {
                if (sourceAspect >= viewportAspect) {
                    1f to (viewportAspect / sourceAspect)
                } else {
                    (sourceAspect / viewportAspect) to 1f
                }
            }
        }
    }

    private fun createExternalTexture(): Int {
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        val id = ids[0]
        require(id != 0) { "glGenTextures returned 0" }
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, id)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
        return id
    }

    private fun buildProgram(vertexSource: String, fragmentSource: String): Int {
        val vertex = compileShader(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragment = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val result = GLES20.glCreateProgram()
        require(result != 0) { "glCreateProgram failed" }
        GLES20.glAttachShader(result, vertex)
        GLES20.glAttachShader(result, fragment)
        GLES20.glLinkProgram(result)
        val status = IntArray(1)
        GLES20.glGetProgramiv(result, GLES20.GL_LINK_STATUS, status, 0)
        val log = GLES20.glGetProgramInfoLog(result)
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        if (status[0] == 0) {
            GLES20.glDeleteProgram(result)
            error("OpenGL program link failed: $log")
        }
        return result
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        require(shader != 0) { "glCreateShader failed" }
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)
        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            error("OpenGL shader compile failed: $log")
        }
        return shader
    }

    companion object {
        private const val INPUT_VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec4 aTexCoord;
            uniform mat4 uTexMatrix;
            uniform vec2 uScale;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = vec4(aPosition.xy * uScale, 0.0, 1.0);
                vTexCoord = (uTexMatrix * aTexCoord).xy;
            }
        """

        private const val INPUT_FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES uTexture;
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = texture2D(uTexture, vTexCoord);
            }
        """

        private const val EFFECT_VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec4 aTexCoord;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = aTexCoord.xy;
            }
        """

        private const val EFFECT_FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D uTexture;
            uniform float uEffectMode;
            uniform float uEffectAmount;
            uniform float uPosterizeLevels;
            varying vec2 vTexCoord;

            void main() {
                vec4 source = texture2D(uTexture, vTexCoord);
                vec3 processed = source.rgb;

                if (uEffectMode > 0.5 && uEffectMode < 1.5) {
                    float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
                    processed = vec3(luminance);
                } else if (uEffectMode >= 1.5) {
                    float levels = max(2.0, uPosterizeLevels);
                    processed = floor(source.rgb * levels + 0.5) / levels;
                }

                vec3 outputColor = mix(source.rgb, processed, clamp(uEffectAmount, 0.0, 1.0));
                gl_FragColor = vec4(outputColor, source.a);
            }
        """
    }
}

private fun floatBufferOf(vararg values: Float): FloatBuffer {
    val buffer = ByteBuffer
        .allocateDirect(values.size * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
    buffer.put(values)
    buffer.position(0)
    return buffer
}
