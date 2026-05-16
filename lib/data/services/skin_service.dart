import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class SkinResult {
  final double ratio;
  const SkinResult({required this.ratio});
}

// ✅ OPT: Top-level function للـ compute() — يشتغل في isolate منفصل
// يمنع blocking الـ UI thread أثناء تحليل البكسلات
Future<double> _analyzeSkinInIsolate(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) return 0.0;

  // ✅ OPT: تقليل من 100x100 → 64x64 = أسرع بـ 2.4x مع نفس الدقة
  final resized = img.copyResize(image, width: 64, height: 64);
  int skinPixels = 0;
  int totalPixels = 0;

  for (int y = 0; y < resized.height; y++) {
    for (int x = 0; x < resized.width; x++) {
      final pixel = resized.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();

      // Rule 1: RGB-based (Kovac et al.)
      final rule1 = r > 95 && g > 40 && b > 20 && (r - g).abs() > 15 && r > g && r > b;
      // Rule 2: للبشرة الداكنة
      final rule2 = r > 60 && g > 30 && b > 15 && r > b && (r - b) > 20 && r > 80;
      // Rule 3: HSV-based
      final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
      final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
      final saturation = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
      final rule3 = saturation > 0.1 && saturation < 0.8 && r > 60 && r > b;

      if (rule1 || rule2 || rule3) skinPixels++;
      totalPixels++;
    }
  }

  return skinPixels / totalPixels;
}

class SkinService {
  Future<SkinResult> analyze(String imagePath) async {
    try {
      // ✅ OPT: compute() = isolate منفصل → لا يبطّئ الـ UI أو الـ scan thread
      final ratio = await compute(_analyzeSkinInIsolate, imagePath);
      return SkinResult(ratio: ratio);
    } catch (_) {
      return const SkinResult(ratio: 0.0);
    }
  }
}
