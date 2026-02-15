
package com.example.muadh

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.content.Context
import android.util.Log

class MaadhAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("MaadhShield", "✅ تم تشغيل خدمة الحارس الذكي بنجاح")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // 1. قراءة القائمة المحظورة التي حفظها Flutter
        val prefs = getSharedPreferences("MaadhSettings", Context.MODE_PRIVATE)
        val blacklistString = prefs.getString("ai_blacklist", "") ?: ""
        
        if (blacklistString.isEmpty()) return
        
        val blacklist = blacklistString.split(",").map { it.trim().lowercase() }.filter { it.isNotEmpty() }

        // 2. فحص محتوى الشاشة
        val rootNode = rootInActiveWindow ?: return
        scanNode(rootNode, blacklist)
    }

    private fun scanNode(node: AccessibilityNodeInfo, blacklist: List<String>) {
        if (node.text != null) {
            val text = node.text.toString().lowercase()
            for (word in blacklist) {
                if (text.contains(word)) {
                    Log.d("MaadhShield", "🚫 تم اكتشاف كلمة محظورة: $word")
                    performGlobalAction(GLOBAL_ACTION_HOME)
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    return
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            scanNode(child, blacklist)
        }
    }

    override fun onInterrupt() {}
}
                scanNode(child, blacklist)
            }
        }
