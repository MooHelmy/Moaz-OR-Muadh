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

        private val IGNORED_PACKAGES = setOf(
            "com.example.muadh",
            "com.android.systemui",
            "com.google.android.inputmethod.latin",
            "com.samsung.android.honeyboard",
            "com.swiftkey.swiftkeyapp"
        )

        private const val DEDUP_TTL_MS = 30_000L
        private const val SHORT_WORD_MIN_LENGTH = 5

        // ─── تطبيقات المحادثات ────────────────────────────────────────────────
        // فيها تسامح — الكلمة لازم تتكرر أو تيجي مع كلمة تانية
        private val CHAT_PACKAGES = setOf(
            "com.whatsapp",
            "com.whatsapp.w4b",
            "com.facebook.orca",       // Messenger
            "org.telegram.messenger",
            "org.telegram.plus",
            "com.instagram.android",
            "com.twitter.android",
            "com.snapchat.android",
            "com.viber.voip",
            "com.skype.raider",
            "com.discord",
            "com.tencent.mm",          // WeChat
            "jp.naver.line.android",   // Line
        )

        // نافذة المحادثات: 60 ثانية
        private const val CHAT_WINDOW_MS = 60_000L
    }

    private val recentlySent = LinkedHashMap<String, Long>()
    private var lastSeenFileName: String? = null
    private var lastFallbackMs: Long = 0L
    private var lastActivePackage: String? = null

    // ─── Chat context tracking ────────────────────────────────────────────────
    private val chatWordHistory = HashMap<String, MutableList<Pair<String, Long>>>()

    // ─── Blacklist cache — بيتبنى مرة واحدة لما القائمة تتغير ───────────────
    // longWords  → HashSet: بحث O(1) بدل O(n)
    // shortWords → List:    محتاجين regex عليهم
    private var cachedBlacklistStr = ""
    private var longWordsSet  = HashSet<String>()  // كلمات >= 5 حروف
    private var shortWordsList = listOf<String>()   // كلمات < 5 حروف

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "✅ تم تشغيل خدمة الحارس الذكي بنجاح")
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
                if (found == lastSeenFileName) return
                lastSeenFileName = found
                resolveAndSend(found)
            } else {
                val now = System.currentTimeMillis()
                val packageChanged = pkg != lastActivePackage
                val timeoutPassed = now - lastFallbackMs > 10_000L
                if (packageChanged || timeoutPassed) {
                    lastActivePackage = pkg
                    lastFallbackMs = now
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
    //  handleBlacklist — بيفرق بين المحادثات وباقي التطبيقات
    //
    //  المحادثات (WhatsApp, Telegram, إلخ):
    //    كلمة مرة واحدة          → تجاهل
    //    نفس الكلمة مرتين/60ث    → إقفال
    //    كلمتين مختلفتين/60ث     → إقفال
    //
    //  باقي التطبيقات والمتصفحات:
    //    أي كلمة → إقفال فوري
    // ══════════════════════════════════════════════════════════════════════════
    private fun handleBlacklist(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val blacklistString = prefs.getString("flutter.ai_blacklist", "") ?: ""
        if (blacklistString.isEmpty()) return

        // ─── أعد بناء الـ cache بس لو القائمة اتغيرت ────────────────────────
        // بدل ما نعمل split وmap في كل event
        if (blacklistString != cachedBlacklistStr) {
            val all = blacklistString
                .split(",")
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
            longWordsSet  = HashSet(all.filter { it.length >= SHORT_WORD_MIN_LENGTH })
            shortWordsList = all.filter { it.length < SHORT_WORD_MIN_LENGTH }
            cachedBlacklistStr = blacklistString
        }

        if (longWordsSet.isEmpty() && shortWordsList.isEmpty()) return

        // بناء قائمة موحدة للـ scan
        val blacklist = longWordsSet.toList() + shortWordsList

        val root = rootInActiveWindow ?: return
        try {
            // جمّع كل الكلمات المحظورة الموجودة على الشاشة دلوقتي
            val foundWords = mutableSetOf<String>()
            collectBlockedWords(root, blacklist, foundWords)

            if (foundWords.isEmpty()) return

            val isChat = pkg in CHAT_PACKAGES

            if (!isChat) {
                // ─── باقي التطبيقات → إقفال فوري ──────────────────────────
                val word = foundWords.first()
                Log.d(TAG, "🚫 [فوري] $word في $pkg")
                triggerBlock(word)
                return
            }

            // ─── تطبيق محادثة → نظام التتبع ──────────────────────────────
            val now = System.currentTimeMillis()
            val history = chatWordHistory.getOrPut(pkg) { mutableListOf() }

            // أضف الكلمات الجديدة للـ history
            for (word in foundWords) {
                history.add(Pair(word, now))
            }

            // احذف الـ entries القديمة (أكتر من 60 ثانية)
            history.removeIf { now - it.second > CHAT_WINDOW_MS }

            // شوف عدد الكلمات الفريدة في آخر 60 ثانية
            val uniqueWords = history.map { it.first }.toSet()
            val totalOccurrences = history.size

            val shouldBlock = when {
                // كلمة واحدة تكررت مرتين أو أكتر
                uniqueWords.size == 1 && totalOccurrences >= 2 -> true
                // كلمتين مختلفتين أو أكتر
                uniqueWords.size >= 2 -> true
                else -> false
            }

            if (shouldBlock) {
                val word = uniqueWords.first()
                Log.d(TAG, "🚫 [محادثة] $word تكررت ${totalOccurrences}x في $pkg")
                chatWordHistory.remove(pkg) // reset بعد الإقفال
                triggerBlock(word)
            } else {
                Log.d(TAG, "⏳ [محادثة] ${foundWords.first()} مرة واحدة في $pkg — انتظار")
            }

        } finally {
            root.recycle()
        }
    }

    private fun collectBlockedWords(
        node: AccessibilityNodeInfo,
        blacklist: List<String>,
        found: MutableSet<String>
    ) {
        node.text?.toString()?.lowercase()?.let { text ->
            // ─── الكلمات الطويلة: O(1) بحث مباشر في الـ HashSet ─────────────
            // بدل loop على كل الكلمات، بنقسم النص لكلمات ونشوف لو أي منها
            // موجودة في الـ HashSet
            val textWords = text.split(Regex("[\\s\\p{Punct}]+"))
            for (textWord in textWords) {
                if (textWord.isNotEmpty() && longWordsSet.contains(textWord)) {
                    found.add(textWord)
                }
            }
            // كمان بنشوف الـ substrings للكلمات الطويلة المركبة زي "xvideos.com"
            for (word in longWordsSet) {
                if (text.contains(word) && !found.contains(word)) {
                    found.add(word)
                }
            }

            // ─── الكلمات القصيرة: regex word boundary (قائمة صغيرة) ─────────
            for (word in shortWordsList) {
                if (matchesWord(text, word)) {
                    found.add(word)
                }
            }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectBlockedWords(child, blacklist, found)
            child.recycle()
        }
    }

    private fun triggerBlock(word: String) {
        saveBlockLog(word)
        sendBroadcast(Intent("com.maadh.shield.BLOCKED_EVENT").apply {
            putExtra("word", word)
        })

        // الخطوة 1: ارجع للهوم فوراً
        performGlobalAction(GLOBAL_ACTION_HOME)

        // الخطوة 2: بعد 400ms افتح الـ recents
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            performGlobalAction(GLOBAL_ACTION_RECENTS)

            // الخطوة 3: بعد 500ms دور على الـ task وامسحه
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                dismissBlockedTask()
            }, 500)
        }, 400)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  dismissBlockedTask
    //  بيمسح التطبيق المحظور من شاشة الـ recents
    //  المنطق:
    //    1. نفتش في الـ recents عن زرار "مسح الكل" / "Clear all"
    //    2. لو مش لاقيه نعمل swipe dismiss على أول task
    //    3. في الآخر نرجع للهوم
    // ══════════════════════════════════════════════════════════════════════════
    private fun dismissBlockedTask() {
        val root = rootInActiveWindow ?: run {
            performGlobalAction(GLOBAL_ACTION_HOME)
            return
        }

        try {
            // ─── محاولة 1: دور على زرار "مسح الكل" ─────────────────────────
            // بيختلف من جهاز لجهاز: "Clear all", "CLEAR ALL", "مسح الكل"
            val clearKeywords = listOf(
                "clear all", "clear", "مسح الكل", "مسح", "dismiss all",
                "close all", "end all"
            )

            val clearButton = findNodeByText(root, clearKeywords)
            if (clearButton != null) {
                clearButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                clearButton.recycle()
                android.util.Log.d(TAG, "✅ ضغطنا على 'مسح الكل'")
            } else {
                // ─── محاولة 2: دور على زرار X أو dismiss على الـ card ──────
                val dismissButton = findDismissButton(root)
                if (dismissButton != null) {
                    dismissButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    dismissButton.recycle()
                    android.util.Log.d(TAG, "✅ ضغطنا على زرار الإغلاق")
                } else {
                    // ─── محاولة 3: swipe فوق على أول task card ────────────
                    val taskCard = findTaskCard(root)
                    if (taskCard != null) {
                        taskCard.performAction(AccessibilityNodeInfo.ACTION_DISMISS)
                        taskCard.recycle()
                        android.util.Log.d(TAG, "✅ عملنا dismiss على الـ task")
                    }
                }
            }
        } finally {
            root.recycle()
        }

        // ارجع للهوم في الآخر
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            performGlobalAction(GLOBAL_ACTION_HOME)
        }, 300)
    }

    // دور على node بنصه
    private fun findNodeByText(
        root: AccessibilityNodeInfo,
        keywords: List<String>
    ): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            val text = node.text?.toString()?.lowercase() ?: ""
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
            if (keywords.any { text.contains(it) || desc.contains(it) }) {
                queue.forEach { it.recycle() }
                return node
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    // دور على زرار X أو dismiss في الـ recents
    private fun findDismissButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
            val text = node.text?.toString()?.lowercase() ?: ""
            // بيدور على زرار الـ X أو dismiss
            if ((desc.contains("dismiss") || desc.contains("close") ||
                 desc.contains("remove") || text == "×" || text == "x") &&
                node.isClickable) {
                queue.forEach { it.recycle() }
                return node
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    // دور على الـ task card الأولى في الـ recents
    private fun findTaskCard(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            // الـ task cards عادةً بتكون dismissable
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
    //  matchesWord — المنطق الأساسي
    //
    //  كلمة قصيرة (< 5 حروف): word boundary
    //    "sex" ✅ "sex video"  ❌ "Essex"  ❌ "sexuality"
    //    "nu"  ✅ "nu model"   ❌ "continue" ❌ "menu"
    //
    //  كلمة طويلة (>= 5 حروف): contains عادي
    //    "porno" ✅ "pornography"
    //    "xvideos" ✅ "xvideos.com"
    // ══════════════════════════════════════════════════════════════════════════
    private fun matchesWord(text: String, word: String): Boolean {
        if (word.length >= SHORT_WORD_MIN_LENGTH) {
            return text.contains(word)
        }
        // word boundary — مش مسبوق أو متبوع بحرف عربي أو إنجليزي
        val escaped = Regex.escape(word)
        val pattern = Regex(
            "(?<![a-zA-Z\\u0600-\\u06FF])$escaped(?![a-zA-Z\\u0600-\\u06FF])",
            RegexOption.IGNORE_CASE
        )
        return pattern.containsMatchIn(text)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  findMediaFileName
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
    //  resolveAndSend
    // ══════════════════════════════════════════════════════════════════════════
    private fun resolveAndSend(input: String, isFullPath: Boolean = false) {
        val path = if (isFullPath) input else (queryMediaStore(input) ?: return)
        val now = System.currentTimeMillis()
        val lastSent = recentlySent[path]
        if (lastSent != null && now - lastSent < DEDUP_TTL_MS) return
        recentlySent.entries.removeIf { now - it.value > DEDUP_TTL_MS }
        if (recentlySent.size > 200) recentlySent.remove(recentlySent.keys.first())
        recentlySent[path] = now
        Log.d(TAG, "📤 إرسال للفحص: $path")
        sendBroadcast(Intent("com.maadh.shield.SCAN_FILE").apply {
            putExtra("path", path)
        })
    }

    private fun queryMediaStore(fileName: String): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(MediaStore.Files.FileColumns.DATA),
                "${MediaStore.Files.FileColumns.DISPLAY_NAME} = ?",
                arrayOf(fileName),
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC LIMIT 1"
            )
            if (cursor != null && cursor.moveToFirst()) {
                val col = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                if (col >= 0) cursor.getString(col) else null
            } else null
        } catch (e: Exception) { null } finally { cursor?.close() }
    }

    private fun queryRecentMedia(withinMs: Long): String? {
        val sinceSeconds = (System.currentTimeMillis() - withinMs) / 1000
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(MediaStore.Files.FileColumns.DATA),
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN " +
                "(${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}," +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}) " +
                "AND ${MediaStore.Files.FileColumns.DATE_MODIFIED} >= ?",
                arrayOf(sinceSeconds.toString()),
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC LIMIT 1"
            )
            if (cursor != null && cursor.moveToFirst()) {
                val col = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                if (col >= 0) cursor.getString(col) else null
            } else null
        } catch (e: Exception) { null } finally { cursor?.close() }
    }

    private fun saveBlockLog(word: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val current = prefs.getString("flutter.shield_logs", "") ?: ""
        val entry = "$word|${System.currentTimeMillis()}|false"
        prefs.edit().putString("flutter.shield_logs",
            if (current.isEmpty()) entry else "$current;$entry").apply()
    }

    override fun onInterrupt() {}
}