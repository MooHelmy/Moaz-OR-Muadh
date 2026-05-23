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
      "xxx",
      "سكس",
      "xvideos",
      "pornhub",
      "betting",
      "xnxx",
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
      "brazzers",
      "redtube",
      "xhamster",
      "youporn",
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
      "أفلام إباحية",
      "افلام اباحية",
      "صور عارية",
      "مقاطع إباحية",
      "porno",
      "sexe",
      "nu",
      "nue",
      "érotique",
      "erotique",
      "adulte",
      "cul",
      "bite",
      "chatte",
      "sein",
      "film porno",
      "site adulte",
      "webcam coquine",
      "porno",
      "sexo",
      "desnudo",
      "desnuda",
      "erotico",
      "erótico",
      "adulto",
      "polla",
      "coño",
      "tetas",
      "follar",
      "pelicula porno",
      "sitio adulto",
      "porno",
      "sexo",
      "desnudo",
      "desnuda",
      "erotico",
      "erótico",
      "adulto",
      "polla",
      "coño",
      "tetas",
      "follar",
      "pelicula porno",
      "sitio adulto",
      "porno",
      "nackt",
      "erotik",
      "erwachsene",
      "titten",
      "schwanz",
      "muschi",
      "pornos",
      "erotikfilm",
      "sexfilm",
      "porno",
      "sexo",
      "nu",
      "nua",
      "erotico",
      "erótico",
      "adulto",
      "buceta",
      "pau",
      "peitos",
      "foder",
      "filme porno",
      "site adulto",
      "порно",
      "секс",
      "голый",
      "голая",
      "эротика",
      "взрослые",
      "член",
      "пизда",
      "грудь",
      "трахать",
      "порнофильм",
      "порносайт",
      "porno",
      "porn",
      "seks",
      "çıplak",
      "erotik",
      "yetişkin",
      "göt",
      "amcık",
      "sik",
      "memeler",
      "sikişmek",
      "porno film",
      "yetişkin site",
      "پورنو",
      "سکس",
      "برهنه",
      "اروتیک",
      "بزرگسال",
      "کیر",
      "سینه",
      "فیلم سکسی",
      "فحش",
      "برہنہ",
      "بالغ",
      "سیکس",
      "فحش فلم",
      "فحش تصویر",
      "पोर्न",
      "सेक्स",
      "नग्न",
      "अश्लील",
      "वयस्क",
      "चूत",
      "लंड",
      "बूब्स",
      "पोर्न फिल्म",
      "porno",
      "seks",
      "telanjang",
      "erotis",
      "dewasa",
      "memek",
      "kontol",
      "payudara",
      "bokep",
      "film porno",
      "situs dewasa",
      "porno",
      "sesso",
      "nudo",
      "nuda",
      "erotico",
      "adulto",
      "cazzo",
      "figa",
      "tette",
      "scopare",
      "film porno",
      "sito adulti",
      "ポルノ",
      "セックス",
      "エロ",
      "裸",
      "アダルト",
      "エロ動画",
      "無修正",
      "アダルトサイト",
      "色情",
      "性爱",
      "裸体",
      "成人",
      "情色",
      "做爱",
      "性交",
      "色情网站",
      "成人视频",
      "포르노",
      "섹스",
      "나체",
      "에로",
      "성인",
      "야동",
      "성인사이트",
      "음란물",
      "porno",
      "seks",
      "nagi",
      "naga",
      "erotyczny",
      "dorosły",
      "cipka",
      "kutas",
      "cycki",
      "porno",
      "seks",
      "naakt",
      "erotisch",
      "volwassen",
      "kut",
      "lul",
      "tieten",
      "neuken",
      "porr",
      "naken",
      "erotisk",
      "vuxen",
      "fitta",
      "kuk",
      "bröst",
      "πορνό",
      "σεξ",
      "γυμνό",
      "ερωτικό",
      "ενήλικες",
      "porno",
      "gol",
      "goală",
      "erotic",
      "adult",
      "cur",
      "pula",
      "pizda",
      "pornó",
      "szex",
      "meztelen",
      "erotikus",
      "felnőtt",
      "porno",
      "sex",
      "nahý",
      "nahá",
      "erotický",
      "dospělý",
      "โป๊",
      "เซ็กส์",
      "เปลือย",
      "อีโรติก",
      "ผู้ใหญ่",
      "หนังโป๊",
      "คลิปโป๊",
      "khiêu dâm",
      "tình dục",
      "khỏa thân",
      "người lớn",
      "phim sex",
      "clip sex",
      "porn",
      "hubad",
      "malaswa",
      "para sa matatanda",
      "ponografia",
      "ngono",
      "uchi",
      "uasherati",
      "batsa",
      "zina",
      "ashewo",
      "ihe ọkụkọ",
    ];
  }
}
