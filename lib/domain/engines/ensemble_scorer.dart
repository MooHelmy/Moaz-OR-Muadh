import 'package:medi_guard/data/services/face_service.dart';
import 'package:medi_guard/data/services/nsfw_service.dart';
import 'package:medi_guard/data/services/skin_service.dart';

class EnsembleScorer {
  final NsfwService nsfwService;
  final FaceService faceService;
  final SkinService skinService;

  // ===== أوزان الـ ensemble =====
  // NSFW model (Marqo) هو المرجع الأساسي — وزنه عالي جداً
  static const double wNsfw = 0.75;
  static const double wSkin = 0.15;
  static const double wFace = 0.10;

  // ✅ حد NSFW تحته = Face و Skin لا يؤثروا (عشان منحذفش صور عادية)
  // لو NSFW أقل من 20% → صورة safe بوضوح → Face/Skin = 0
  // لو NSFW بين 20% و 50% → Face/Skin يضربوا بمعامل أقل
  // لو NSFW فوق 50% → Face/Skin يضربوا بكامل وزنهم
  static const double _nsfwLowThreshold  = 0.20;
  static const double _nsfwHighThreshold = 0.50;

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

    final nsfwScore = nsfw.nsfw;

    // ✅ حساب معامل التأثير لـ Face و Skin بناءً على درجة NSFW
    //
    // المنطق: Face/Skin لوحدهم مش بيحكموا — بس لو NSFW model شايف
    // إن فيه حاجة مريبة، هيزودوا الـ weighted score ويساعدوا في القرار.
    //
    // لو صورة عادية (NSFW < 20%) → Face/Skin مش بيؤثروا خالص
    // لو NSFW في المنطقة الرمادية (20-50%) → Face/Skin بيؤثروا بنسبة
    // لو NSFW عالي (> 50%) → Face/Skin بيكملوا الصورة بكامل وزنهم
    final double amplifier;
    if (nsfwScore < _nsfwLowThreshold) {
      amplifier = 0.0; // NSFW model مطمن → Face/Skin لا يؤثران
    } else if (nsfwScore > _nsfwHighThreshold) {
      amplifier = 1.0; // NSFW عالي → Face/Skin بيكملوا
    } else {
      // linear interpolation بين 0 و 1
      amplifier = (nsfwScore - _nsfwLowThreshold) /
          (_nsfwHighThreshold - _nsfwLowThreshold);
    }

    // درجة الوجه: وجه واحد مع NSFW مريب = أكثر ريبة من وجوه كتيرة
    final rawFaceScore = face.hasFace ? (face.faceCount == 1 ? 0.5 : 0.3) : 0.0;
    final faceScore = rawFaceScore * amplifier;

    // درجة الجلد: بنضربها في المعامل
    final rawSkinScore = skin.ratio;
    final skinScore = rawSkinScore * amplifier;

    // Weighted ensemble
    final weighted =
        (nsfwScore * wNsfw) + (skinScore * wSkin) + (faceScore * wFace);

    return ScoredResult(
      path: path,
      weighted: weighted.clamp(0.0, 1.0),
      nsfwScore: nsfwScore,
      faceScore: faceScore,
      skinScore: skinScore,
      rawFaceScore: rawFaceScore,
      rawSkinScore: rawSkinScore,
      amplifier: amplifier,
      rawNsfw: nsfw,
    );
  }
}

class ScoredResult {
  final String path;
  final double weighted;
  final double nsfwScore;
  final double faceScore;   // بعد تطبيق الـ amplifier
  final double skinScore;   // بعد تطبيق الـ amplifier
  final double rawFaceScore; // قبل الـ amplifier
  final double rawSkinScore; // قبل الـ amplifier
  final double amplifier;    // معامل تأثير Face/Skin (0.0 → 1.0)
  final NsfwResult rawNsfw;

  const ScoredResult({
    required this.path,
    required this.weighted,
    required this.nsfwScore,
    required this.faceScore,
    required this.skinScore,
    required this.rawFaceScore,
    required this.rawSkinScore,
    required this.amplifier,
    required this.rawNsfw,
  });
}
