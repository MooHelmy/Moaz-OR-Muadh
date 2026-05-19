package com.example.muadh

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

// ══════════════════════════════════════════════════════════════════════════════
//  AppBootReceiver
//
//  بيشتغل في 3 حالات:
//    1. BOOT_COMPLETED     — بعد restart الجهاز
//    2. QUICKBOOT_POWERON  — بعد restart سريع (Huawei/Oppo/Realme)
//    3. MY_PACKAGE_REPLACED — بعد update التطبيق
//
//  بيشغّل MainActivity عشان Flutter يبدأ ويشغّل الـ foreground service
// ══════════════════════════════════════════════════════════════════════════════
class AppBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d("AppBootReceiver", "📡 Received: $action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d("AppBootReceiver", "🚀 إعادة تشغيل الخدمة بعد: $action")
                restartService(context)
            }
        }
    }

    private fun restartService(context: Context) {
        try {
            // ✅ شغّل الـ foreground service مباشرة بدون فتح الـ UI
            // المستخدم مش هيشوف التطبيق على الشاشة — بيشتغل في الخلفية بصمت
            val intent = Intent(
                context,
                com.pravera.flutter_foreground_task.service.ForegroundService::class.java
            )
            context.startForegroundService(intent)
            Log.d("AppBootReceiver", "✅ Service started in background silently")
        } catch (e: Exception) {
            Log.e("AppBootReceiver", "❌ فشل إعادة التشغيل: ${e.message}")
        }
    }
}