class ScanTargets {
  static const List<String> folders = [
    // ─── Downloads ───────────────────────────────────────────
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',

    // ─── WhatsApp (مسارين: القديم والجديد Android 11+) ───────
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/Sent',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/Sent',

    // ─── Telegram ─────────────────────────────────────────────
    '/storage/emulated/0/Telegram',
    '/storage/emulated/0/Android/media/org.telegram.messenger/Telegram',

    // ─── DCIM كامل (Camera + Facebook + كل sub-folders) ──────
    '/storage/emulated/0/DCIM',

    // ─── Pictures كامل (Instagram + Screenshots + ...) ───────
    '/storage/emulated/0/Pictures',

    // ─── Movies/Videos ────────────────────────────────────────
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/Videos',

    // ─── Snapchat ─────────────────────────────────────────────
    '/storage/emulated/0/Android/data/com.snapchat.android/files/my_media',

    // ─── مشاركة ملفات ─────────────────────────────────────────
    '/storage/emulated/0/Shareit',
    '/storage/emulated/0/Xender',
  ];

  static const List<String> imageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  ];

  static const List<String> videoExtensions = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.3gp',
    '.webm',
  ];

  static bool isMediaFile(String path) {
    final fileName = path.split('/').last;
    // تجاهل الملفات المخفية أو الملفات المؤقتة التي تبدأ بـ . (مثل .pending)
    if (fileName.startsWith('.')) return false;

    return isImage(path) || isVideo(path);
  }

  static bool isImage(String path) {
    final ext = path.toLowerCase();
    return imageExtensions.any((e) => ext.endsWith(e));
  }

  static bool isVideo(String path) {
    final ext = path.toLowerCase();
    return videoExtensions.any((e) => ext.endsWith(e));
  }
}
