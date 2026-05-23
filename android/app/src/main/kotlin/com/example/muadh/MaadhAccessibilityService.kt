package com.example.muadh

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.database.Cursor
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

        private val IGNORED_PACKAGES = setOf(
            "com.example.muadh",
            "com.android.systemui",
            "com.google.android.inputmethod.latin",
            "com.samsung.android.honeyboard",
            "com.swiftkey.swiftkeyapp"
        )

        // ─── تطبيقات المحادثات — متلمسهاش خالص ──────────────────────────────
        // هي كده كده بتتراقب عن طريق فولدرات الميديا
        private val IGNORED_CHAT_PACKAGES = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b",
            "com.facebook.orca",
            "org.telegram.messenger",
            "org.telegram.plus",
            "com.instagram.android",
        )

        private const val DEDUP_TTL_MS         = 30_000L
        private const val SHORT_WORD_MIN_LENGTH = 5
        private const val BLOCK_COOLDOWN_MS     = 10_000L
    }

    // ─── Media ────────────────────────────────────────────────────────────────
    private val recentlySent      = LinkedHashMap<String, Long>()
    private var lastSeenFileName  : String? = null
    private var lastFallbackMs    : Long    = 0L
    private var lastActivePackage : String? = null

    // ─── Blacklist cache ──────────────────────────────────────────────────────
    private var cachedBlacklistStr = ""
    private var longWordsSet       = HashSet<String>()
    private var shortWordsList     = listOf<String>()

    // ─── Block cooldown ───────────────────────────────────────────────────────
    private var lastBlockTimeMs : Long = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "✅ تم تشغيل خدمة الحارس الذكي")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return

        // تجاهل الباكدجات الكاملة
        if (pkg in IGNORED_PACKAGES) return

        // تجاهل تطبيقات المحادثات — بتتراقب بطريقة تانية
        if (pkg in IGNORED_CHAT_PACKAGES) return

        // ─── وظيفة 1: الكلمات المحظورة ───────────────────────────────────────
        handleBlacklist(pkg)

        // ─── وظيفة 2: كشف الملفات المفتوحة ──────────────────────────────────
        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return

        val root = rootInActiveWindow ?: return
        try {
            val found = findMediaFileName(root)
            if (found != null) {
                if (found == lastSeenFileName) return
                lastSeenFileName = found
                resolveAndSend(found)
            } else {
                val now           = System.currentTimeMillis()
                val pkgChanged    = pkg != lastActivePackage
                val timeoutPassed = now - lastFallbackMs > 10_000L
                if (pkgChanged || timeoutPassed) {
                    lastActivePackage = pkg
                    lastFallbackMs    = now
                    queryRecentMedia(3000L)?.let { resolveAndSend(it, isFullPath = true) }
                }
            }
        } finally {
            root.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  handleBlacklist
    //  بس للتطبيقات غير المحادثات — حجب فوري ورجوع للهوم
    // ══════════════════════════════════════════════════════════════════════════
    private fun handleBlacklist(pkg: String) {
        val prefs           = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val blacklistString = prefs.getString("flutter.ai_blacklist", "") ?: ""
        if (blacklistString.isEmpty()) return

        if (blacklistString != cachedBlacklistStr) {
            val all        = blacklistString.split(",").map { it.trim().lowercase() }.filter { it.isNotEmpty() }
            longWordsSet   = HashSet(all.filter { it.length >= SHORT_WORD_MIN_LENGTH })
            shortWordsList = all.filter { it.length < SHORT_WORD_MIN_LENGTH }
            cachedBlacklistStr = blacklistString
        }
        if (longWordsSet.isEmpty() && shortWordsList.isEmpty()) return

        val now = System.currentTimeMillis()
        if (now - lastBlockTimeMs < BLOCK_COOLDOWN_MS) return

        val root = rootInActiveWindow ?: return
        try {
            val found = mutableSetOf<String>()
            collectAllWords(root, found)
            if (found.isNotEmpty()) {
                Log.d(TAG, "🚫 [حجب] ${found.first()} في $pkg")
                triggerBlock(found.first())
            }
        } finally {
            root.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  collectAllWords
    // ══════════════════════════════════════════════════════════════════════════
    private fun collectAllWords(node: AccessibilityNodeInfo, found: MutableSet<String>) {
        node.text?.toString()?.lowercase()?.let { text ->
            for (w in text.split(Regex("[\\s\\p{Punct}،؛؟!]+"))) {
                if (w.isNotEmpty() && longWordsSet.contains(w)) found.add(w)
            }
            for (w in longWordsSet) { if (text.contains(w)) found.add(w) }
            for (w in shortWordsList) { if (matchesWord(text, w)) found.add(w) }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectAllWords(child, found)
            child.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  matchesWord
    // ══════════════════════════════════════════════════════════════════════════
    private fun matchesWord(text: String, word: String): Boolean {
        if (word.length >= SHORT_WORD_MIN_LENGTH) return text.contains(word)
        val escaped = Regex.escape(word)
        return Regex(
            "(?<![a-zA-Z\\u0600-\\u06FF])$escaped(?![a-zA-Z\\u0600-\\u06FF])",
            RegexOption.IGNORE_CASE
        ).containsMatchIn(text)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  triggerBlock
    // ══════════════════════════════════════════════════════════════════════════
    private fun triggerBlock(word: String) {
        lastBlockTimeMs = System.currentTimeMillis()
        saveBlockLog(word)
        sendBroadcast(Intent("com.maadh.shield.BLOCKED_EVENT").apply { putExtra("word", word) })

        performGlobalAction(GLOBAL_ACTION_HOME)

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            performGlobalAction(GLOBAL_ACTION_RECENTS)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                val root = rootInActiveWindow ?: run {
                    performGlobalAction(GLOBAL_ACTION_HOME)
                    return@postDelayed
                }
                try {
                    val card = findFirstDismissable(root)
                    if (card != null) {
                        card.performAction(AccessibilityNodeInfo.ACTION_DISMISS)
                        card.recycle()
                        Log.d(TAG, "✅ تم مسح التطبيق من الـ recents")
                    }
                } finally {
                    root.recycle()
                }
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    performGlobalAction(GLOBAL_ACTION_HOME)
                }, 300)
            }, 600)
        }, 500)
    }

    private fun findFirstDismissable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.isDismissable) {
                queue.forEach { it.recycle() }
                return node
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  Media
    // ══════════════════════════════════════════════════════════════════════════
    private fun findMediaFileName(root: AccessibilityNodeInfo): String? {
        val q = ArrayDeque<AccessibilityNodeInfo>()
        q.add(root)
        while (q.isNotEmpty()) {
            val n = q.removeFirst()
            listOf(n.text?.toString(), n.contentDescription?.toString()).forEach { text ->
                if (!text.isNullOrBlank()) {
                    val fileName = extractMediaFileName(text)
                    if (fileName != null) {
                        q.forEach { it.recycle() }
                        return fileName
                    }
                }
            }
            for (i in 0 until n.childCount) n.getChild(i)?.let { q.add(it) }
        }
        return null
    }

    private fun extractMediaFileName(text: String): String? {
        for (part in text.trim().split("/", "\\", " ").reversed()) {
            val lower = part.lowercase()
            val dot   = lower.lastIndexOf('.')
            if (dot >= 1 && lower.substring(dot + 1) in MEDIA_EXTENSIONS) return part
        }
        return null
    }

    private fun resolveAndSend(input: String, isFullPath: Boolean = false) {
        val path     = if (isFullPath) input else (queryMediaStore(input) ?: return)
        val now      = System.currentTimeMillis()
        val lastSent = recentlySent[path]
        if (lastSent != null && now - lastSent < DEDUP_TTL_MS) return
        recentlySent.entries.removeIf { now - it.value > DEDUP_TTL_MS }
        if (recentlySent.size > 200) recentlySent.remove(recentlySent.keys.first())
        recentlySent[path] = now
        Log.d(TAG, "📤 إرسال للفحص: $path")
        sendBroadcast(Intent("com.maadh.shield.SCAN_FILE").apply { putExtra("path", path) })
    }

    private fun queryMediaStore(fileName: String): String? {
        var c: Cursor? = null
        return try {
            c = contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(MediaStore.Files.FileColumns.DATA),
                "${MediaStore.Files.FileColumns.DISPLAY_NAME} = ?",
                arrayOf(fileName),
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC LIMIT 1"
            )
            if (c != null && c.moveToFirst()) {
                val col = c.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                if (col >= 0) c.getString(col) else null
            } else null
        } catch (e: Exception) { null } finally { c?.close() }
    }

    private fun queryRecentMedia(withinMs: Long): String? {
        val since = (System.currentTimeMillis() - withinMs) / 1000
        var c: Cursor? = null
        return try {
            c = contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(MediaStore.Files.FileColumns.DATA),
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN " +
                "(${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}," +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}) " +
                "AND ${MediaStore.Files.FileColumns.DATE_MODIFIED} >= ?",
                arrayOf(since.toString()),
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC LIMIT 1"
            )
            if (c != null && c.moveToFirst()) {
                val col = c.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                if (col >= 0) c.getString(col) else null
            } else null
        } catch (e: Exception) { null } finally { c?.close() }
    }

    private fun saveBlockLog(word: String) {
        val prefs   = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val current = prefs.getString("flutter.shield_logs", "") ?: ""
        val entry   = "$word|${System.currentTimeMillis()}|false"
        prefs.edit().putString("flutter.shield_logs",
            if (current.isEmpty()) entry else "$current;$entry").apply()
    }

    override fun onInterrupt() {}
}