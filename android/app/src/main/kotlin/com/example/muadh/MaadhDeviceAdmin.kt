package com.example.muadh

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

class MaadhDeviceAdmin : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        Toast.makeText(
            context,
            "✅ تم تفعيل حماية التطبيق بنجاح",
            Toast.LENGTH_SHORT
        ).show()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Toast.makeText(
            context,
            "⚠️ تم إلغاء حماية التطبيق",
            Toast.LENGTH_SHORT
        ).show()
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        return "لا يمكن إلغاء الحماية بدون إدخال الرمز السري من داخل التطبيق"
    }
}
