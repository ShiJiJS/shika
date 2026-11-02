package io.github.shijijs.video_viewer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Only explicit SAF selection can touch an external file. Channel payloads
 * contain private paths and scalar metadata, never a whole backup byte array. */
class BackupFileBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        private const val PICK = 0x5641
        private const val SAVE = 0x5642
        private const val MAXIMUM = 256L * 1024 * 1024
    }
    private class Job(val id: String, val result: MethodChannel.Result, val saving: Boolean) {
        val cancelled = AtomicBoolean(false)
        val replied = AtomicBoolean(false)
        val signal = CancellationSignal()
        @Volatile var input: Closeable? = null
        @Volatile var output: Closeable? = null
        var chooser = false
        var directory: File? = null
        var source: File? = null
        var bytes = 0L
        var hash = ""
        var owner = ""
        var partial: File? = null
        var complete: File? = null
        var created: Uri? = null
    }
    private val worker = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "video_viewer/backup_files")
    private var current: Job? = null
    private var detached = false

    init { channel.setMethodCallHandler { call, result -> handle(call, result) } }

    private fun ownFile(path: String): File {
        val file = File(path).canonicalFile
        val roots = listOf(activity.filesDir.canonicalFile, activity.cacheDir.canonicalFile)
        require(roots.any { file.path.startsWith(it.path + File.separator) })
        return file
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            current?.takeIf { it.id == call.argument<String>("id") }?.let { cancel(it) }
            result.success(null)
            return
        }
        if (call.method !in listOf("pick", "save")) { result.notImplemented(); return }
        if (detached || current != null) { result.error("BACKUP_BUSY", "请先关闭当前文件选择", null); return }
        var job: Job? = null
        try {
            val id = call.argument<String>("id") ?: error("Missing identity")
            require(id.matches(Regex("[a-f0-9]{32}")))
            job = Job(id, result, call.method == "save")
            if (job.saving) {
                job.source = ownFile(call.argument<String>("path") ?: error("Missing source"))
                job.bytes = call.argument<Number>("bytes")?.toLong() ?: 0
                job.hash = call.argument<String>("sha256") ?: ""
                require(job.bytes in 1..MAXIMUM && job.hash.matches(Regex("[a-f0-9]{64}")))
                val name = call.argument<String>("name") ?: "video-viewer-backup.vvbackup"
                require(name.length in 1..128 && !name.contains('/') && !name.contains('\\'))
                current = job
                work(job, {
                    verifySource(job)
                    null
                }, {
                    chooser(job, Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, SAVE)
                })
            } else {
                job.directory = ownFile(call.argument<String>("directory") ?: error("Missing directory"))
                job.owner = call.argument<String>("owner") ?: error("Missing owner")
                require(job.owner.isNotEmpty() && job.owner.length <= 8192)
                job.bytes = call.argument<Number>("maximumBytes")?.toLong() ?: 0
                require(job.bytes in 1..MAXIMUM)
                current = job
                chooser(job, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }, PICK)
            }
        } catch (_: Exception) {
            job?.let { if (current === it) current = null }
            result.error("BACKUP_FILE_INVALID", "备份文件信息不完整或本机文件不可用", null)
        }
    }

    private fun chooser(job: Job, intent: Intent, code: Int) {
        if (current !== job || job.cancelled.get() || detached) { cleanup(job); return }
        try {
            job.chooser = true
            activity.startActivityForResult(intent, code)
        } catch (_: Exception) {
            job.chooser = false
            finish(job, null, "无法打开系统文件选择器")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK && requestCode != SAVE) return false
        val job = current ?: return true
        if (!job.chooser || job.saving != (requestCode == SAVE)) return true
        job.chooser = false
        if (job.cancelled.get() || resultCode != Activity.RESULT_OK || data?.data == null) {
            if (job.cancelled.get() && job.saving && resultCode == Activity.RESULT_OK) {
                job.created = data?.data
                cleanup(job)
            }
            finish(job, null)
            return true
        }
        val uri = data.data!!
        if (uri.scheme != "content") {
            finish(job, null, "系统未返回可读取的文件")
            return true
        }
        if (job.saving) job.created = uri
        work(job, { if (job.saving) save(job, uri) else pick(job, uri) }) { value -> finish(job, value) }
        return true
    }

    private fun check(job: Job) { check(!job.cancelled.get()) { "Cancelled" } }
    private fun close(stream: Closeable?) { try { stream?.close() } catch (_: Exception) {} }
    private fun digest(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun copy(job: Job, input: InputStream, output: OutputStream?, maximum: Long): Pair<Long, String> {
        val hash = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        var bytes = 0L
        job.input = input
        job.output = output
        while (true) {
            check(job)
            val count = input.read(buffer)
            if (count < 0) break
            if (count == 0) continue
            bytes += count
            require(bytes <= maximum) { "Too large" }
            hash.update(buffer, 0, count)
            output?.write(buffer, 0, count)
        }
        check(job)
        require(bytes > 0)
        output?.flush()
        return Pair(bytes, digest(hash.digest()))
    }

    private fun verifySource(job: Job) {
        val file = job.source ?: error("Missing source")
        require(file.isFile && file.length() == job.bytes)
        val originalTime = file.lastModified()
        val actual = FileInputStream(file).use { copy(job, it, null, job.bytes) }
        require(actual.first == job.bytes && actual.second == job.hash && file.lastModified() == originalTime)
    }

    private fun pick(job: Job, uri: Uri): Map<String, Any> {
        val directory = job.directory ?: error("Missing directory")
        require(directory.isDirectory || directory.mkdirs())
        val id = UUID.randomUUID().toString().replace("-", "")
        val partial = File(directory, "$id.part").also { job.partial = it }
        val complete = File(directory, "$id.vvbackup").also { job.complete = it }
        require(partial.createNewFile() && !complete.exists())
        val descriptor = activity.contentResolver.openFileDescriptor(uri, "r", job.signal) ?: error("Cannot open")
        val actual = ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
            FileOutputStream(partial).use { output ->
                copy(job, input, output, job.bytes).also { output.fd.sync() }
            }
        }
        check(job)
        require(partial.renameTo(complete))
        check(job)
        return mapOf("id" to id, "owner" to job.owner, "bytes" to actual.first, "sha256" to actual.second)
    }

    private fun save(job: Job, uri: Uri): Boolean {
        verifySource(job)
        val descriptor = activity.contentResolver.openFileDescriptor(uri, "w", job.signal) ?: error("Cannot save")
        val actual = ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
            FileInputStream(job.source!!).use { input -> copy(job, input, output, job.bytes) }.also {
                // Pipe-backed/cloud providers need not implement fsync. Closing
                // still reports their write errors; regular descriptors sync.
                try { descriptor.fileDescriptor.sync() } catch (error: java.io.SyncFailedException) {
                    if (descriptor.statSize >= 0) throw error
                }
            }
        }
        check(job)
        require(actual.first == job.bytes && actual.second == job.hash)
        return true
    }

    private fun work(job: Job, action: () -> Any?, success: (Any?) -> Unit) {
        worker.execute {
            try {
                val value = action()
                activity.runOnUiThread {
                    if (current === job && !job.cancelled.get() && !detached) success(value)
                    else cleanup(job)
                }
            } catch (_: Exception) {
                cleanup(job)
                activity.runOnUiThread { finish(job, null, "文件读取、大小或完整性核对失败，原备份任务已保留") }
            } finally {
                close(job.input); close(job.output)
                job.input = null; job.output = null
            }
        }
    }

    private fun cleanup(job: Job) {
        job.partial?.delete()
        job.complete?.delete()
        job.created?.let { uri ->
            try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) {}
        }
    }

    private fun finish(job: Job, value: Any?, message: String? = null) {
        if (current === job) current = null
        if (!job.replied.compareAndSet(false, true)) return
        if (job.cancelled.get() || message == null) job.result.success(if (job.cancelled.get()) null else value)
        else job.result.error("BACKUP_FILE_IO", message, null)
    }

    private fun cancel(job: Job) {
        job.cancelled.set(true)
        try { job.signal.cancel() } catch (_: Exception) {}
        close(job.input); close(job.output)
        // Keep the chooser's cancelled identity until its result arrives. A late
        // result must never be attached to a newly opened file request.
        if (job.chooser) {
            if (job.replied.compareAndSet(false, true)) job.result.success(null)
            activity.finishActivity(if (job.saving) SAVE else PICK)
        } else finish(job, null)
    }

    fun detach() {
        detached = true
        current?.let { cancel(it); cleanup(it) }
        current = null
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }
}
