import 'dart:developer';

import 'package:flutter/services.dart';

class AiBlacklistService {
  static const platform = MethodChannel('com.maadh.shield/vpn');

  // ✅ أفضل طريقة لتمرير المفتاح بأمان
  // استخدم الأمر: flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY
  // static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  // دالة التحديث الرئيسية
  static Future<void> fetchAndSyncBlacklist() async {
    try {
      List<String> aiWords;

      try {
        // 1. محاولة جلب الكلمات من الذكاء الاصطناعي مباشرة
        aiWords = await _generateWordsFromGemini();
        log("✅ تم توليد القائمة من الذكاء الاصطناعي: ${aiWords.length} كلمة");
      } catch (e) {
        log(
          "⚠️ تعذر الاتصال بالذكاء الاصطناعي ($e)، سيتم استخدام القائمة الاحتياطية.",
        );
        aiWords = _getBackupList();
      }

      // 2. تحويل القائمة لنص مفصول بفواصل
      String blacklistString = aiWords.join(",");

      // 3. إرسال القائمة إلى نظام الأندرويد (ليستخدمها الـ Accessibility)
      await platform.invokeMethod('updateBlacklist', blacklistString);
    } catch (e) {
      log("❌ فشل كلي في تحديث القائمة: $e");
    }
  }

  // دالة الاتصال بـ Gemini
  static Future<List<String>> _generateWordsFromGemini() async {
    // final model = GenerativeModel(model: 'gemini-pro', apiKey: _apiKey);

    // // نطلب منه القائمة بصيغة محددة (CSV) لسهولة المعالجة
    // final prompt = Content.text('''
    //   Generate a comma-separated list (CSV) of 100 keywords used for filtering adult content, pornography, and gambling in both Arabic and English.
    //   Do not include numbers or bullet points. Just the words separated by commas.
    //   Focus on the most common terms used in URL blocking.
    // ''');

    // final response = await model.generateContent([prompt]);
    // final text = response.text;
    // final text = kBlockListWords;

    // if (text == null || text.isEmpty) {
    //   return _getBackupList();
    // }

    // تنظيف النص وتحويله لقائمة
    // List<String> words = text
    //     .split(',')
    //     .map((e) => e.trim().toLowerCase())
    //     .where((e) => e.isNotEmpty)
    //     .toList();

    // // دمج القائمة المولدة مع القائمة الاحتياطية لضمان عدم فوات الأساسيات
    return _getBackupList();
  }

  // قائمة احتياطية في حال عدم وجود إنترنت أو فشل الـ AI
  static List<String> _getBackupList() {
    return [
      "porn",
      "sex",
      "xxx",
      "سكس",
      "xnxx",
      "sex"
          "xvideos",
      "pornhub",
      "betting",
      "casino",
      "adult",
      "hentai",
      "erotic",
      "incest",
      "boobs",
      "pussy",
      "dick",
      "cock",
      "brazzers",
      "redtube",
      "xhamster",
      "youporn",
      "tube8",
      "beeg",
      "eporner",
      "hqporner",
      "tnaflix",
      "thumbzilla",
      "chaturbate",
      "cam4",
      "livejasmin",
      "myfreecams",
      "bongacams",
      "stripchat",
      "sex.com",
      "adultfriendfinder",
    ];
  }
}
