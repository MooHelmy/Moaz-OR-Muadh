package com.example.muadh

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.MediaStore
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class MaadhAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "MaadhAccessibility"

        private val MEDIA_EXTENSIONS = setOf(
            "jpg", "jpeg", "png", "webp", "gif", "bmp",
            "mp4", "mkv", "avi", "mov", "3gp", "webm"
        )

        // تجاهل التطبيق نفسه + system UI + keyboards
        private val IGNORED_PACKAGES = setOf(
            "com.example.muadh",
            "com.android.systemui",
            "com.google.android.inputmethod.latin",
            "com.samsung.android.honeyboard",
            "com.swiftkey.swiftkeyapp"
        )

        private const val DEDUP_TTL_MS = 30_000L
    }

    // dedup: path → آخر وقت بعتناه
    private val recentlySent = LinkedHashMap<String, Long>()
    private var lastSeenFileName: String? = null

    // fallback: آخر وقت استخدمنا فيه الـ MediaStore fallback
    private var lastFallbackMs: Long = 0L
    // آخر package شفناه — عشان نعرف لما التطبيق اتغير
    private var lastActivePackage: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "✅ Accessibility Service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg in IGNORED_PACKAGES) return

        // ─── وظيفة 1: الكلمات المحظورة ───────────────────────────────────────
        handleBlacklist(event)

        // ─── وظيفة 2: كشف الملفات المفتوحة ──────────────────────────────────
        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return

        val root = rootInActiveWindow ?: return
        try {
            val found = findMediaFileName(root)
            if (found != null) {
                // ✅ المسار الرئيسي: لقينا اسم الملف في الـ node tree
                if (found == lastSeenFileName) return
                lastSeenFileName = found
                resolveAndSend(found)
            } else {
                // ✅ Fallback: مش لاقيين اسم الملف في الـ node tree
                // بنسأل MediaStore عن آخر ملف اتضاف/اتعدّل في آخر 3 ثواني
                // بنستخدمه بس لو:
                //   1. التطبيق اتغير (package جديد) — يعني المستخدم فتح حاجة جديدة
                //   2. أو مرت 10 ثواني من آخر fallback — منقفلش التطبيق
                val now = System.currentTimeMillis()
                val packageChanged = pkg != lastActivePackage
                val timeoutPassed  = now - lastFallbackMs > 10_000L

                if (packageChanged || timeoutPassed) {
                    lastActivePackage = pkg
                    lastFallbackMs    = now
                    queryRecentMedia(withinMs = 3000L)?.let { path ->
                        resolveAndSend(path, isFullPath = true)
                    }
                }
            }
        } finally {
            root.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  findMediaFileName — BFS على الـ node tree
    // ══════════════════════════════════════════════════════════════════════════
    private fun findMediaFileName(root: AccessibilityNodeInfo): String? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)

        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()

            listOf(node.text?.toString(), node.contentDescription?.toString())
                .forEach { text ->
                    if (!text.isNullOrBlank()) {
                        val fileName = extractMediaFileName(text)
                        if (fileName != null) {
                            queue.forEach { it.recycle() }
                            return fileName
                        }
                    }
                }

            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  extractMediaFileName — يشيل اسم الملف من أي نص
    // ══════════════════════════════════════════════════════════════════════════
    private fun extractMediaFileName(text: String): String? {
        val parts = text.trim().split("/", "\\", " ")
        for (part in parts.reversed()) {
            val lower = part.lowercase()
            val dotIdx = lower.lastIndexOf('.')
            if (dotIdx < 1) continue
            val ext = lower.substring(dotIdx + 1)
            if (ext in MEDIA_EXTENSIONS) return part
        }
        return null
    }



    // ══════════════════════════════════════════════════════════════════════════
    //  queryMediaStore — بيجيب الـ full path باسم الملف
    // ══════════════════════════════════════════════════════════════════════════
    private fun queryMediaStore(fileName: String): String? {
        val uri: Uri    = MediaStore.Files.getContentUri("external")
        val projection  = arrayOf(MediaStore.Files.FileColumns.DATA)
        val selection   = "${MediaStore.Files.FileColumns.DISPLAY_NAME} = ?"
        val args        = arrayOf(fileName)
        val sortOrder   = "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC LIMIT 1"

        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, projection, selection, args, sortOrder)
            if (cursor != null && cursor.moveToFirst()) {
                val col = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                if (col >= 0) cursor.getString(col) else null
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "❌ MediaStore query error: ${e.message}")
            null
        } finally {
            cursor?.close()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  resolveAndSend overload — لو عندنا full path مباشرة (من fallback)
    // ══════════════════════════════════════════════════════════════════════════
    private fun resolveAndSend(input: String, isFullPath: Boolean = false) {
        val path = if (isFullPath) input else (queryMediaStore(input) ?: run {
            Log.d(TAG, "⚠️ مش موجود في MediaStore: $input")
            return
        })

        val now = System.currentTimeMillis()
        val lastSent = recentlySent[path]
        if (lastSent != null && now - lastSent < DEDUP_TTL_MS) {
            Log.d(TAG, "⏭️ dedup skip: ${path.substringAfterLast('/')}")
            return
        }

        recentlySent.entries.removeIf { now - it.value > DEDUP_TTL_MS }
        if (recentlySent.size > 200) recentlySent.remove(recentlySent.keys.first())
        recentlySent[path] = now

        Log.d(TAG, "📤 إرسال للفحص: $path")
        sendBroadcast(Intent("com.maadh.shield.SCAN_FILE").apply {
            putExtra("path", path)
        })
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  queryRecentMedia — Fallback
    //  بيجيب آخر ملف ميديا اتضاف أو اتعدّل في آخر X milliseconds
    //  بنستخدمه لما الـ node tree مش بيحتوي على اسم الملف
    // ══════════════════════════════════════════════════════════════════════════
    private fun queryRecentMedia(withinMs: Long): String? {
        val sinceSeconds = (System.currentTimeMillis() - withinMs) / 1000
        val uri          = android.provider.MediaStore.Files.getContentUri("external")
        val projection   = arrayOf(android.provider.MediaStore.Files.FileColumns.DATA)
        val selection    = (
            "${android.provider.MediaStore.Files.FileColumns.MEDIA_TYPE} IN " +
            "(${android.provider.MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}," +
            "${android.provider.MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}) " +
            "AND ${android.provider.MediaStore.Files.FileColumns.DATE_MODIFIED} >= ?"
        )
        val args      = arrayOf(sinceSeconds.toString())
        val sortOrder = "${android.provider.MediaStore.Files.FileColumns.DATE_MODIFIED} DESC LIMIT 1"

        var cursor: android.database.Cursor? = null
        return try {
            cursor = contentResolver.query(uri, projection, selection, args, sortOrder)
            if (cursor != null && cursor.moveToFirst()) {
                val col = cursor.getColumnIndex(android.provider.MediaStore.Files.FileColumns.DATA)
                if (col >= 0) cursor.getString(col) else null
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "❌ queryRecentMedia error: ${e.message}")
            null
        } finally {
            cursor?.close()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  handleBlacklist — الكلمات المحظورة (موجودة قبل كده)
    // ══════════════════════════════════════════════════════════════════════════
    private fun handleBlacklist(event: AccessibilityEvent) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val blacklistString = prefs.getString("flutter.ai_blacklist", "") ?: ""
        if (blacklistString.isEmpty()) return

        val blacklist = blacklistString
            .split(",")
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }

        val root = rootInActiveWindow ?: return
        try {
            scanNodeForBlacklist(root, blacklist)
        } finally {
            root.recycle()
        }
    }

    private fun scanNodeForBlacklist(node: AccessibilityNodeInfo, blacklist: List<String>) {
        node.text?.toString()?.lowercase()?.let { text ->
            for (word in blacklist) {
                if (text.contains(word)) {
                    Log.d(TAG, "🚫 كلمة محظورة: $word")
                    saveBlockLog(word)
                    sendBroadcast(Intent("com.maadh.shield.BLOCKED_EVENT").apply {
                        putExtra("word", word)
                    })
                    performGlobalAction(GLOBAL_ACTION_HOME)
                    return
                }
            }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            scanNodeForBlacklist(child, blacklist)
            child.recycle()
        }
    }

    private fun saveBlockLog(word: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val current = prefs.getString("flutter.shield_logs", "") ?: ""
        val entry   = "$word|${System.currentTimeMillis()}|false"
        val updated = if (current.isEmpty()) entry else "$current;$entry"
        prefs.edit().putString("flutter.shield_logs", updated).apply()
    }

    override fun onInterrupt() {}
}