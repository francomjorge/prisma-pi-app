package com.prismapi.prisma_mobile_spike

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@UnstableApi
class AndroidMediaSurfaceFactory(private val context: Context) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = (args as? Map<*, *>) ?: emptyMap<String, Any?>()
        return AndroidMediaSurfacePlatformView(context, params)
    }
}

@UnstableApi
private class AndroidMediaSurfacePlatformView(
    context: Context,
    private val params: Map<*, *>,
) : PlatformView {
    private val root = FrameLayout(context)
    private var player: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var imageView: ImageView? = null
    private var bitmap: Bitmap? = null
    private var trackedImageBytes = 0L
    private var videoTracked = false
    private var disposed = false

    init {
        val path = params["path"] as? String
            ?: error("native media surface requires path")
        val kind = (params["kind"] as? String)?.lowercase()
            ?: error("native media surface requires kind")
        require(File(path).isFile) { "native media surface path does not exist: $path" }

        when (kind) {
            "image" -> openImage(context, path)
            "video" -> openVideo(context, path)
            else -> error("unsupported native media surface kind: $kind")
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        if (disposed) return
        disposed = true

        playerView?.player = null
        playerView = null
        player?.release()
        player = null
        if (videoTracked) {
            AndroidMediaResourceTracker.videoReleased()
            videoTracked = false
        }

        imageView?.setImageDrawable(null)
        imageView = null
        bitmap?.let {
            if (!it.isRecycled) it.recycle()
        }
        bitmap = null
        if (trackedImageBytes > 0) {
            AndroidMediaResourceTracker.imageReleased(trackedImageBytes)
            trackedImageBytes = 0
        }

        root.removeAllViews()
    }

    private fun openImage(context: Context, path: String) {
        val targetWidth = (params["target_width"] as? Number)?.toInt()?.coerceAtLeast(1) ?: 1280
        val targetHeight = (params["target_height"] as? Number)?.toInt()?.coerceAtLeast(1) ?: 720
        val fit = ((params["fit"] as? String) ?: "contain").lowercase()
        val decoded = TargetImageDecoder.decode(
            File(path),
            targetWidth,
            targetHeight,
            fit,
        )
        bitmap = decoded
        trackedImageBytes = decoded.allocationByteCount.toLong()
        AndroidMediaResourceTracker.imageAcquired(trackedImageBytes)

        val image = ImageView(context).apply {
            scaleType = imageScaleType(fit)
            adjustViewBounds = false
            setImageBitmap(decoded)
        }
        imageView = image
        root.addView(
            image,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private fun openVideo(context: Context, path: String) {
        val fit = ((params["fit"] as? String) ?: "contain").lowercase()
        val autoplay = params["autoplay"] as? Boolean ?: true
        val loop = params["loop"] as? Boolean ?: true
        val muted = params["muted"] as? Boolean ?: true

        val exo = ExoPlayer.Builder(context).build().apply {
            repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            volume = if (muted) 0f else 1f
            setMediaItem(MediaItem.fromUri(Uri.fromFile(File(path))))
            prepare()
            playWhenReady = autoplay
        }
        player = exo

        val view = PlayerView(context).apply {
            useController = false
            resizeMode = videoResizeMode(fit)
            player = exo
            keepScreenOn = autoplay
        }
        playerView = view
        AndroidMediaResourceTracker.videoAcquired()
        videoTracked = true
        root.addView(
            view,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private fun imageScaleType(fit: String): ImageView.ScaleType = when (fit) {
        "cover" -> ImageView.ScaleType.CENTER_CROP
        "fill" -> ImageView.ScaleType.FIT_XY
        "fitwidth" -> ImageView.ScaleType.FIT_CENTER
        "fitheight" -> ImageView.ScaleType.FIT_CENTER
        "nativepixels" -> ImageView.ScaleType.CENTER
        "scaledown" -> ImageView.ScaleType.CENTER_INSIDE
        else -> ImageView.ScaleType.FIT_CENTER
    }

    private fun videoResizeMode(fit: String): Int = when (fit) {
        "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
        "fitwidth" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
        "fitheight" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
        else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
    }
}

private object TargetImageDecoder {
    fun decode(file: File, targetWidth: Int, targetHeight: Int, fit: String): Bitmap {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            decodeModern(file, targetWidth, targetHeight, fit)
        } else {
            decodeCompat(file, targetWidth, targetHeight, fit)
        }
    }

    private fun decodeModern(
        file: File,
        targetWidth: Int,
        targetHeight: Int,
        fit: String,
    ): Bitmap {
        return ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
            val sourceWidth = info.size.width
            val sourceHeight = info.size.height
            val target = resolveTarget(
                sourceWidth,
                sourceHeight,
                targetWidth,
                targetHeight,
                fit,
            )
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
            decoder.setTargetSize(target.first, target.second)
        }
    }

    private fun decodeCompat(
        file: File,
        targetWidth: Int,
        targetHeight: Int,
        fit: String,
    ): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) {
            "unreadable image dimensions for ${file.absolutePath}"
        }
        val target = resolveTarget(
            bounds.outWidth,
            bounds.outHeight,
            targetWidth,
            targetHeight,
            fit,
        )
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= target.first &&
            bounds.outHeight / (sample * 2) >= target.second
        ) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeFile(file.absolutePath, options)
            ?: error("BitmapFactory failed to decode ${file.absolutePath}")
        if (decoded.width == target.first && decoded.height == target.second) return decoded
        val scaled = Bitmap.createScaledBitmap(decoded, target.first, target.second, true)
        if (scaled !== decoded && !decoded.isRecycled) decoded.recycle()
        return scaled
    }

    private fun resolveTarget(
        sourceWidth: Int,
        sourceHeight: Int,
        viewportWidth: Int,
        viewportHeight: Int,
        fit: String,
    ): Pair<Int, Int> {
        val widthScale = viewportWidth.toDouble() / sourceWidth
        val heightScale = viewportHeight.toDouble() / sourceHeight
        val scale = when (fit) {
            "cover" -> max(widthScale, heightScale)
            "fill" -> return Pair(
                min(sourceWidth, viewportWidth).coerceAtLeast(1),
                min(sourceHeight, viewportHeight).coerceAtLeast(1),
            )
            "fitwidth" -> widthScale
            "fitheight" -> heightScale
            "nativepixels" -> 1.0
            "scaledown" -> min(1.0, min(widthScale, heightScale))
            else -> min(widthScale, heightScale)
        }.coerceAtMost(1.0)

        return Pair(
            max(1, (sourceWidth * scale).roundToInt()),
            max(1, (sourceHeight * scale).roundToInt()),
        )
    }
}
