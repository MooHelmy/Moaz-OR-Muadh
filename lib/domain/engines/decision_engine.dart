import 'package:medi_guard/data/services/nsfw_service.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';

class DecisionEngine {
  double acceptThreshold;
  double rejectThreshold;

  DecisionEngine({
    this.acceptThreshold = 0.25,
    this.rejectThreshold = 0.55,
  });

  MediaDecision decide(ScoredResult scored, NsfwResult rawNsfw) {
    // ✅ موديل Marqo: nsfw.nsfw هو الاحتمال المباشر للمحتوى غير اللائق
    // ثقة عالية جداً → reject فوري بدون ما ننتظر الـ ensemble
    if (rawNsfw.nsfw > 0.85) {
      return MediaDecision.reject(
        reason: 'high_confidence_nsfw (marqo=${rawNsfw.nsfw.toStringAsFixed(3)})',
        confidence: rawNsfw.nsfw,
      );
    }

    // الـ ensemble score يأخذ skin و face في الاعتبار
    if (scored.weighted >= rejectThreshold) {
      return MediaDecision.reject(
        reason: 'high_ensemble_score',
        confidence: scored.weighted,
      );
    }

    if (scored.weighted <= acceptThreshold) {
      return MediaDecision.accept(confidence: 1 - scored.weighted);
    }

    // المنطقة الرمادية → review
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
