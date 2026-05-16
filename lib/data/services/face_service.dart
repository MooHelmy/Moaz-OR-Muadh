import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

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

  // ✅ FIX: يقبل Uint8List بدل file path — zero disk IO
  // InputImage.fromBytes() يمرر الـ bytes مباشرة للـ ML Kit في memory
  Future<FaceResult> analyze(Uint8List imageBytes) async {
    try {
      final inputImage = InputImage.fromBytes(
        bytes: imageBytes,
        metadata: InputImageMetadata(
          size: const Size(224, 224),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: 224 * 4,
        ),
      );
      final faces = await _detector.processImage(inputImage);
      return FaceResult(hasFace: faces.isNotEmpty, faceCount: faces.length);
    } catch (_) {
      return const FaceResult(hasFace: false, faceCount: 0);
    }
  }

  void dispose() => _detector.close();
}
