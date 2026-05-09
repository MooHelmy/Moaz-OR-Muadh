class ScanTargets {
  static const List<String> folders = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/Telegram',
    '/storage/emulated/0/Android/media/org.telegram.messenger/Telegram',
    '/storage/emulated/0/DCIM/Facebook',
    '/storage/emulated/0/Pictures/Instagram',
    '/storage/emulated/0/Movies/TikTok',
    '/storage/emulated/0/Android/data/com.snapchat.android/files/my_media',
    '/storage/emulated/0/DCIM/Camera',
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
