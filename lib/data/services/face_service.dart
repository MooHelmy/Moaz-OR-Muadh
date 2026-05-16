import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceResult {
  final bool hasFace;
  final int faceCount;
  const FaceResult({required this.hasFace, required this.faceCount});
}

class FaceService {
  late final FaceDetector _detector;

  FaceService() {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableLandmarks: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  // ✅ FIX: InputImage.fromBytes تحتاج raw BGRA pixels — مش JPEG bytes
  // الكود القديم كان بيمرر JPEG مباشرة → ML Kit بيفشل صامت (0 faces دايماً)
  // الحل: نفكّك الـ JPEG بالـ image package → نحوّله BGRA → نمرره لـ ML Kit
  Future<FaceResult> analyze(Uint8List imageBytes) async {
    try {
      // 1. فكّ الـ JPEG في memory
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null)
        return const FaceResult(hasFace: false, faceCount: 0);

      // 2. resize لـ 320x320 — كافي للكشف عن وجوه وأسرع من 384
      const targetSize = 320;
      final resized = img.copyResize(
        decoded,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.linear,
      );

      // 3. حوّل لـ BGRA raw bytes (اللي يتوقعه InputImage.fromBytes)
      final bgraBytes = _toBgra(resized, targetSize);

      // 4. مرّر لـ ML Kit
      final inputImage = InputImage.fromBytes(
        bytes: bgraBytes,
        metadata: InputImageMetadata(
          size: Size(targetSize.toDouble(), targetSize.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: targetSize * 4, // 4 bytes per pixel (BGRA)
        ),
      );

      final faces = await _detector.processImage(inputImage);
      return FaceResult(hasFace: faces.isNotEmpty, faceCount: faces.length);
    } catch (_) {
      return const FaceResult(hasFace: false, faceCount: 0);
    }
  }

  /// يحوّل img.Image إلى raw BGRA Uint8List
  Uint8List _toBgra(img.Image image, int size) {
    final bytes = Uint8List(size * size * 4);
    int offset = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final px = image.getPixel(x, y);
        bytes[offset++] = px.b.toInt(); // B
        bytes[offset++] = px.g.toInt(); // G
        bytes[offset++] = px.r.toInt(); // R
        bytes[offset++] = 255; // A
      }
    }
    return bytes;
  }

  void dispose() => _detector.close();
}
