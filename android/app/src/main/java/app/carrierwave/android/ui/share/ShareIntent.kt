package app.carrierwave.android.ui.share

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.core.content.FileProvider
import app.carrierwave.android.util.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/**
 * Shared share-intent plumbing extracted from the brag-sheet flow (Task 9) so
 * the activation share card (Task 11) reuses the exact same FileProvider write +
 * `ACTION_SEND` chooser rather than re-implementing them.
 *
 * `app.carrierwave.android.fileprovider` (declared in `AndroidManifest.xml`,
 * paths in `res/xml/file_paths.xml`) exposes `cacheDir/share/`.
 */

/**
 * Writes [bitmap] as a PNG under `cacheDir/share/[fileName]` and returns a
 * `content://` URI for it via [FileProvider]. Runs on [Dispatchers.IO] — file
 * I/O must not touch the main thread. Returns null (and logs) on any failure
 * rather than throwing, so the caller can show an inline error instead of
 * crashing the share flow.
 */
suspend fun writeShareBitmap(context: Context, bitmap: Bitmap, fileName: String): Uri? =
    withContext(Dispatchers.IO) {
        try {
            val shareDir = File(context.cacheDir, "share").apply { mkdirs() }
            val file = File(shareDir, fileName)
            FileOutputStream(file).use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out) }
            FileProvider.getUriForFile(context, "app.carrierwave.android.fileprovider", file)
        } catch (e: Exception) {
            AppLog.add(AppLog.Level.ERROR, "share: failed to write image: ${e.message}")
            null
        }
    }

/**
 * Writes [bytes] as [fileName] under `cacheDir/share/` and returns a
 * `content://` URI via [FileProvider]. The text/binary analog of
 * [writeShareBitmap] — used for the ADIF export ([shareTextFileUri]). Runs on
 * [Dispatchers.IO]; returns null (and logs) on failure.
 */
suspend fun writeShareBytes(context: Context, bytes: ByteArray, fileName: String): Uri? =
    withContext(Dispatchers.IO) {
        try {
            val shareDir = File(context.cacheDir, "share").apply { mkdirs() }
            val file = File(shareDir, fileName)
            FileOutputStream(file).use { out -> out.write(bytes) }
            FileProvider.getUriForFile(context, "app.carrierwave.android.fileprovider", file)
        } catch (e: Exception) {
            AppLog.add(AppLog.Level.ERROR, "share: failed to write file: ${e.message}")
            null
        }
    }

/**
 * Fires an `ACTION_SEND` chooser for the PNG at [uri]. [context] should be the
 * hosting Activity — no `FLAG_ACTIVITY_NEW_TASK` is needed. `clipData` is set
 * explicitly (belt-and-braces alongside `EXTRA_STREAM` +
 * `FLAG_GRANT_READ_URI_PERMISSION`) so the URI grant is unambiguous for chooser
 * targets that read `clipData` instead of the stream extra.
 */
fun shareBitmapUri(context: Context, uri: Uri, chooserTitle: String) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "image/png"
        putExtra(Intent.EXTRA_STREAM, uri)
        clipData = ClipData.newUri(context.contentResolver, chooserTitle, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(sendIntent, chooserTitle))
}

/**
 * Fires an `ACTION_SEND` chooser for the ADIF file at [uri]. iOS shares ADIF as
 * a `.adi` document; there is no registered ADIF MIME, so we advertise
 * `application/octet-stream` (a generic binary) which every mail/drive/messaging
 * target accepts as an attachment — a specific `text/x-adif` would be filtered
 * out by many chooser targets that don't recognize it.
 */
fun shareTextFileUri(context: Context, uri: Uri, chooserTitle: String) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "application/octet-stream"
        putExtra(Intent.EXTRA_STREAM, uri)
        clipData = ClipData.newUri(context.contentResolver, chooserTitle, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(sendIntent, chooserTitle))
}
