package com.prismapi.prisma_mobile_spike

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File

/**
 * Diagnostic Android media/storage boundary for M0.
 *
 * This deliberately uses ContentResolver for user-selected content instead of
 * relying on unstable external filesystem paths. It also probes and decodes
 * managed local files natively so full image/video payloads do not cross the
 * Flutter method channel.
 */
class AndroidMediaBridge(private val context: Context) {
    fun inspectUri(uriText: String): Map<String, Any?> {
        val uri = Uri.parse(uriText)
        var displayName: String? = null
        var size: Long? = null

        context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    displayName = cursor.getString(nameIndex)
                }
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }

        return mapOf(
            "uri" to uri.toString(),
            "display_name" to displayName,
            "byte_size" to size,
            "mime_type" to context.contentResolver.getType(uri),
            "scheme" to uri.scheme,
        )
    }

    fun copyUriToFile(uriText: String, targetPath: String): Map<String, Any?> {
        val uri = Uri.parse(uriText)
        val target = File(targetPath)
        target.parentFile?.mkdirs()

        val input = context.contentResolver.openInputStream(uri)
            ?: error("ContentResolver returned no stream for $uri")

        var copied = 0L
        input.use { source ->
            target.outputStream().buffered().use { destination ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val count = source.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    destination.write(buffer, 0, count)
                    copied += count
                }
                destination.flush()
            }
        }

        return mapOf(
            "target_path" to target.absolutePath,
            "byte_size" to copied,
            "exists" to target.exists(),
        )
    }

    fun probeManagedFile(path: String): Map<String, Any?> {
        val file = File(path)
        require(file.exists() && file.isFile) { "Managed media file does not exist: $path" }

        val image = probeImage(file)
        if (image != null) return image

        val video = probeVideo(file)
        if (video != null) return video

        error("Unsupported or unreadable media: $path")
    }

    fun decodeImageFile(path: String): Map<String, Any?> {
        val file = File(path)
        require(file.exists() && file.isFile) { "Managed image file does not exist: $path" }

        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
            ?: error("Android BitmapFactory could not decode $path")
        return try {
            bitmapSummary(bitmap, "ANDROID_BITMAP_FACTORY")
        } finally {
            bitmap.recycle()
        }
    }

    fun decodeVideoFrame(path: String, timeMs: Long): Map<String, Any?> {
        val file = File(path)
        require(file.exists() && file.isFile) { "Managed video file does not exist: $path" }

        val retriever = MediaMetadataRetriever()
        var bitmap: Bitmap? = null
        return try {
            retriever.setDataSource(file.absolutePath)
            val safeTimeMs = timeMs.coerceAtLeast(0L)
            bitmap = retriever.getFrameAtTime(
                safeTimeMs * 1000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: error("Android could not decode a video frame at ${safeTimeMs}ms")

            bitmapSummary(bitmap, "ANDROID_MEDIA_METADATA_RETRIEVER") + mapOf(
                "requested_time_ms" to safeTimeMs,
            )
        } finally {
            bitmap?.recycle()
            retriever.release()
        }
    }

    private fun bitmapSummary(bitmap: Bitmap, backend: String): Map<String, Any?> = mapOf(
        "backend" to backend,
        "width" to bitmap.width,
        "height" to bitmap.height,
        "allocation_bytes" to bitmap.allocationByteCount,
        "config" to bitmap.config?.name,
    )

    private fun probeImage(file: File): Map<String, Any?>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null

        return mapOf(
            "type" to "IMAGE",
            "mime_type" to (options.outMimeType ?: "application/octet-stream"),
            "width" to options.outWidth,
            "height" to options.outHeight,
            "duration_ms" to null,
            "has_audio" to false,
            "frame_rate" to null,
        )
    }

    private fun probeVideo(file: File): Map<String, Any?>? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)

            val width = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
            )?.toIntOrNull()
            val height = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
            )?.toIntOrNull()
            val duration = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION,
            )?.toLongOrNull()

            if ((width ?: 0) <= 0 || (height ?: 0) <= 0 || (duration ?: 0L) <= 0L) {
                null
            } else {
                mapOf(
                    "type" to "VIDEO",
                    "mime_type" to (
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
                            ?: "application/octet-stream"
                        ),
                    "width" to width,
                    "height" to height,
                    "duration_ms" to duration,
                    "has_audio" to (
                        retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
                        ),
                    "frame_rate" to retriever.extractMetadata(
                        MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE,
                    )?.toDoubleOrNull(),
                )
            }
        } catch (_: RuntimeException) {
            null
        } finally {
            retriever.release()
        }
    }
}
