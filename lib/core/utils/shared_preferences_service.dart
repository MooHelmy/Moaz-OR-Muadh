import 'package:shared_preferences/shared_preferences.dart';

class SharePreferencesService {
  static Future<void> saveInstallDate() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey('install_date')) {
      await prefs.setString('install_date', DateTime.now().toIso8601String());
    }
  }

  static Future<DateTime?> getInstallDate() async {
    final prefs = await SharedPreferences.getInstance();
    final installDateString = prefs.getString('install_date');
    if (installDateString == null) return null;
    return DateTime.parse(installDateString);
  }

  static Future<Map<String, int>> getUsageDuration() async {
    final prefs = await SharedPreferences.getInstance();

    final installDateString = prefs.getString('install_date');

    if (installDateString == null) {
      return {
        'days': 0,
        'hours': 0,
        'minutes': 0,
      };
    }

    final installDate = DateTime.parse(installDateString);
    final now = DateTime.now();

    final difference = now.difference(installDate);

    return {
      'days': difference.inDays,
      'hours': difference.inHours % 24,
      'minutes': difference.inMinutes % 60,
    };
  }
}
