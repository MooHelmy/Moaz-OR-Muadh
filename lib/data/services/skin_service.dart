import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class SkinResult {
  final double ratio;
  const SkinResult({required this.ratio});
}

class SkinService {
  Future<SkinResult> analyze(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return const SkinResult(ratio: 0.0);

    final resized = img.copyResize(image, width: 100, height: 100);
    int skinPixels = 0;
    int totalPixels = 0;

    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        if (_isSkinColor(r, g, b)) skinPixels++;
        totalPixels++;
      }
    }

    final ratio = skinPixels / totalPixels;
    debugPrint('Skin ratio → ${ratio.toStringAsFixed(3)} '
        '($skinPixels/$totalPixels pixels)');

    return SkinResult(ratio: ratio);
  }

  // ✅ Fix: دمجنا 3 rules مختلفة عشان يشمل ألوان البشرة من فاتح لغامق
  bool _isSkinColor(int r, int g, int b) {
    // Rule 1: RGB-based (Kovac et al.) — للبشرة الفاتحة والمتوسطة
    final rule1 =
        r > 95 && g > 40 && b > 20 && (r - g).abs() > 15 && r > g && r > b;

    // Rule 2: للبشرة الداكنة
    final rule2 = r > 60 && g > 30 && b > 15 && r > b && (r - b) > 20 && r > 80;

    // Rule 3: HSV-based approximation — يمسك ألوان أكتر
    final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
    final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
    final saturation = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
    final rule3 = saturation > 0.1 && saturation < 0.8 && r > 60 && r > b;

    return rule1 || rule2 || rule3;
  }
}
