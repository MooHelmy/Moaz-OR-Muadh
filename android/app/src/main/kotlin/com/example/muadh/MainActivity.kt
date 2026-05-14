package com.example.muadh

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.FileObserver
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val VPN_CHANNEL        = "com.maadh.shield/vpn"
    private val FILE_METHOD_CHANNEL = "medi_guard/file_observer"
    private val FILE_EVENT_CHANNEL  = "medi_guard/file_events"
    // ✅ channel جديد للحذف الـ native
    private val DELETE_CHANNEL      = "com.maadh.shield/delete"

    private var eventSink: EventChannel.EventSink? = null
    private val observers = mutableListOf<FileObserver>()

    private val mediaExtensions = listOf(
        ".jpg", ".jpeg", ".png", ".mp4", ".mkv", ".avi", ".webp", ".3gp"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupVpnChannel(flutterEngine)
        setupFileObserverChannel(flutterEngine)
        setupDeleteChannel(flutterEngine)   // ✅ جديد
    }

    // ─── Delete Channel ────────────────────────────────────
    // ✅ الحذف الـ native أضمن على Android 10+ لأنه يتعامل مع الـ MediaStore
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
                    android.util.Log.d("DeleteChannel", if (deleted) "✅ Deleted: $path" else "❌ Failed: $path")
                    result.success(deleted)
                } catch (e: Exception) {
                    android.util.Log.e("DeleteChannel", "Error deleting $path: ${e.message}")
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    // ─── VPN Channel ───────────────────────────────────────
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
                    if (intent != null) startActivityForResult(intent, 0)
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
                    getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .edit().putString("flutter.ai_blacklist", blacklist).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─── FileObserver Channel ──────────────────────────────
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
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
    }

    private fun startWatchingFolders(folders: List<String>) {
        observers.forEach { it.stopWatching() }
        observers.clear()
        for (folderPath in folders) {
            val dir = File(folderPath)
            if (!dir.exists()) continue
            val observer = object : FileObserver(dir, CREATE or MOVED_TO or CLOSE_WRITE) {
                override fun onEvent(event: Int, path: String?) {
                    if (path == null) return
                    val fullPath = "$folderPath/$path"
                    if (!isMediaFile(fullPath)) return
                    runOnUiThread { eventSink?.success(fullPath) }
                }
            }
            observer.startWatching()
            observers.add(observer)
        }
    }

    private fun isMediaFile(path: String) = mediaExtensions.any { path.lowercase().endsWith(it) }

    override fun onDestroy() {
        observers.forEach { it.stopWatching() }
        observers.clear()
        super.onDestroy()
    }
}
