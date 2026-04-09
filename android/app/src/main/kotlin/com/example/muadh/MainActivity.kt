package com.example.muadh

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.content.Intent
import android.net.VpnService
import android.app.Activity
import android.content.Context
import android.view.accessibility.AccessibilityManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.net.Uri
import android.provider.Settings

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.maadh.shield/vpn"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // استقبال البث من MaadhAccessibilityService وتحويله لـ Flutter
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val word = intent?.getStringExtra("word") ?: "محتوى غير لائق"
                methodChannel.invokeMethod("onBlockedContent", word)
            }
        }
        registerReceiver(receiver, IntentFilter("com.maadh.shield.BLOCKED_EVENT"))

        methodChannel.setMethodCallHandler { call, result ->
            if (call.method == "startVpn") {
                val intent = VpnService.prepare(this)
                if (intent != null) {
                    startActivityForResult(intent, 0)
                } else {
                    // الصلاحية موجودة بالفعل، ابدأ الخدمة مباشرة
                    // startService(Intent(this, MaadhVpnService::class.java)) // معطلة لعدم وجود الملف في المرفقات
                }
                result.success(true)
            } else if (call.method == "stopVpn") {
                // stopService(Intent(this, MaadhVpnService::class.java)) // معطلة لعدم وجود الملف في المرفقات
                result.success(true)
            } else if (call.method == "openAccessibilitySettings") {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                result.success(true)
            } else if (call.method == "isAccessibilityEnabled") {
                val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
                val enabledServices = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                val myService = ComponentName(this, MaadhAccessibilityService::class.java)
                var isEnabled = false
                for (service in enabledServices) {
                    if (service.id.contains(myService.flattenToShortString())) {
                        isEnabled = true
                        break
                    }
                }
                result.success(isEnabled)
            } else if (call.method == "updateBlacklist") {
                val blacklist = call.arguments as String
                // التعديل هنا: استخدام ملف FlutterSharedPreferences وإضافة البادئة flutter.
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putString("flutter.ai_blacklist", blacklist).apply()
                result.success(true)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode == Activity.RESULT_OK) {
            // val intent = Intent(this, MaadhVpnService::class.java) // معطلة لعدم وجود الملف
            // startService(intent)
        }
    }
}