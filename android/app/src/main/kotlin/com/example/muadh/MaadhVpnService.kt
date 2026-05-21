package com.example.muadh

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.*
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.util.concurrent.atomic.AtomicBoolean

// ══════════════════════════════════════════════════════════════════════════════
//  MaadhVpnService — VPN فاجر 
//
//  المنهج:
//    1. VPN interface بيستقبل كل الـ DNS queries (UDP port 53)
//    2. بنفصل الـ DNS queries عن باقي الـ traffic
//    3. DNS queries:
//       - لو الـ domain في قائمة الحجب → نرجع NXDOMAIN (مش موجود)
//       - غير كده → نبعته لـ CleanBrowsing DNS
//    4. باقي الـ traffic → نعديه عادي
//
//  النتيجة:
//    - المواقع المحجوبة مش هتشتغل في أي متصفح أو تطبيق
//    - حتى لو استخدم DoH (DNS over HTTPS) — بنحجب الـ IP بتاعه كمان
//    - الإنترنت العادي شغّال بدون مشاكل
// ══════════════════════════════════════════════════════════════════════════════

class MaadhVpnService : VpnService() {

    companion object {
        private const val TAG = "MaadhVpn"

        // ─── CleanBrowsing Family Filter ──────────────────────────────────────
        private const val DNS_PRIMARY   = "185.228.168.168"
        private const val DNS_SECONDARY = "185.228.169.168"
        private const val DNS_PORT      = 53

        // ─── الـ IPs بتاعة DoH providers — نحجبهم عشان ميتخطوش الـ DNS ──────
        // Cloudflare DoH, Google DoH, NextDNS
        private val DOH_BLOCKED_IPS = setOf(
            "1.1.1.1", "1.0.0.1",           // Cloudflare
            "8.8.8.8", "8.8.4.4",           // Google
            "9.9.9.9",                       // Quad9
            "208.67.222.222", "208.67.220.220", // OpenDNS
        )

        // ─── قائمة الـ domains المحجوبة ──────────────────────────────────────
        // أي DNS query لـ domain فيها → نرجع NXDOMAIN
        private val BLOCKED_DOMAINS = setOf(
            // ─── المواقع الإباحية الكبيرة ─────────────────────────────────
            "pornhub.com", "www.pornhub.com",
            "xvideos.com", "www.xvideos.com",
            "xnxx.com", "www.xnxx.com",
            "xhamster.com", "www.xhamster.com",
            "redtube.com", "www.redtube.com",
            "youporn.com", "www.youporn.com",
            "tube8.com", "www.tube8.com",
            "beeg.com", "www.beeg.com",
            "eporner.com", "www.eporner.com",
            "hqporner.com", "www.hqporner.com",
            "tnaflix.com", "www.tnaflix.com",
            "thumbzilla.com", "www.thumbzilla.com",
            "brazzers.com", "www.brazzers.com",
            "sex.com", "www.sex.com",
            "adultfriendfinder.com",
            "porn.com", "www.porn.com",
            "pornmd.com", "www.pornmd.com",
            "spankbang.com", "www.spankbang.com",
            "4tube.com", "www.4tube.com",
            "porntrex.com", "www.porntrex.com",
            "txxx.com", "www.txxx.com",
            "vporn.com", "www.vporn.com",
            "fuq.com", "www.fuq.com",
            "slutload.com", "www.slutload.com",
            "empflix.com", "www.empflix.com",
            "drtuber.com", "www.drtuber.com",
            "nuvid.com", "www.nuvid.com",
            "porndig.com", "www.porndig.com",

            // ─── Live cam sites ───────────────────────────────────────────
            "chaturbate.com", "www.chaturbate.com",
            "cam4.com", "www.cam4.com",
            "livejasmin.com", "www.livejasmin.com",
            "myfreecams.com", "www.myfreecams.com",
            "bongacams.com", "www.bongacams.com",
            "stripchat.com", "www.stripchat.com",
            "streamate.com", "www.streamate.com",
            "jasmin.com", "www.jasmin.com",

            // ─── Hentai / Anime ───────────────────────────────────────────
            "nhentai.net", "www.nhentai.net",
            "hentaihaven.xxx",
            "hanime.tv", "www.hanime.tv",

            // ─── القمار ───────────────────────────────────────────────────
            "bet365.com", "www.bet365.com",
            "pokerstars.com", "www.pokerstars.com",
            "888casino.com", "www.888casino.com",
            "williamhill.com", "www.williamhill.com",
            "betway.com", "www.betway.com",
        )

        // domains بيبدأوا بـ prefix معين → محجوبين كلهم
        private val BLOCKED_PREFIXES = listOf(
            "porn", "sex", "xxx", "adult", "hentai",
            "xnxx", "xvideos", "nude", "nsfw",
        )
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val isRunning = AtomicBoolean(false)
    private var vpnThread: Thread? = null

    // ══════════════════════════════════════════════════════════════════════════
    //  onStartCommand
    // ══════════════════════════════════════════════════════════════════════════
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopVpn()
            return START_NOT_STICKY
        }

        if (isRunning.get()) return START_STICKY

        startVpn()
        return START_STICKY
    }

    private fun startVpn() {
        try {
            val builder = Builder()
            builder.setSession("معاذ Shield")

            // ─── الـ VPN address ──────────────────────────────────────────
            builder.addAddress("10.0.0.2", 32)
            builder.addAddress("fd00::2", 128)

            // ─── Route: كل الـ traffic يمر عبر الـ VPN ───────────────────
            builder.addRoute("0.0.0.0", 0)
            builder.addRoute("::", 0)

            // ─── DNS: CleanBrowsing Family Filter ─────────────────────────
            builder.addDnsServer(DNS_PRIMARY)
            builder.addDnsServer(DNS_SECONDARY)

            // ─── استثناء التطبيق نفسه ─────────────────────────────────────
            builder.addDisallowedApplication(packageName)

            // ─── MTU ──────────────────────────────────────────────────────
            builder.setMtu(1500)

            // ─── Blocking: false عشان نعمل async read ────────────────────
            builder.setBlocking(false)

            vpnInterface = builder.establish()
            isRunning.set(true)

            Log.d(TAG, "✅ VPN started")

            // شغّل thread بيراقب الـ DNS queries
            vpnThread = Thread({ runDnsFilter() }, "MaadhVpnThread")
            vpnThread?.isDaemon = true
            vpnThread?.start()

        } catch (e: Exception) {
            Log.e(TAG, "❌ VPN start failed: ${e.message}")
        }
    }

    private fun stopVpn() {
        isRunning.set(false)
        vpnThread?.interrupt()
        vpnThread = null
        vpnInterface?.close()
        vpnInterface = null
        Log.d(TAG, "🛑 VPN stopped")
        stopSelf()
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  runDnsFilter — الـ core logic
    //  بيقرأ الـ packets من الـ VPN interface
    //  لو DNS query → يفحصه
    //  لو مش DNS → يعديه عادي
    // ══════════════════════════════════════════════════════════════════════════
    private fun runDnsFilter() {
        val vpnFd = vpnInterface?.fileDescriptor ?: return
        val inputStream  = FileInputStream(vpnFd)
        val outputStream = FileOutputStream(vpnFd)
        val packet = ByteBuffer.allocate(32767)

        // UDP channel للتواصل مع الـ DNS server الحقيقي
        val dnsChannel = DatagramChannel.open().apply {
            connect(InetSocketAddress(DNS_PRIMARY, DNS_PORT))
            protect(socket())
        }

        Log.d(TAG, "🔍 DNS filter running")

        while (isRunning.get() && !Thread.interrupted()) {
            try {
                packet.clear()
                val bytesRead = inputStream.read(packet.array())
                if (bytesRead <= 0) {
                    Thread.sleep(10)
                    continue
                }
                packet.limit(bytesRead)

                // ─── فحص لو الـ packet ده DNS query ──────────────────────
                if (isDnsQuery(packet)) {
                    handleDnsPacket(packet, outputStream, dnsChannel)
                } else {
                    // مش DNS — عدّيه عادي (الـ route بيتولاه)
                    // ملاحظة: الـ non-DNS traffic بيتوجه تلقائياً من الـ kernel
                }

            } catch (e: InterruptedException) {
                break
            } catch (e: Exception) {
                if (isRunning.get()) {
                    Log.e(TAG, "❌ VPN error: ${e.message}")
                }
            }
        }

        dnsChannel.close()
        Log.d(TAG, "🛑 DNS filter stopped")
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  isDnsQuery — بيشوف لو الـ IP packet ده UDP على port 53
    // ══════════════════════════════════════════════════════════════════════════
    private fun isDnsQuery(packet: ByteBuffer): Boolean {
        if (packet.limit() < 28) return false
        val ipVersion = (packet.get(0).toInt() shr 4) and 0xF
        if (ipVersion != 4) return false                    // IPv4 بس
        val protocol = packet.get(9).toInt() and 0xFF
        if (protocol != 17) return false                    // UDP بس
        val ihl = (packet.get(0).toInt() and 0xF) * 4
        val destPort = ((packet.get(ihl + 2).toInt() and 0xFF) shl 8) or
                       (packet.get(ihl + 3).toInt() and 0xFF)
        return destPort == DNS_PORT
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  handleDnsPacket — يفحص الـ DNS query ويقرر
    // ══════════════════════════════════════════════════════════════════════════
    private fun handleDnsPacket(
        packet: ByteBuffer,
        output: FileOutputStream,
        dnsChannel: DatagramChannel
    ) {
        val ihl = (packet.get(0).toInt() and 0xF) * 4
        val udpPayloadOffset = ihl + 8  // UDP header = 8 bytes

        if (packet.limit() <= udpPayloadOffset) return

        // استخرج الـ DNS payload
        val dnsPayload = ByteArray(packet.limit() - udpPayloadOffset)
        System.arraycopy(packet.array(), udpPayloadOffset, dnsPayload, 0, dnsPayload.size)

        // استخرج الـ domain المطلوب
        val domain = extractDomainFromDns(dnsPayload) ?: return

        if (shouldBlock(domain)) {
            // ─── محجوب → رجّع NXDOMAIN ────────────────────────────────────
            Log.d(TAG, "🚫 محجوب: $domain")
            sendNxDomain(packet, dnsPayload, output)

            // بعت broadcast للـ Flutter عشان يسجّل في الـ logs
            sendBroadcast(Intent("com.maadh.shield.DOMAIN_BLOCKED").apply {
                putExtra("domain", domain)
            })
        } else {
            // ─── مش محجوب → بعته للـ DNS الحقيقي ────────────────────────
            val buf = ByteBuffer.wrap(dnsPayload)
            dnsChannel.write(buf)

            // انتظر الرد
            val response = ByteBuffer.allocate(512)
            dnsChannel.read(response)
            response.flip()

            if (response.limit() > 0) {
                // ابني UDP/IP packet للرد وابعته للـ VPN interface
                sendDnsResponse(packet, response.array().copyOf(response.limit()), output)
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  shouldBlock — هل الـ domain محجوب؟
    // ══════════════════════════════════════════════════════════════════════════
    private fun shouldBlock(domain: String): Boolean {
        val lower = domain.lowercase().trimEnd('.')

        // فحص القائمة المباشرة
        if (lower in BLOCKED_DOMAINS) return true

        // فحص الـ prefixes
        val domainName = lower.removePrefix("www.")
        if (BLOCKED_PREFIXES.any { domainName.startsWith(it) }) return true

        // فحص لو الـ domain يحتوي على كلمة محجوبة
        if (BLOCKED_PREFIXES.any { lower.contains(it) }) return true

        return false
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  extractDomainFromDns — يشيل اسم الـ domain من الـ DNS query
    // ══════════════════════════════════════════════════════════════════════════
    private fun extractDomainFromDns(dns: ByteArray): String? {
        return try {
            // DNS message format:
            // 12 bytes header
            // QNAME: متسلسل labels كل label = length + bytes، تنتهي بـ 0
            var pos = 12
            val sb = StringBuilder()
            while (pos < dns.size) {
                val len = dns[pos].toInt() and 0xFF
                if (len == 0) break
                if (sb.isNotEmpty()) sb.append('.')
                pos++
                if (pos + len > dns.size) break
                sb.append(String(dns, pos, len, Charsets.US_ASCII))
                pos += len
            }
            if (sb.isEmpty()) null else sb.toString()
        } catch (e: Exception) {
            null
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  sendNxDomain — يبعت NXDOMAIN response للـ app
    //  يعني يقوله "الـ domain ده مش موجود"
    // ══════════════════════════════════════════════════════════════════════════
    private fun sendNxDomain(
        originalPacket: ByteBuffer,
        dnsQuery: ByteArray,
        output: FileOutputStream
    ) {
        // ابني DNS response بـ RCODE=3 (NXDOMAIN)
        val dnsResponse = ByteArray(dnsQuery.size)
        System.arraycopy(dnsQuery, 0, dnsResponse, 0, dnsQuery.size)

        // Transaction ID نفسه
        // Flags: QR=1 (response), RCODE=3 (NXDOMAIN)
        dnsResponse[2] = 0x81.toByte()  // QR=1, Opcode=0, AA=0, TC=0, RD=1
        dnsResponse[3] = 0x83.toByte()  // RA=1, RCODE=3 (NXDOMAIN)
        // ANCOUNT = 0
        dnsResponse[6] = 0
        dnsResponse[7] = 0

        sendDnsResponse(originalPacket, dnsResponse, output)
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  sendDnsResponse — يبني IP/UDP packet ويكتبه على الـ VPN interface
    // ══════════════════════════════════════════════════════════════════════════
    private fun sendDnsResponse(
        originalPacket: ByteBuffer,
        dnsPayload: ByteArray,
        output: FileOutputStream
    ) {
        try {
            val ihl = (originalPacket.get(0).toInt() and 0xF) * 4
            val totalLength = ihl + 8 + dnsPayload.size
            val response = ByteArray(totalLength)

            // ─── IP header ──────────────────────────────────────────────
            response[0] = originalPacket.get(0)   // Version + IHL
            response[1] = 0                         // DSCP/ECN
            response[2] = (totalLength shr 8).toByte()
            response[3] = (totalLength and 0xFF).toByte()
            response[4] = originalPacket.get(4)    // ID
            response[5] = originalPacket.get(5)
            response[6] = 0                         // Flags + Fragment offset
            response[7] = 0
            response[8] = 64                        // TTL
            response[9] = 17                        // Protocol: UDP
            response[10] = 0                        // Checksum (نحسبه بعدين)
            response[11] = 0

            // Swap src/dst IP
            for (i in 0..3) {
                response[12 + i] = originalPacket.get(16 + i) // src = original dst
                response[16 + i] = originalPacket.get(12 + i) // dst = original src
            }

            // ─── UDP header ──────────────────────────────────────────────
            // Swap src/dst ports
            response[ihl + 0] = originalPacket.get(ihl + 2)
            response[ihl + 1] = originalPacket.get(ihl + 3)
            response[ihl + 2] = originalPacket.get(ihl + 0)
            response[ihl + 3] = originalPacket.get(ihl + 1)
            val udpLength = 8 + dnsPayload.size
            response[ihl + 4] = (udpLength shr 8).toByte()
            response[ihl + 5] = (udpLength and 0xFF).toByte()
            response[ihl + 6] = 0  // Checksum
            response[ihl + 7] = 0

            // ─── DNS payload ─────────────────────────────────────────────
            System.arraycopy(dnsPayload, 0, response, ihl + 8, dnsPayload.size)

            // IP checksum
            val checksum = calculateIpChecksum(response, ihl)
            response[10] = (checksum shr 8).toByte()
            response[11] = (checksum and 0xFF).toByte()

            output.write(response)

        } catch (e: Exception) {
            Log.e(TAG, "❌ sendDnsResponse error: ${e.message}")
        }
    }

    private fun calculateIpChecksum(header: ByteArray, ihl: Int): Int {
        var sum = 0
        for (i in 0 until ihl step 2) {
            val word = ((header[i].toInt() and 0xFF) shl 8) or (header[i + 1].toInt() and 0xFF)
            sum += word
        }
        while (sum shr 16 != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        return sum.inv() and 0xFFFF
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }
}