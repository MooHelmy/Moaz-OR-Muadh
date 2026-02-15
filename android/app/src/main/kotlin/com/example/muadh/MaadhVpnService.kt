package com.example.muadh

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor

class MaadhVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (vpnInterface == null) {
            val builder = Builder()
            builder.setSession("Maadh Shield")
            builder.addAddress("10.0.0.2", 32)
            builder.addRoute("0.0.0.0", 0)
            
            // استخدام DNS CleanBrowsing (Family Filter) لحجب الإباحية
            builder.addDnsServer("185.228.168.168")
            builder.addDnsServer("185.228.169.168")
            
            vpnInterface = builder.establish()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        vpnInterface?.close()
        vpnInterface = null
    }
}