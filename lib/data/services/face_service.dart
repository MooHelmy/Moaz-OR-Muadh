import 'dart:io';

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

  Future<FaceResult> analyze(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final faces = await _detector.processImage(inputImage);
      return FaceResult(hasFace: faces.isNotEmpty, faceCount: faces.length);
    } catch (_) {
      return const FaceResult(hasFace: false, faceCount: 0);
    }
  }

  void dispose() => _detector.close();
}
