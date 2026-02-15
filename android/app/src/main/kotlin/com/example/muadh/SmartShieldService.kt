package com.example.muadh

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

class SmartShieldService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // مثال: عرض رسالة عند كل تغيير في النوافذ
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            Toast.makeText(this, "Maadh Smart Shield active", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onInterrupt() {
        // في حال توقف الخدمة
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Toast.makeText(this, "Smart Shield connected", Toast.LENGTH_SHORT).show()
    }
}
