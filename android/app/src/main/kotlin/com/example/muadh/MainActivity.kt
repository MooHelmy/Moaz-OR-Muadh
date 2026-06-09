package com.example.muadh

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.MediaMetadataRetriever
import android.net.VpnService
import android.os.Build
import android.os.FileObserver
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    private val VPN_CHANNEL         = "com.maadh.shield/vpn"
    private val FILE_METHOD_CHANNEL = "medi_guard/file_observer"
    private val FILE_EVENT_CHANNEL  = "medi_guard/file_events"
    private val DELETE_CHANNEL      = "com.maadh.shield/delete"
    private val ADMIN_CHANNEL       = "com.maadh.shield/admin"
    private val VIDEO_META_CHANNEL  = "medi_guard/video_metadata"
    private val DEVICE_INFO_CHANNEL = "medi_guard/device_info"
    private val MEDIA_STORE_CHANNEL = "medi_guard/media_store"
    private val SCAN_FILE_CHANNEL    = "medi_guard/scan_file"

    private var eventSink: EventChannel.EventSink? = null
    private val observers = mutableListOf<FileObserver>()

    private val mediaExtensions = listOf(
        ".jpg", ".jpeg", ".png", ".mp4", ".mkv", ".avi", ".webp", ".3gp"
    )

    private val PREFS_NAME = "FlutterSharedPreferences"
    private val PIN_KEY    = "flutter.anti_uninstall_pin"
    private val ADMIN_KEY  = "flutter.anti_uninstall_active"

    companion object {
        // REQUEST_ADMIN_CODE أُزيل — startActivityForResult استُبدل بـ startActivity
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupVpnChannel(flutterEngine)
        setupFileObserverChannel(flutterEngine)
        setupDeleteChannel(flutterEngine)
        setupAdminChannel(flutterEngine)
        setupVideoMetadataChannel(flutterEngine)
        setupDeviceInfoChannel(flutterEngine)
        setupMediaStoreChannel(flutterEngine)
        setupScanFileChannel(flutterEngine)
    }


    // ─── Scan File Channel ─────────────────────────────────────────────────────
    // يستقبل broadcast من MaadhAccessibilityService لما المستخدم يفتح ملف ميديا
    // الحل: نكتب الـ path في SharedPreferences وبعدين نبعت event لـ Flutter
    // Flutter (main isolate) بيستقبله ويبعته للـ background task بـ sendDataToTask
    private var scanFileEventSink: EventChannel.EventSink? = null

    private fun setupScanFileChannel(flutterEngine: FlutterEngine) {
        // EventChannel على main engine — بيسمعه Flutter في main isolate
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCAN_FILE_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                scanFileEventSink = sink
            }
            override fun onCancel(arguments: Any?) {
                scanFileEventSink = null
            }
        })

        // استقبل الـ broadcast من MaadhAccessibilityService
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val path = intent?.getStringExtra("path") ?: return
                android.util.Log.d("ScanFileChannel", "📤 accessibility path: $path")
                // بعت على EventChannel → main isolate → sendDataToTask → background task
                runOnUiThread { scanFileEventSink?.success(path) }
            }
        }
        registerReceiver(receiver, IntentFilter("com.maadh.shield.SCAN_FILE"))
    }

    // ─── MediaStore Channel ────────────────────────────────────────────────────
    // يجيب الملفات الجديدة أو المعدّلة من Android MediaStore
    // بدون FileObserver — Android يسجّل الملفات هنا بعد اكتمال الـ write
    // مش محتاج permissions إضافية — READ_EXTERNAL_STORAGE كافية (موجودة)
    private fun setupMediaStoreChannel(flutterEngine: FlutterEngine) {
        val resolver = contentResolver

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_STORE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRecentMedia" -> {
                    val sinceTimestamp = call.argument<Int>("sinceTimestamp") ?: 0
                    val limit = call.argument<Int>("limit") ?: 20

                    try {
                        val paths = mutableListOf<String>()

                        // نجيب من Images + Video في query واحدة عبر Files URI
                        val uri = android.provider.MediaStore.Files.getContentUri("external")
                        val projection = arrayOf(
                            android.provider.MediaStore.Files.FileColumns.DATA,
                            android.provider.MediaStore.Files.FileColumns.DATE_MODIFIED,
                            android.provider.MediaStore.Files.FileColumns.MEDIA_TYPE,
                        )

                        // فقط صور وفيديوهات — مش كل الملفات
                        val mediaTypeFilter = (
                            "${android.provider.MediaStore.Files.FileColumns.MEDIA_TYPE}" +
                            " IN (${android.provider.MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}," +
                            "${android.provider.MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})"
                        )

                        val selection = if (sinceTimestamp > 0) {
                            "$mediaTypeFilter AND " +
                            "${android.provider.MediaStore.Files.FileColumns.DATE_MODIFIED} > ?"
                        } else {
                            mediaTypeFilter
                        }

                        val selectionArgs = if (sinceTimestamp > 0) {
                            arrayOf(sinceTimestamp.toString())
                        } else {
                            null
                        }

                        val sortOrder =
                            "${android.provider.MediaStore.Files.FileColumns.DATE_MODIFIED} DESC LIMIT $limit"

                        resolver.query(uri, projection, selection, selectionArgs, sortOrder)
                            ?.use { cursor ->
                                val dataCol = cursor.getColumnIndexOrThrow(
                                    android.provider.MediaStore.Files.FileColumns.DATA
                                )
                                while (cursor.moveToNext()) {
                                    val path = cursor.getString(dataCol) ?: continue
                                    if (path.isNotEmpty()) paths.add(path)
                                }
                            }

                        result.success(paths)
                    } catch (e: Exception) {
                        result.error("MEDIA_STORE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─── Device Info Channel ───────────────────────────────────────────────────
    // يُرجع hardware specs للـ Flutter لتحديد concurrency level المناسب
    // لا يحتاج صلاحيات خاصة — كل المعلومات متاحة بدون permissions
    private fun setupDeviceInfoChannel(flutterEngine: FlutterEngine) {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_INFO_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceCapabilities" -> {
                    result.success(mapOf(
                        // عدد أنوية الـ CPU المتاحة للتطبيق
                        "cpuCores"       to Runtime.getRuntime().availableProcessors(),
                        // إجمالي RAM بالميجابايت
                        "totalRamMb"     to (memInfo.totalMem / (1024 * 1024)).toInt(),
                        // هل الجهاز low-RAM (ActivityManager classification)
                        "isLowRamDevice" to am.isLowRamDevice,
                        // Android SDK version — للمقارنة إذا احتجنا
                        "sdkInt"         to Build.VERSION.SDK_INT,
                        // ✅ FIX: isPowerSaveMode من PowerManager — الـ API الرسمي
                        // أموثق وأصح من قراءة /sys/class/power_supply على كل الأجهزة
                        "isPowerSaveMode" to run {
                            val pm = getSystemService(Context.POWER_SERVICE)
                                    as android.os.PowerManager
                            pm.isPowerSaveMode
                        },
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─── Video Metadata Channel ────────────────────────────────────────────────
    // getVideoMetadata : يجيب duration/width/height بدون decode
    // getFrameBytes    : يجيب frame كـ JPEG bytes بدون FileInputStream leak
    //
    // ✅ FIX: استبدال VideoThumbnail package بـ MediaMetadataRetriever مباشرة
    // VideoThumbnail كان بيفتح FileInputStream ويسيبه للـ GC يقفله
    // → بيسبب "A resource failed to call close / ENOENT" في الـ logcat
    // MediaMetadataRetriever.release() في finally بيضمن إغلاق كل resources فوراً
    private fun setupVideoMetadataChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VIDEO_META_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "getVideoMetadata" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("NO_PATH", "path is null", null)
                        return@setMethodCallHandler
                    }
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(path)
                        val durationStr = retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_DURATION
                        )
                        val widthStr = retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
                        )
                        val heightStr = retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
                        )
                        result.success(mapOf(
                            "durationMs" to (durationStr?.toLongOrNull() ?: 0L),
                            "width"      to (widthStr?.toIntOrNull()    ?: 0),
                            "height"     to (heightStr?.toIntOrNull()   ?: 0),
                        ))
                    } catch (e: Exception) {
                        result.error("RETRIEVER_ERROR", e.message, null)
                    } finally {
                        // ✅ release() مضمون دايماً — مفيش FileInputStream يتسرب للـ GC
                        retriever.release()
                    }
                }

                "getFrameBytes" -> {
                    val path   = call.argument<String>("path")
                    val timeMs = call.argument<Int>("timeMs") ?: 0
                    val size   = call.argument<Int>("size")   ?: 384

                    if (path == null) {
                        result.error("NO_PATH", "path is null", null)
                        return@setMethodCallHandler
                    }

                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(path)

                        // OPTION_CLOSEST_SYNC = أسرع seek — يروح لأقرب keyframe
                        // أسرع من OPTION_CLOSEST ومناسب للـ NSFW detection
                        val bitmap = retriever.getFrameAtTime(
                            timeMs * 1000L, // microseconds
                            MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                        )

                        if (bitmap == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        // Scale لـ size×size في memory بدون disk
                        val scaled = android.graphics.Bitmap.createScaledBitmap(
                            bitmap, size, size, true
                        )
                        if (scaled !== bitmap) bitmap.recycle()

                        // Compress لـ JPEG bytes في memory — مفيش disk write
                        val stream = java.io.ByteArrayOutputStream()
                        scaled.compress(
                            android.graphics.Bitmap.CompressFormat.JPEG,
                            80, // quality 80 — كافي للـ NSFW model
                            stream
                        )
                        scaled.recycle()

                        result.success(stream.toByteArray())

                    } catch (e: Exception) {
                        result.success(null) // frame فاشلة → skip بدل crash
                    } finally {
                        // ✅ release() مضمون — يغلق كل native resources فوراً
                        // ده اللي كان ناقص في VideoThumbnail package
                        retriever.release()
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ─── Anti-Uninstall / Admin Channel ───────────────────────────────────────
    private fun setupAdminChannel(flutterEngine: FlutterEngine) {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, MaadhDeviceAdmin::class.java)
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ADMIN_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // هل صلاحية Device Admin مفعلة حالياً؟
                "isAdminActive" -> {
                    result.success(dpm.isAdminActive(adminComponent))
                }

                // فتح شاشة تفعيل صلاحية Device Admin
                "requestAdmin" -> {
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                        putExtra(
                            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                            "هذه الصلاحية تمنع حذف التطبيق لحماية الجهاز"
                        )
                    }
                    // ✅ FIX: startActivity بدل startActivityForResult (deprecated في Android 13+)
                    // نتيجة الـ admin بتتحقق من Flutter عبر isAdminActive() مباشرة
                    startActivity(intent)
                    result.success(true)
                }

                // توليد PIN عشوائي من 6 أرقام — يُحفظ كـ SHA-256 ويُرجَع للـ Flutter مرة واحدة فقط
                "generateAndSavePin" -> {
                    val pin = (100000..999999).random().toString()
                    val hash = sha256(pin)
                    prefs.edit().putString(PIN_KEY, hash).apply()
                    android.util.Log.d("AdminChannel", "✅ PIN generated and saved as hash")
                    result.success(pin)
                }

                // التحقق من PIN — لو صح يُلغى Device Admin
                "verifyPinAndRemoveAdmin" -> {
                    val inputPin = call.argument<String>("pin") ?: ""
                    val savedHash = prefs.getString(PIN_KEY, null)

                    if (savedHash == null) {
                        result.error("NO_PIN", "لا يوجد PIN محفوظ", null)
                        return@setMethodCallHandler
                    }

                    if (sha256(inputPin) == savedHash) {
                        dpm.removeActiveAdmin(adminComponent)
                        prefs.edit()
                            .remove(PIN_KEY)
                            .putBoolean(ADMIN_KEY, false)
                            .apply()
                        android.util.Log.d("AdminChannel", "✅ Admin removed successfully")
                        result.success(true)
                    } else {
                        android.util.Log.d("AdminChannel", "❌ Wrong PIN entered")
                        result.success(false)
                    }
                }

                // هل خاصية Anti-Uninstall مفعلة (Device Admin نشط + علامة Flutter)؟
                "isAntiUninstallActive" -> {
                    val flagActive = prefs.getBoolean(ADMIN_KEY, false)
                    val adminActive = dpm.isAdminActive(adminComponent)
                    result.success(flagActive && adminActive)
                }

                // حفظ حالة التفعيل من Flutter
                "setAntiUninstallActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    prefs.edit().putBoolean(ADMIN_KEY, active).apply()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    // ─── SHA-256 ───────────────────────────────────────────────────────────────
    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    // ─── Delete Channel ────────────────────────────────────────────────────────
    private fun setupDeleteChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DELETE_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "deleteFile") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("NO_PATH", "path is null", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(path)
                    if (!file.exists()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val deleted = file.delete()
                    android.util.Log.d(
                        "DeleteChannel",
                        if (deleted) "✅ Deleted: $path" else "❌ Failed: $path"
                    )
                    result.success(deleted)
                } catch (e: Exception) {
                    android.util.Log.e("DeleteChannel", "Error: ${e.message}")
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    // ─── VPN Channel ───────────────────────────────────────────────────────────
    private fun setupVpnChannel(flutterEngine: FlutterEngine) {
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VPN_CHANNEL
        )

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val word = intent?.getStringExtra("word") ?: "محتوى غير لائق"
                methodChannel.invokeMethod("onBlockedContent", word)
            }
        }
        registerReceiver(receiver, IntentFilter("com.maadh.shield.BLOCKED_EVENT"))

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val intent = VpnService.prepare(this)
                    // ✅ FIX: startActivity بدل startActivityForResult (deprecated)
                    if (intent != null) startActivity(intent)
                    result.success(true)
                }
                "stopVpn" -> result.success(true)
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    })
                    result.success(true)
                }
                "isAccessibilityEnabled" -> {
                    val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
                    val myService = ComponentName(this, MaadhAccessibilityService::class.java)
                    val isEnabled = am.getEnabledAccessibilityServiceList(
                        AccessibilityServiceInfo.FEEDBACK_ALL_MASK
                    ).any { it.id.contains(myService.flattenToShortString()) }
                    result.success(isEnabled)
                }
                "updateBlacklist" -> {
                    val blacklist = call.arguments as String
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putString("flutter.ai_blacklist", blacklist)
                        .apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─── FileObserver Channel ──────────────────────────────────────────────────
    private fun setupFileObserverChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "startWatching") {
                @Suppress("UNCHECKED_CAST")
                val folders = call.argument<List<String>>("folders") ?: emptyList()
                startWatchingFolders(folders)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun startWatchingFolders(folders: List<String>) {
        observers.forEach { it.stopWatching() }
        observers.clear()
        for (folderPath in folders) {
            val dir = File(folderPath)
            if (!dir.exists()) continue

            // ✅ FIX: FileObserver(File, Int) اتضاف في API 29 (Android 10)
            // على API 28 وأقل لازم نستخدم FileObserver(String, Int)
            val observer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                object : FileObserver(dir, CREATE or MOVED_TO or CLOSE_WRITE) {
                    override fun onEvent(event: Int, path: String?) {
                        if (path == null) return
                        val fullPath = "$folderPath/$path"
                        if (!isMediaFile(fullPath)) return
                        runOnUiThread { eventSink?.success(fullPath) }
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                object : FileObserver(folderPath, CREATE or MOVED_TO or CLOSE_WRITE) {
                    override fun onEvent(event: Int, path: String?) {
                        if (path == null) return
                        val fullPath = "$folderPath/$path"
                        if (!isMediaFile(fullPath)) return
                        runOnUiThread { eventSink?.success(fullPath) }
                    }
                }
            }

            observer.startWatching()
            observers.add(observer)
        }
    }

    private fun isMediaFile(path: String) =
        mediaExtensions.any { path.lowercase().endsWith(it) }

    override fun onDestroy() {
        observers.forEach { it.stopWatching() }
        observers.clear()
        super.onDestroy()
    }
}