import 'package:medi_guard/data/services/nsfw_service.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';

class DecisionEngine {
  double acceptThreshold;
  double rejectThreshold;

  DecisionEngine({
    this.acceptThreshold = 0.20, // كان 0.25
    this.rejectThreshold = 0.35, // كان 0.55 — ده كان السبب!
  });

  // ✅ قائمة مواقع إباحية معروفة في اسم الملف → حذف فوري بدون فحص
  // ✅ FIX: أزلنا 'sexy', 'nude', 'naked', 'nsfw' من القائمة
  // أسماء عادية جداً تحتويها: sexy_back_song.jpg, nude_lipstick_ad.jpg
  // الكلمات دي تُكشف بالـ AI model — مش بمطابقة اسم الملف
  // باقي الكلمات دي domain names حقيقية → حذف فوري آمن
  static const _blockedKeywords = [
    'xnxx',
    'xvideos',
    'pornhub',
    'xhamster',
    'redtube',
    'youporn',
    'brazzers',
    'bangbros',
    'porn',
    'xxx',
  ];

  MediaDecision decide(ScoredResult scored, NsfwResult rawNsfw,
      {String? filePath}) {
    // ✅ 1. اسم الملف — لو فيه كلمة إباحية واضحة → REJECT فوري
    if (filePath != null) {
      final nameLower = filePath.split('/').last.toLowerCase();
      for (final kw in _blockedKeywords) {
        if (nameLower.contains(kw)) {
          return MediaDecision.reject(
            reason: 'blocked_filename ($kw)',
            confidence: 1.0,
          );
        }
      }
    }

    // ✅ 2. لو الموديل شايف NSFW أكبر من SFW → REJECT مباشرة
    // ده أبسط وأقوى من أي threshold ثابت
    if (rawNsfw.nsfw > rawNsfw.sfw) {
      return MediaDecision.reject(
        reason:
            'nsfw>sfw (${rawNsfw.nsfw.toStringAsFixed(3)} vs ${rawNsfw.sfw.toStringAsFixed(3)})',
        confidence: rawNsfw.nsfw,
      );
    }

    // ✅ 3. Ensemble score
    if (scored.weighted >= rejectThreshold) {
      return MediaDecision.reject(
        reason: 'ensemble_score (${scored.weighted.toStringAsFixed(3)})',
        confidence: scored.weighted,
      );
    }

    if (scored.weighted <= acceptThreshold) {
      return MediaDecision.accept(confidence: 1 - scored.weighted);
    }

    return MediaDecision.review(confidence: scored.weighted);
  }
}

enum DecisionResult { accept, review, reject }

class MediaDecision {
  final DecisionResult result;
  final String reason;
  final double confidence;

  const MediaDecision._({
    required this.result,
    required this.reason,
    required this.confidence,
  });

  factory MediaDecision.accept({required double confidence}) => MediaDecision._(
      result: DecisionResult.accept, reason: 'safe', confidence: confidence);

  factory MediaDecision.review({required double confidence}) => MediaDecision._(
      result: DecisionResult.review,
      reason: 'needs_review',
      confidence: confidence);

  factory MediaDecision.reject(
          {required String reason, required double confidence}) =>
      MediaDecision._(
          result: DecisionResult.reject,
          reason: reason,
          confidence: confidence);
}
