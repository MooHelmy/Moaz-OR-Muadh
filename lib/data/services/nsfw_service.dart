// ══════════════════════════════════════════════════════════════════════════════
//  nsfw_service.dart — Production-Ready ONNX Inference Service
//  Version: 3.0.0 — Full rewrite
//
//  Design guarantees:
//    ✅ Singleton — одного instance на весь lifetime app
//    ✅ Thread-safe initialization (Completer-based mutex)
//    ✅ Zero force-unwrap (!) на всех execution paths
//    ✅ Resilient: auto session recovery upon crash
//    ✅ Inflight tracking — dispose waits for all active inferences
//    ✅ Structured logging for every failure case
//    ✅ Architecture ready for: quantized ONNX, GPU delegates, batching
// ══════════════════════════════════════════════════════════════════════════════

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

// ──────────────────────────────────────────────────────────────────────────────
// 1. DATA MODELS
// ──────────────────────────────────────────────────────────────────────────────

/// نتيجة inference — immutable value object.
final class NsfwResult {
  final double nsfw;
  final double sfw;

  const NsfwResult({required this.nsfw, required this.sfw});

  // Aliases للـ backward compatibility مع باقي الكود.
  double get porn => nsfw;
  double get hentai => 0.0;
  double get sexy => 0.0;
  double get neutral => sfw;
  double get drawings => 0.0;

  bool get isNsfw => nsfw > sfw;

  /// Margin بين الـ classes — كلما زاد كلما كان القرار أوضح.
  double get margin => (nsfw - sfw).abs();

  @override
  String toString() => 'NsfwResult(nsfw=${nsfw.toStringAsFixed(4)}, '
      'sfw=${sfw.toStringAsFixed(4)}, margin=${margin.toStringAsFixed(4)})';
}

// ──────────────────────────────────────────────────────────────────────────────
// 2. SERVICE STATE
// ──────────────────────────────────────────────────────────────────────────────

enum NsfwServiceState {
  idle, // لم يُهيأ بعد
  loading, // initialize() جارية
  ready, // جاهز للـ inference
  failed, // فشل قابل للاسترداد
  disposing, // dispose() جارية
  disposed, // أُغلق نهائياً
}

// ──────────────────────────────────────────────────────────────────────────────
// 3. CONFIGURATION
// ──────────────────────────────────────────────────────────────────────────────

/// كل ثوابت الـ model في مكان واحد — سهل التغيير عند quantization أو re-export.
final class _Cfg {
  // Model
  static const String modelAsset = 'assets/models/model.onnx';
  static const String inputName = 'pixel_values';
  static const String outputName = 'logits';

  // Preprocessing
  static const int inputSize = 384;
  static const double normMean = 0.5;
  static const double normStd = 0.5;

  // Warmup — صورة أصغر لتجنب تأخير أول inference حقيقي
  static const int warmupSize = 64;

  // Timeouts
  static const Duration initTimeout = Duration(seconds: 30);
  static const Duration inferTimeout = Duration(seconds: 15);
  static const Duration preprocessLimit = Duration(seconds: 10);
  static const Duration warmupTimeout = Duration(seconds: 20);
  static const Duration drainTimeout = Duration(seconds: 15);
  static const Duration recoveryDelay = Duration(seconds: 2);

  // Retry policy
  static const int maxRecoveries = 3;
}

// ──────────────────────────────────────────────────────────────────────────────
// 4. STRUCTURED LOGGER
// ──────────────────────────────────────────────────────────────────────────────

abstract final class _Log {
  static const _tag = '[NsfwService]';

  static void i(String msg) => _out('✅', msg);
  static void w(String msg, [Object? e]) => _out('⚠️', msg, e);
  static void e(String msg, [Object? e]) => _out('❌', msg, e);

  static void _out(String icon, String msg, [Object? err]) {
    final line =
        err != null ? '$icon $_tag $msg\n    ↳ $err' : '$icon $_tag $msg';

    // في debug mode — debugPrint مشان يظهر في console.
    // في release — استبدل بـ Crashlytics.instance.log() أو Sentry.
    if (kDebugMode) {
      debugPrint(line);
    } else {
      print(line); // production logging hook
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 5. ISOLATE PREPROCESSING
//    Top-level functions — شرط compute() إنها تكون خارج أي class.
// ──────────────────────────────────────────────────────────────────────────────

/// Args object لـ compute() — كل ما يحتاجه الـ isolate في struct واحد.
final class _PreprocessArgs {
  final String imagePath;
  final int size;
  final double mean;
  final double std;

  const _PreprocessArgs(this.imagePath, this.size, this.mean, this.std);
}

/// يشتغل في isolate منفصل — zero UI jank.
///
/// Optimizations:
///   • Float32List allocated مرة واحدة (no intermediate lists)
///   • CHW layout محسوب مباشرة بدون transpose
///   • Offsets محسوبة قبل الـ loops
Future<Float32List> _preprocessIsolate(_PreprocessArgs a) async {
  final bytes = await File(a.imagePath).readAsBytes();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Failed to decode image: ${a.imagePath}');
  }

  final resized = img.copyResize(
    decoded,
    width: a.size,
    height: a.size,
    interpolation: img.Interpolation.linear, // أسرع من cubic مع دقة كافية
  );

  final pixels = a.size * a.size;
  final buffer = Float32List(3 * pixels);
  final g = pixels; // Green channel offset
  final b = 2 * pixels; // Blue  channel offset
  final mean = a.mean;
  final std = a.std;

  for (var y = 0; y < a.size; y++) {
    final row = y * a.size;
    for (var x = 0; x < a.size; x++) {
      final px = resized.getPixel(x, y);
      final idx = row + x;
      buffer[idx] = (px.r / 255.0 - mean) / std; // R plane
      buffer[g + idx] = (px.g / 255.0 - mean) / std; // G plane
      buffer[b + idx] = (px.b / 255.0 - mean) / std; // B plane
    }
  }

  return buffer;
}

/// Warmup tensor — صورة سوداء في الذاكرة، بدون I/O.
/// كل القيم = (0/255 - 0.5) / 0.5 = -1.0
Float32List _buildWarmupTensor(int size) {
  final buf = Float32List(3 * size * size);
  buf.fillRange(0, buf.length, -1.0);
  return buf;
}

// ──────────────────────────────────────────────────────────────────────────────
// 6. NSFW SERVICE — Singleton, Thread-safe, Resilient
// ──────────────────────────────────────────────────────────────────────────────

class NsfwService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final NsfwService _inst = NsfwService._();
  factory NsfwService() => _inst;
  NsfwService._();

  // ── Internal state ─────────────────────────────────────────────────────────
  OrtSession? _session;
  NsfwServiceState _state = NsfwServiceState.idle;
  int _recoveries = 0;

  /// Completer-based mutex — يمنع تعدد initialize() في نفس الوقت.
  /// كل caller ينتظر نفس الـ future حتى يكتمل الـ init.
  Completer<void>? _initLock;

  /// عداد الـ inferences النشطة — dispose ينتظر حتى يصل لـ 0.
  int _inflight = 0;
  final _drainedSignal = _ResettableCompleter();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// State الحالية — مفيدة لـ UI diagnostics وlogging.
  NsfwServiceState get state => _state;

  /// هل الـ service جاهز للـ inference؟
  bool get isReady => _state == NsfwServiceState.ready;

  // ── initialize() ───────────────────────────────────────────────────────────

  /// يحمّل الـ model ويُجهّز الـ session.
  ///
  /// Thread-safe: استدعاؤه من عدة places في نفس الوقت آمن تماماً.
  /// Lazy: ممكن تستدعيه يدوياً أو يتعمل تلقائياً من predict().
  Future<void> initialize() async {
    switch (_state) {
      case NsfwServiceState.ready:
        return; // ✅ جاهز — ما في حاجة

      case NsfwServiceState.loading:
        // ✅ في منتصف init — انتظر نفس الـ lock بدلاً من بدء init جديدة
        _Log.i('initialize() — awaiting ongoing init');
        final lock = _initLock;
        if (lock != null) await lock.future;
        return;

      case NsfwServiceState.disposing:
      case NsfwServiceState.disposed:
        throw StateError(
          'initialize() called on a disposed NsfwService. state=$_state',
        );

      case NsfwServiceState.failed:
        if (_recoveries >= _Cfg.maxRecoveries) {
          throw StateError(
            'NsfwService permanently failed after ${_Cfg.maxRecoveries} '
            'recovery attempts.',
          );
        }
        _Log.w('initialize() — retrying after failure '
            '(attempt ${_recoveries + 1}/${_Cfg.maxRecoveries})');
        _state = NsfwServiceState.idle; // reset للمحاولة الجديدة
        break;

      case NsfwServiceState.idle:
        break;
    }

    // ── فتح الـ mutex ──────────────────────────────────────────────────────
    _initLock = Completer<void>();
    _state = NsfwServiceState.loading;

    try {
      await _loadModel().timeout(
        _Cfg.initTimeout,
        onTimeout: () => throw TimeoutException(
          'Model load timed out (${_Cfg.initTimeout.inSeconds}s)',
        ),
      );

      await _warmup(); // non-fatal — ما يوقفش الـ init لو فشل

      _state = NsfwServiceState.ready;
      _recoveries = 0;
      _Log.i('initialized ✓');
      _initLock?.complete();
    } catch (e) {
      _state = NsfwServiceState.failed;
      _Log.e('initialization failure', e);
      _initLock?.completeError(e);
      rethrow;
    }
  }

  // ── predict() ──────────────────────────────────────────────────────────────

  /// يحلل صورة ويرجع [NsfwResult].
  ///
  /// • Lazy init — يحمّل الـ model تلقائياً لو لسه ما اتعملش.
  /// • Timeout-protected — ما يبقاش معلقاً إلى الأبد.
  /// • Session recovery — يعيد المحاولة مرة عند session crash.
  /// • Inflight guard — يحمي dispose من الـ race condition.
  Future<NsfwResult> predict(String imagePath) async {
    _assertUsable();

    if (_state != NsfwServiceState.ready) {
      await initialize();
    }

    return _guardedInference(() => _runPipeline(imagePath));
  }

  // ── dispose() ──────────────────────────────────────────────────────────────

  /// تنظيف نهائي — ينتظر كل الـ inferences النشطة قبل الإغلاق.
  Future<void> dispose() async {
    if (_state == NsfwServiceState.disposing ||
        _state == NsfwServiceState.disposed) return;

    _state = NsfwServiceState.disposing;
    _Log.i('dispose() — inflight=$_inflight');

    // انتظر drain الـ inflight operations
    if (_inflight > 0) {
      await _drainedSignal.future.timeout(
        _Cfg.drainTimeout,
        onTimeout: () {
          _Log.w('dispose() drain timeout — forcing close');
        },
      );
    }

    await _closeSession();
    _state = NsfwServiceState.disposed;
    _Log.i('disposed ✓');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIVATE — Inference pipeline
  // ──────────────────────────────────────────────────────────────────────────

  /// كامل الـ pipeline: preprocess → inference → extract result.
  Future<NsfwResult> _runPipeline(String imagePath) async {
    try {
      return await _executePipeline(imagePath);
    } on StateError catch (e) {
      // Session corruption — محاولة recovery مرة واحدة
      if (_recoveries < _Cfg.maxRecoveries &&
          _state == NsfwServiceState.ready) {
        _Log.w('session error — attempting recovery', e);
        await _recoverSession();
        _Log.i('retrying inference after recovery');
        return _executePipeline(imagePath); // second and final attempt
      }
      _Log.e('inference failure — no recovery attempts left', e);
      rethrow;
    } catch (e) {
      _Log.e('inference failure', e);
      rethrow;
    }
  }

  Future<NsfwResult> _executePipeline(String imagePath) async {
    _assertUsable();

    // ── Step 1: Preprocessing في isolate ─────────────────────────────────
    final args =
        _PreprocessArgs(imagePath, _Cfg.inputSize, _Cfg.normMean, _Cfg.normStd);

    final buffer = await compute(_preprocessIsolate, args).timeout(
      _Cfg.preprocessLimit,
      onTimeout: () => throw TimeoutException(
        'Preprocessing timed out: $imagePath',
      ),
    );

    // ── Guard بعد isolate — ممكن dispose اتعمل أثناءه ─────────────────────
    _assertUsable();

    final session = _session;
    if (session == null) {
      throw StateError(
        'Session became null after preprocessing. state=$_state',
      );
    }

    // ── Step 2: Build input tensor ───────────────────────────────────────
    final inputTensor = await OrtValue.fromList(
      buffer,
      [1, 3, _Cfg.inputSize, _Cfg.inputSize],
    );

    // ── Step 3: Inference مع timeout ─────────────────────────────────────
    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run({_Cfg.inputName: inputTensor}).timeout(
        _Cfg.inferTimeout,
        onTimeout: () => throw TimeoutException(
          'Inference timed out (${_Cfg.inferTimeout.inSeconds}s): '
          '$imagePath',
        ),
      );

      // ── Step 4: Null-safe result extraction ──────────────────────────
      return await _extractResult(outputs);
    } finally {
      // ── Cleanup — دايماً حتى عند exceptions ─────────────────────────
      await _disposeTensor(inputTensor);
      if (outputs != null) await _disposeOutputs(outputs);
    }
  }

  /// استخرج النتيجة من outputs مع null-safety كاملة وvalidation شامل.
  Future<NsfwResult> _extractResult(Map<String, OrtValue> outputs) async {
    // ── Null-safe output lookup ───────────────────────────────────────────
    final logitsTensor = outputs[_Cfg.outputName];
    if (logitsTensor == null) {
      final available = outputs.keys.join(', ');
      throw StateError(
        'Model output key "${_Cfg.outputName}" not found. '
        'Available: [$available]. '
        'Update _Cfg.outputName to match your model export.',
      );
    }

    // ── Extract values ────────────────────────────────────────────────────
    final flat = await logitsTensor.asFlattenedList();

    if (flat.length < 2) {
      throw StateError(
        'logits tensor has ${flat.length} element(s), expected ≥ 2. '
        'Model architecture mismatch — check ONNX export.',
      );
    }

    final l0 = (flat[0] as num).toDouble();
    final l1 = (flat[1] as num).toDouble();

    // ── NaN/Inf guard — يحمي من broken quantized models ─────────────────
    if (!l0.isFinite || !l1.isFinite) {
      throw StateError(
        'Non-finite logits: [$l0, $l1]. '
        'Model may produce NaN/Inf — check quantization or model corruption.',
      );
    }

    final probs = _softmax([l0, l1]);
    return NsfwResult(nsfw: probs[0], sfw: probs[1]);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIVATE — Model lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadModel() async {
    _Log.i('loading model: ${_Cfg.modelAsset}');
    // ─ Architecture hook: لدعم GPU delegates أضف SessionOptions هنا ─────
    //   final options = OrtSessionOptions()..addCoreMLDelegate();
    //   _session = await ort.createSessionFromAsset(path, options: options);
    // ─────────────────────────────────────────────────────────────────────
    final ort = OnnxRuntime();
    _session = await ort.createSessionFromAsset(_Cfg.modelAsset);
    _Log.i('model loaded');
  }

  /// Warmup inference — يُحرّك الـ JIT cache لتحسين أول inference حقيقي.
  /// Non-fatal: لو فشل الـ warmup نكمل بدونه.
  Future<void> _warmup() async {
    _Log.i('warmup starting ...');
    final session = _session;
    if (session == null) return;

    final size = _Cfg.warmupSize;
    final tensor = _buildWarmupTensor(size);

    OrtValue? warmInput;
    Map<String, OrtValue>? warmOut;
    try {
      warmInput = await OrtValue.fromList(tensor, [1, 3, size, size]);
      warmOut = await session
          .run({_Cfg.inputName: warmInput}).timeout(_Cfg.warmupTimeout);
      _Log.i('warmup complete ✓');
    } catch (e) {
      _Log.w('warmup skipped — non-fatal', e);
    } finally {
      if (warmInput != null) await _disposeTensor(warmInput);
      if (warmOut != null) await _disposeOutputs(warmOut);
    }
  }

  Future<void> _recoverSession() async {
    _recoveries++;
    _Log.w('recovering session '
        '(attempt $_recoveries/${_Cfg.maxRecoveries})');

    await _closeSession();
    await Future.delayed(_Cfg.recoveryDelay);

    try {
      await _loadModel().timeout(_Cfg.initTimeout);
      _Log.i('session recovered ✓');
    } catch (e) {
      _state = NsfwServiceState.failed;
      _Log.e('session recovery failed', e);
      rethrow;
    }
  }

  Future<void> _closeSession() async {
    try {
      await _session?.close();
    } catch (e) {
      _Log.w('session.close() error (ignored)', e);
    } finally {
      _session = null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIVATE — Inflight guard
  // ──────────────────────────────────────────────────────────────────────────

  /// يُغلّف أي inference operation ويتتبع الـ inflight count.
  Future<T> _guardedInference<T>(Future<T> Function() fn) async {
    _inflight++;
    _drainedSignal.reset(); // يفتح الـ gate لما في ops نشطة

    try {
      return await fn();
    } finally {
      _inflight--;
      if (_inflight == 0) {
        _drainedSignal.complete(); // signal للـ dispose
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIVATE — Math
  // ──────────────────────────────────────────────────────────────────────────

  List<double> _softmax(List<double> logits) {
    final max = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - max)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIVATE — Guards & safe dispose
  // ──────────────────────────────────────────────────────────────────────────

  void _assertUsable() {
    if (_state == NsfwServiceState.disposing ||
        _state == NsfwServiceState.disposed) {
      throw StateError(
        'NsfwService used after dispose. state=$_state',
      );
    }
  }

  Future<void> _disposeTensor(OrtValue t) async {
    try {
      await t.dispose();
    } catch (e) {
      _Log.w('tensor.dispose() error (ignored)', e);
    }
  }

  Future<void> _disposeOutputs(Map<String, OrtValue> outputs) async {
    for (final e in outputs.entries) {
      try {
        await e.value.dispose();
      } catch (err) {
        _Log.w('output[${e.key}].dispose() error (ignored)', err);
      }
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 7. RESETTABLE COMPLETER UTILITY
//    يسمح بـ reset الـ completer بعد complete — لإشارة drain متكررة.
// ──────────────────────────────────────────────────────────────────────────────

class _ResettableCompleter {
  Completer<void> _inner = Completer<void>()..complete();

  Future<void> get future => _inner.future;

  void complete() {
    if (!_inner.isCompleted) _inner.complete();
  }

  void reset() {
    if (_inner.isCompleted) {
      _inner = Completer<void>();
    }
  }
}
