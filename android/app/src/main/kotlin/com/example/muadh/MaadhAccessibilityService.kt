package com.example.muadh

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.content.Context
import android.util.Log

class MaadhAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // 1. قراءة القائمة المحظورة التي حفظها Flutter
        val prefs = getSharedPreferences("MaadhSettings", Context.MODE_PRIVATE)
        val blacklistString = prefs.getString("ai_blacklist", "") ?: ""
        
        if (blacklistString.isEmpty()) return
        
        val blacklist = blacklistString.split(",").map { it.trim().lowercase() }.filter { it.isNotEmpty() }

        // 2. فحص محتوى الشاشة
        val rootNode = rootInActiveWindow ?: return
        if (scanNode(rootNode, blacklist)) {
            // 3. إجراء الحظر (الخروج للشاشة الرئيسية)
            performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            Log.d("MaadhShield", "🚫 تم حجب محتوى مخالف!")
        }
    }

    private fun scanNode(node: AccessibilityNodeInfo, blacklist: List<String>): Boolean {
        if (node.text != null) {
            val text = node.text.toString().lowercase()
            for (word in blacklist) {
                if (text.contains(word)) {
                    return true
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (scanNode(child, blacklist)) return true
        }
        return false
    }

    override fun onInterrupt() {}
}