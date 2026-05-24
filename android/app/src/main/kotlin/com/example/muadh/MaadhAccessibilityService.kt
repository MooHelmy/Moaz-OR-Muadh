package com.example.muadh

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

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

        private val TOLERANT_PACKAGES = setOf(
            "com.whatsapp", "com.whatsapp.w4b",
            "com.facebook.orca",
            "org.telegram.messenger", "org.telegram.plus",
            "com.instagram.android",
            "com.twitter.android",
            "com.snapchat.android",
            "com.viber.voip",
            "com.skype.raider",
            "com.discord",
            "com.tencent.mm",
            "jp.naver.line.android",
            "com.google.android.dialer",
            "com.samsung.android.dialer",
            "com.android.dialer",
            "com.google.android.documentsui",
            "com.samsung.android.myfiles",
            "com.asus.filemanager",
            "com.mi.android.globalFileexplorer",
            "com.huawei.filemanager",
            "com.oppo.filemanager",
            "com.coloros.filemanager",
            "com.realme.filemanager",
            "com.android.fileexplorer",
            "com.es.fileexplorer",
            "com.rhmsoft.fm",
        )

        private const val DEDUP_TTL_MS         = 30_000L
        private const val SHORT_WORD_MIN_LENGTH = 5
        private const val NOTIF_CHANNEL_ID      = "maadh_warnings"
        private const val MAX_STRIKES           = 3
        private const val WORD_REPEAT_THRESHOLD = 3

        // cooldown بين الـ strikes العادية (10 ثواني)
        private const val STRIKE_COOLDOWN_MS    = 10_000L

        // أقصى وقت للمراقبة بعد الحجب قبل reset تلقائي (5 دقائق)
        private const val MAX_WATCH_MS          = 5 * 60_000L

        // فترة polling لفحص الشاشة بعد الحجب (كل ثانية)
        private const val WATCH_INTERVAL_MS     = 1_000L
    }

    private val recentlySent      = LinkedHashMap<String, Long>()
    private var lastSeenFileName  : String? = null
    private var lastFallbackMs    : Long    = 0L
    private var lastActivePackage : String? = null

    private var cachedBlacklistStr = ""
    private var longWordsSet       = HashSet<String>()
    private var shortWordsList     = listOf<String>()

    private var lastStrikeTimeMs : Long    = 0L
    private var lastBlockedPkg   : String? = null

    // Strike system
    private val strikeCount   = HashMap<String, Int>()
    private val lastStrikeDay = HashMap<String, Int>()

    // عداد تكرار الكلمات
    private val wordSeenCount = HashMap<String, Int>()

    // نصوص شفناها
    private val seenMessageTexts = HashMap<String, MutableSet<String>>()

    private val mainHandler = Handler(Looper.getMainLooper())

    // ─── وضع المراقبة بعد الحجب ──────────────────────────────────────────────
    // لما يتم حجب تطبيق محادثة، ندخل "watching mode"
    // بنراقب الشاشة كل ثانية — لما الكلمات تتمسح نعمل reset ونبعت إشعار
    private var watchingPkg       : String?   = null  // التطبيق المراقَب
    private var watchedWords      : Set<String> = emptySet() // الكلمات اللي لازم تتمسح
    private var watchStartMs      : Long      = 0L
    private var watchRunnable     : Runnable? = null
    private var forceResetRunnable: Runnable? = null  // reset إجباري بعد 5 دقائق

    // ══════════════════════════════════════════════════════════════════════════
    override fun onServiceConnected() {
        super.onServiceConnected()
        createNotificationChannel()
        Log.d(TAG, "✅ تم تشغيل خدمة الحارس الذكي")
    }

    // ══════════════════════════════════════════════════════════════════════════
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg in IGNORED_PACKAGES) return

        if (lastBlockedPkg != null &&
            (pkg == "com.android.systemui" ||
             event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED)) {
            tryDismissInRecents()
        }

        if (pkg in TOLERANT_PACKAGES) {
            val type = event.eventType
            if (type == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
                type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                // لو في watching mode وفس التطبيق المراقَب فتح → فحص فوري
                if (watchingPkg == pkg) {
                    checkIfWordsCleared(pkg)
                    return
                }
                checkEntireChat(pkg)
            }
            return
        }

        handleInstantBlock(pkg)

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
    //  startWatchingForClear
    //  بعد الحجب — بتراقب الشاشة كل ثانية
    //  لو الكلمات اتمسحت → reset فوري + إشعار
    //  لو عدت 5 دقائق → reset إجباري
    // ══════════════════════════════════════════════════════════════════════════
    private fun startWatchingForClear(pkg: String, words: Set<String>) {
        // إلغاء أي مراقبة سابقة
        stopWatching()

        watchingPkg   = pkg
        watchedWords  = words
        watchStartMs  = System.currentTimeMillis()

        Log.d(TAG, "👁️ [Watch] بدأ مراقبة مسح الكلمات في $pkg: $words")

        // polling كل ثانية — بيفحص لو المستخدم فتح التطبيق ومسح الكلمات
        watchRunnable = object : Runnable {
            override fun run() {
                if (watchingPkg == null) return
                checkIfWordsCleared(pkg)
                // لو لسه في watching mode → جدول الفحص التالي
                if (watchingPkg != null) {
                    mainHandler.postDelayed(this, WATCH_INTERVAL_MS)
                }
            }
        }
        mainHandler.postDelayed(watchRunnable!!, WATCH_INTERVAL_MS)

        // reset إجباري بعد 5 دقائق لو معمسحش
        forceResetRunnable = Runnable {
            Log.d(TAG, "⏱️ [5min] انتهى وقت المراقبة — reset إجباري لـ $pkg")
            doReset(pkg)
            showWarningNotification(
                id    = 1004,
                title = "✅ يمكنك الرجوع الآن",
                body  = "انتهت مدة الإغلاق. ارجع للمحادثة وتأكد من مسح الكلمات غير اللائقة."
            )
        }
        mainHandler.postDelayed(forceResetRunnable!!, MAX_WATCH_MS)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  checkIfWordsCleared
    //  يقرأ الشاشة الحالية — لو مفيش أي كلمة محظورة من watchedWords → reset
    // ══════════════════════════════════════════════════════════════════════════
    private fun checkIfWordsCleared(pkg: String) {
        val root = rootInActiveWindow ?: return

        // لو التطبيق مش فاتح دلوقتي → مش نعمل حاجة
        val currentPkg = root.packageName?.toString()
        if (currentPkg != pkg) {
            root.recycle()
            return
        }

        try {
            val currentTexts = mutableSetOf<String>()
            collectNonInputTexts(root, currentTexts)

            // فحص لو أي كلمة من watchedWords لسه موجودة
            val allText = currentTexts.joinToString(" ").lowercase()
            val stillPresent = watchedWords.any { word -> allText.contains(word) }

            if (!stillPresent) {
                Log.d(TAG, "✅ [Watch] الكلمات اتمسحت في $pkg — reset")
                doReset(pkg)
                // امسح إشعار الحجب
                NotificationManagerCompat.from(this).cancel(1003)
                // بعت إشعار "تم المسح"
                showWarningNotification(
                    id    = 1004,
                    title = "✅ تم المسح — يمكنك الرجوع",
                    body  = "تم اكتشاف مسح الكلمات غير اللائقة. يمكنك الرجوع للمحادثة."
                )
            } else {
                Log.d(TAG, "👁️ [Watch] الكلمات لسه موجودة في $pkg")
            }
        } finally {
            root.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  doReset — reset كامل لتطبيق معين
    // ══════════════════════════════════════════════════════════════════════════
    private fun doReset(pkg: String) {
        stopWatching()
        strikeCount.remove(pkg)
        seenMessageTexts.remove(pkg)
        wordSeenCount.keys.removeIf { it.startsWith("$pkg|") }
        lastStrikeTimeMs = 0L
        Log.d(TAG, "🔄 [Reset] تم reset $pkg")
    }

    private fun stopWatching() {
        watchRunnable?.let      { mainHandler.removeCallbacks(it) }
        forceResetRunnable?.let { mainHandler.removeCallbacks(it) }
        watchRunnable      = null
        forceResetRunnable = null
        watchingPkg        = null
        watchedWords       = emptySet()
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  checkEntireChat
    // ══════════════════════════════════════════════════════════════════════════
    private fun checkEntireChat(pkg: String) {
        rebuildBlacklistIfNeeded()
        if (longWordsSet.isEmpty() && shortWordsList.isEmpty()) return

        val now = System.currentTimeMillis()
        if (now - lastStrikeTimeMs < STRIKE_COOLDOWN_MS) return

        val root = rootInActiveWindow ?: return
        try {
            val currentTexts = mutableSetOf<String>()
            collectNonInputTexts(root, currentTexts)

            val seen     = seenMessageTexts.getOrPut(pkg) { mutableSetOf() }
            val newTexts = currentTexts - seen

            seen.addAll(currentTexts)
            if (seen.size > 200) {
                val toRemove = seen.take(seen.size - 200)
                seen.removeAll(toRemove.toSet())
            }

            if (newTexts.isEmpty()) return

            for (text in newTexts) {
                val badWords = mutableSetOf<String>()
                findBlockedInText(text.lowercase(), badWords)
                if (badWords.isNotEmpty()) {
                    val word  = badWords.first()
                    val key   = "$pkg|$word"
                    val count = (wordSeenCount[key] ?: 0) + 1
                    wordSeenCount[key] = count

                    Log.d(TAG, "💬 [شات] '$word' ظهرت $count مرة في $pkg")

                    if (count == 1 || count % WORD_REPEAT_THRESHOLD == 0) {
                        processDetectedWord(pkg, word)
                    }
                    break
                }
            }
        } finally {
            root.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  collectNonInputTexts
    // ══════════════════════════════════════════════════════════════════════════
    private fun collectNonInputTexts(node: AccessibilityNodeInfo, texts: MutableSet<String>) {
        val isInput = node.isEditable ||
            node.className?.toString()?.contains("EditText", ignoreCase = true) == true
        if (isInput) return

        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty() && text.length >= 2) texts.add(text)

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectNonInputTexts(child, texts)
            child.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  processDetectedWord
    // ══════════════════════════════════════════════════════════════════════════
    private fun processDetectedWord(pkg: String, word: String) {
        val now = System.currentTimeMillis()
        if (now - lastStrikeTimeMs < STRIKE_COOLDOWN_MS) return

        val today = java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_YEAR)
        if (today != (lastStrikeDay[pkg] ?: -1)) {
            strikeCount.remove(pkg)
            lastStrikeDay[pkg] = today
        }

        val prevStrikes = strikeCount[pkg] ?: 0

        if (prevStrikes >= MAX_STRIKES) {
            Log.d(TAG, "🚫 [حجب] مازال محجوباً '$word' في $pkg")
            triggerChatBlock(pkg, word, now)
            return
        }

        val strikes = prevStrikes + 1
        strikeCount[pkg]   = strikes
        lastStrikeDay[pkg] = today
        lastStrikeTimeMs   = now

        Log.d(TAG, "⚡ [Strike $strikes/$MAX_STRIKES] '$word' في $pkg")

        when (strikes) {
            1 -> showWarningNotification(1001, "⚠️ تحذير 1/3",
                    "تم رصد كلمة غير لائقة في المحادثة.")
            2 -> showWarningNotification(1002, "🚨 تحذير 2/3",
                    "آخر تحذير! المخالفة التالية ستغلق المحادثة.")
            else -> {
                saveBlockLog(word)
                sendBroadcast(Intent("com.maadh.shield.BLOCKED_EVENT").apply {
                    putExtra("word", word)
                })
                triggerChatBlock(pkg, word, now)
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  triggerChatBlock
    //  1. HOME فوراً
    //  2. إشعار "امسح الكلمات"
    //  3. ابدأ مراقبة الشاشة — لما الكلمات تتمسح → reset فوري
    //  4. لو معمسحش في 5 دقائق → reset إجباري
    // ══════════════════════════════════════════════════════════════════════════
    private fun triggerChatBlock(pkg: String, word: String, now: Long) {
        lastStrikeTimeMs = now

        // 1. HOME فوراً
        performGlobalAction(GLOBAL_ACTION_HOME)

        // 2. إشعار ongoing
        val appName = getAppName(pkg)
        showBlockNotification(
            title = "🚫 تم إغلاق $appName",
            body  = "وجدنا كلمات غير لائقة.\nافتح المحادثة وامسح الكلمات — الخدمة ستكتشف المسح تلقائياً."
        )

        // 3. ابدأ المراقبة — اجمع كل الكلمات المحظورة الحالية عشان نراقبها
        val currentBadWords = getCurrentBadWordsOnScreen(pkg)
        val wordsToWatch = if (currentBadWords.isNotEmpty()) currentBadWords else setOf(word)
        startWatchingForClear(pkg, wordsToWatch)
    }

    // يجمع كل الكلمات المحظورة الموجودة حالياً على الشاشة
    private fun getCurrentBadWordsOnScreen(pkg: String): Set<String> {
        val root = rootInActiveWindow ?: return emptySet()
        return try {
            val texts = mutableSetOf<String>()
            collectNonInputTexts(root, texts)
            val allText = texts.joinToString(" ").lowercase()
            val found = mutableSetOf<String>()
            findBlockedInText(allText, found)
            found
        } finally {
            root.recycle()
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  handleInstantBlock
    // ══════════════════════════════════════════════════════════════════════════
    private fun handleInstantBlock(pkg: String) {
        rebuildBlacklistIfNeeded()
        if (longWordsSet.isEmpty() && shortWordsList.isEmpty()) return

        val now = System.currentTimeMillis()
        if (now - lastStrikeTimeMs < STRIKE_COOLDOWN_MS) return

        val root = rootInActiveWindow ?: return
        try {
            val found = mutableSetOf<String>()
            collectAllWords(root, found)
            if (found.isNotEmpty()) {
                Log.d(TAG, "🚫 [فوري] ${found.first()} في $pkg")
                triggerInstantBlock(pkg, found.first())
            }
        } finally {
            root.recycle()
        }
    }

    private fun triggerInstantBlock(pkg: String, word: String) {
        lastStrikeTimeMs = System.currentTimeMillis()
        lastBlockedPkg   = pkg
        saveBlockLog(word)
        sendBroadcast(Intent("com.maadh.shield.BLOCKED_EVENT").apply { putExtra("word", word) })

        performGlobalAction(GLOBAL_ACTION_HOME)

        Handler(Looper.getMainLooper()).postDelayed({
            performGlobalAction(GLOBAL_ACTION_RECENTS)
            Handler(Looper.getMainLooper()).postDelayed({ dismissRecentCard() }, 900)
        }, 600)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  Recents dismiss
    // ══════════════════════════════════════════════════════════════════════════
    private fun tryDismissInRecents() {
        val root = rootInActiveWindow ?: return
        try {
            val card = findFirstDismissable(root)
            if (card != null) {
                card.performAction(AccessibilityNodeInfo.ACTION_DISMISS)
                card.recycle()
                Log.d(TAG, "✅ تم مسح ${lastBlockedPkg} من الـ recents")
                lastBlockedPkg = null
            }
        } finally {
            root.recycle()
        }
    }

    private fun dismissRecentCard() {
        val root = rootInActiveWindow ?: run {
            performGlobalAction(GLOBAL_ACTION_HOME)
            lastBlockedPkg = null
            return
        }

        var dismissed = false
        try {
            val card = findFirstDismissable(root)
            if (card != null) {
                dismissed = card.performAction(AccessibilityNodeInfo.ACTION_DISMISS)
                card.recycle()
                if (dismissed) Log.d(TAG, "✅ [dismiss] طريقة 1 نجحت")
            }

            if (!dismissed && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val metrics = resources.displayMetrics
                val path = android.graphics.Path().apply {
                    moveTo(metrics.widthPixels / 2f, metrics.heightPixels * 0.6f)
                    lineTo(metrics.widthPixels / 2f, metrics.heightPixels * 0.1f)
                }
                val gesture = android.accessibilityservice.GestureDescription.Builder()
                    .addStroke(
                        android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 300)
                    ).build()

                dispatchGesture(gesture, object : GestureResultCallback() {
                    override fun onCompleted(g: android.accessibilityservice.GestureDescription?) {
                        Log.d(TAG, "✅ [dismiss] Swipe نجح")
                        lastBlockedPkg = null
                        Handler(Looper.getMainLooper()).postDelayed({
                            performGlobalAction(GLOBAL_ACTION_HOME)
                        }, 300)
                    }
                    override fun onCancelled(g: android.accessibilityservice.GestureDescription?) {
                        performGlobalAction(GLOBAL_ACTION_HOME)
                    }
                }, null)
                return
            }
        } finally {
            root.recycle()
        }

        if (dismissed) lastBlockedPkg = null
        Handler(Looper.getMainLooper()).postDelayed({ performGlobalAction(GLOBAL_ACTION_HOME) }, 300)
    }

    private fun findFirstDismissable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.isDismissable) { queue.forEach { it.recycle() }; return node }
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
        }
        return null
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  Blacklist
    // ══════════════════════════════════════════════════════════════════════════
    private fun rebuildBlacklistIfNeeded() {
        val prefs           = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val blacklistString = prefs.getString("flutter.ai_blacklist", "") ?: ""
        if (blacklistString == cachedBlacklistStr) return
        val all        = blacklistString.split(",").map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        longWordsSet   = HashSet(all.filter { it.length >= SHORT_WORD_MIN_LENGTH })
        shortWordsList = all.filter { it.length < SHORT_WORD_MIN_LENGTH }
        cachedBlacklistStr = blacklistString
    }

    private fun collectAllWords(node: AccessibilityNodeInfo, found: MutableSet<String>) {
        node.text?.toString()?.lowercase()?.let { findBlockedInText(it, found) }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectAllWords(child, found)
            child.recycle()
        }
    }

    private fun findBlockedInText(text: String, found: MutableSet<String>) {
        for (w in text.split(Regex("[\\s\\p{Punct}،؛؟!]+"))) {
            if (w.isNotEmpty() && longWordsSet.contains(w)) found.add(w)
        }
        for (w in longWordsSet) { if (text.contains(w)) found.add(w) }
        for (w in shortWordsList) { if (matchesWord(text, w)) found.add(w) }
    }

    private fun matchesWord(text: String, word: String): Boolean {
        if (word.length >= SHORT_WORD_MIN_LENGTH) return text.contains(word)
        val escaped = Regex.escape(word)
        return Regex(
            "(?<![a-zA-Z\\u0600-\\u06FF])$escaped(?![a-zA-Z\\u0600-\\u06FF])",
            RegexOption.IGNORE_CASE
        ).containsMatchIn(text)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  Notifications
    // ══════════════════════════════════════════════════════════════════════════
    private fun showBlockNotification(title: String, body: String) {
        try {
            val notif = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false)
                .setOngoing(true)
                .build()
            NotificationManagerCompat.from(this).notify(1003, notif)
        } catch (e: Exception) {
            Log.e(TAG, "❌ فشل إشعار الحجب: ${e.message}")
        }
    }

    private fun showWarningNotification(id: Int, title: String, body: String) {
        try {
            val notif = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(this).notify(id, notif)
            Log.d(TAG, "🔔 $title")
        } catch (e: Exception) {
            Log.e(TAG, "❌ فشل الإشعار: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID, "تحذيرات الحارس", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "تحذيرات المحتوى غير اللائق" }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun getAppName(pkg: String): String {
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) { pkg }
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
                    val f = extractMediaFileName(text)
                    if (f != null) { q.forEach { it.recycle() }; return f }
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

    override fun onInterrupt() { stopWatching() }
    override fun onDestroy()   { super.onDestroy(); stopWatching() }
}
