// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medi_guard/core/theme/theme_provider.dart';
// import 'package:url_launcher/url_launcher.dart';

class CustomTopBar extends ConsumerWidget {
  const CustomTopBar({super.key});

  void _showCompanyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withOpacity(0.12),
                border: Border.all(color: const Color(0xFF10B981), width: 2),
              ),
              child: const Center(
                child: Text(
                  'β',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'βTech',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'شركة βTech للحلول التقنية المتقدمة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'تطبيق معاذ — حماية ذكية لك ولعائلتك',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'إغلاق',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Navigator.pop(ctx);
              // final url = Uri.parse('https://btech.sa'); // ← غيّر الرابط
              // if (await canLaunchUrl(url)) {
              //   await launchUrl(url, mode: LaunchMode.externalApplication);
              // }
            },
            icon: const Icon(Icons.open_in_browser_rounded, size: 16),
            label: const Text('زيارة الموقع'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeNotifierProvider);
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => _showCompanyDialog(context),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: const Color(0xFF10B981),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: Text(
                'β',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: !isDarkMode
                      ? const Color(0xFF551a8b)
                      : const Color(0xFF10B981),
                ),
              ),
            ),
          ),
          Text(
            "مَعاذ",
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ref.read(themeNotifierProvider.notifier).toggleTheme();
                },
                borderRadius: BorderRadius.circular(50),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    size: 20,
                    color: isDarkMode ? Colors.amber : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
