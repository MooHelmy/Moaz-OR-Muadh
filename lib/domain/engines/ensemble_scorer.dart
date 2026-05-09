import 'package:medi_guard/data/services/face_service.dart';
import 'package:medi_guard/data/services/nsfw_service.dart';
import 'package:medi_guard/data/services/skin_service.dart';

class EnsembleScorer {
  final NsfwService nsfwService;
  final FaceService faceService;
  final SkinService skinService;

  // ===== أوزان الـ ensemble =====
  // رفعنا وزن NSFW لأن موديل Marqo أقوى بكتير من mobilenet القديم
  static const double wNsfw = 0.65;
  static const double wSkin = 0.20;
  static const double wFace = 0.15;

  EnsembleScorer({
    required this.nsfwService,
    required this.faceService,
    required this.skinService,
  });

  Future<ScoredResult> score(String path) async {
    // ✅ الـ 3 موديلات بيشتغلوا بالتوازي
    final results = await Future.wait([
      nsfwService.predict(path),
      faceService.analyze(path),
      skinService.analyze(path),
    ]);

    final nsfw = results[0] as NsfwResult;
    final face = results[1] as FaceResult;
    final skin = results[2] as SkinResult;

    // ✅ موديل Marqo بيعطينا درجة NSFW مباشرة — مش محتاجين نعمل تركيب معقد
    // nsfw.nsfw = الاحتمال الكلي لكل المحتوى غير اللائق
    final nsfwScore = nsfw.nsfw;

    // درجة الوجه: لو فيه وجه واحد = مريب أكتر من لو فيه وجوه كتير
    final faceScore = face.hasFace ? (face.faceCount > 1 ? 0.3 : 0.5) : 0.0;

    final skinScore = skin.ratio;

    final weighted =
        (nsfwScore * wNsfw) + (skinScore * wSkin) + (faceScore * wFace);

    return ScoredResult(
      path: path,
      weighted: weighted.clamp(0.0, 1.0),
      nsfwScore: nsfwScore,
      faceScore: faceScore,
      skinScore: skinScore,
      rawNsfw: nsfw,
    );
  }
}

class ScoredResult {
  final String path;
  final double weighted;
  final double nsfwScore;
  final double faceScore;
  final double skinScore;
  final NsfwResult rawNsfw;

  const ScoredResult({
    required this.path,
    required this.weighted,
    required this.nsfwScore,
    required this.faceScore,
    required this.skinScore,
    required this.rawNsfw,
  });
}
