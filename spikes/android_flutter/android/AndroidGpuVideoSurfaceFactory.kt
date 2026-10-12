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
 * M0 GPU-path spike:
 *
 * Media3 decoder -> Surface -> SurfaceTexture -> GL_TEXTURE_EXTERNAL_OES ->
 * GLSL effect stage -> native render target.
 *
 * Raw video frames never cross the Flutter method channel. The shader currently
 * exposes only diagnostic PASS_THROUGH / GRAYSCALE / POSTERIZE modes. It is a
 * proof of the processing seam, not the production FX engine.
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
    private val effect = ((params["effect"] as? String) ?: "passthrough").lowercase()
    private val effectAmount = ((params["effect_amount"] as? Number)?.toFloat() ?: 1f)
        .coerceIn(0f, 1f)
    private val posterizeLevels = ((params["posterize_levels"] as? Number)?.toFloat() ?: 6f)
        .coerceIn(2f, 32f)

    private var player: ExoPlayer? = null
    private var tracked = false
    private var disposed = false

    private val gpuView = PrismaGpuVideoView(
        context = context,
        fit = fit,
        effect = effect,
        effectAmount = effectAmount,
        posterizeLevels = posterizeLevels,
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

private class PrismaGpuVideoView(
    context: Context,
    fit: String,
    effect: String,
    effectAmount: Float,
    posterizeLevels: Float,
    onSurfaceReady: (Surface, OesVideoRenderer) -> Unit,
) : GLSurfaceView(context) {
    private val videoRenderer = OesVideoRenderer(
        hostView = this,
        fit = fit,
        effect = effect,
        effectAmount = effectAmount,
        posterizeLevels = posterizeLevels,
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
    effect: String,
    private val effectAmount: Float,
    private val posterizeLevels: Float,
    private val onSurfaceReady: (Surface, OesVideoRenderer) -> Unit,
) : GLSurfaceView.Renderer {
    private val effectMode = when (effect) {
        "grayscale" -> 1f
        "posterize" -> 2f
        else -> 0f
    }
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

    @Volatile
    private var frameAvailable = false

    @Volatile
    private var videoAspectRatio = 16f / 9f

    private var viewportWidth = 1
    private var viewportHeight = 1
    private var textureId = 0
    private var program = 0
    private var surfaceTexture: SurfaceTexture? = null
    private var surface: Surface? = null
    private var released = false

    fun setVideoAspectRatio(aspectRatio: Float) {
        if (aspectRatio <= 0f) return
        videoAspectRatio = aspectRatio
        hostView.requestRender()
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        if (released) return
        program = buildProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        textureId = createExternalTexture()

        val st = SurfaceTexture(textureId)
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
        viewportWidth = width.coerceAtLeast(1)
        viewportHeight = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, viewportWidth, viewportHeight)
    }

    override fun onDrawFrame(gl: GL10?) {
        if (released || program == 0) return

        if (frameAvailable) {
            frameAvailable = false
            surfaceTexture?.let { st ->
                st.updateTexImage()
                st.getTransformMatrix(textureMatrix)
            }
        }

        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glUseProgram(program)

        val positionLocation = GLES20.glGetAttribLocation(program, "aPosition")
        val texCoordLocation = GLES20.glGetAttribLocation(program, "aTexCoord")
        val matrixLocation = GLES20.glGetUniformLocation(program, "uTexMatrix")
        val scaleLocation = GLES20.glGetUniformLocation(program, "uScale")
        val textureLocation = GLES20.glGetUniformLocation(program, "uTexture")
        val effectModeLocation = GLES20.glGetUniformLocation(program, "uEffectMode")
        val effectAmountLocation = GLES20.glGetUniformLocation(program, "uEffectAmount")
        val posterizeLevelsLocation = GLES20.glGetUniformLocation(program, "uPosterizeLevels")

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

        val scale = resolveFitScale(
            fit = fit,
            sourceAspect = videoAspectRatio,
            viewportAspect = viewportWidth.toFloat() / viewportHeight.toFloat(),
        )
        GLES20.glUniform2f(scaleLocation, scale.first, scale.second)
        GLES20.glUniformMatrix4fv(matrixLocation, 1, false, textureMatrix, 0)
        GLES20.glUniform1f(effectModeLocation, effectMode)
        GLES20.glUniform1f(effectAmountLocation, effectAmount)
        GLES20.glUniform1f(posterizeLevelsLocation, posterizeLevels)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glUniform1i(textureLocation, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(positionLocation)
        GLES20.glDisableVertexAttribArray(texCoordLocation)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
    }

    fun release() {
        if (released) return
        released = true

        surface?.release()
        surface = null
        surfaceTexture?.setOnFrameAvailableListener(null)
        surfaceTexture?.release()
        surfaceTexture = null

        if (textureId != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
            textureId = 0
        }
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
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
        private const val VERTEX_SHADER = """
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

        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES uTexture;
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
