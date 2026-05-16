import 'dart:typed_data';

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

  // ✅ FIX: يقبل Uint8List بدل file path — zero disk IO
  // الـ bytes بتيجي من thumbnailData() مباشرة من memory
  Future<ScoredResult> score(Uint8List imageBytes) async {
    // ✅ OPT: نشغّل الـ NSFW model أول — لو النتيجة واضحة نوقف الباقي
    // هيوفر 25% من الـ CPU في الحالات الواضحة (NSFW جداً أو SFW جداً)
    final nsfw = await nsfwService.predict(imageBytes);

    // ✅ Early exit للحالات الواضحة — مش محتاجين Face/Skin
    if (nsfw.nsfw > 0.85 || nsfw.sfw > 0.85) {
      final nsfwScore = nsfw.nsfw;
      return ScoredResult(
        weighted: (nsfwScore * wNsfw).clamp(0.0, 1.0),
        nsfwScore: nsfwScore,
        faceScore: 0.0,
        skinScore: 0.0,
        rawFaceScore: 0.0,
        rawSkinScore: 0.0,
        amplifier: 0.0,
        rawNsfw: nsfw,
      );
    }

    // ✅ المنطقة الرمادية — نشغّل Face/Skin بالتوازي لتحسين القرار
    final results = await Future.wait([
      faceService.analyze(imageBytes),
      skinService.analyze(imageBytes),
    ]);

    final face = results[0] as FaceResult;
    final skin = results[1] as SkinResult;
    final nsfwScore = nsfw.nsfw;

    // ✅ حساب معامل التأثير لـ Face و Skin بناءً على درجة NSFW
    final double amplifier;
    if (nsfwScore < _nsfwLowThreshold) {
      amplifier = 0.0;
    } else if (nsfwScore > _nsfwHighThreshold) {
      amplifier = 1.0;
    } else {
      amplifier = (nsfwScore - _nsfwLowThreshold) /
          (_nsfwHighThreshold - _nsfwLowThreshold);
    }

    final rawFaceScore = face.hasFace ? (face.faceCount == 1 ? 0.5 : 0.3) : 0.0;
    final faceScore = rawFaceScore * amplifier;
    final rawSkinScore = skin.ratio;
    final skinScore = rawSkinScore * amplifier;

    final weighted =
        (nsfwScore * wNsfw) + (skinScore * wSkin) + (faceScore * wFace);

    return ScoredResult(
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
  // ✅ FIX: أُزيل حقل path — ScoredResult لا يحتاج path بعد التحول لـ bytes
  final double weighted;
  final double nsfwScore;
  final double faceScore;   // بعد تطبيق الـ amplifier
  final double skinScore;   // بعد تطبيق الـ amplifier
  final double rawFaceScore; // قبل الـ amplifier
  final double rawSkinScore; // قبل الـ amplifier
  final double amplifier;    // معامل تأثير Face/Skin (0.0 → 1.0)
  final NsfwResult rawNsfw;

  const ScoredResult({
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
