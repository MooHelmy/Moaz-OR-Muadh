// ══════════════════════════════════════════════════════════════════════════════
//  nsfw_service.dart — Production-Ready ONNX Inference Service
//  Version: 3.1.0
//
//  ✅ FIX #1: أُزيل Singleton pattern — كل isolate يعمل instance مستقلة
//             (الـ Dart isolates لا تشارك الـ heap — Singleton وهمي هنا)
//  ✅ FIX #2: dispose() آمن الآن لأن مفيش shared state بين الـ isolates
// ══════════════════════════════════════════════════════════════════════════════

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

// ──────────────────────────────────────────────────────────────────────────────
// 1. DATA MODELS
// ──────────────────────────────────────────────────────────────────────────────

final class NsfwResult {
  final double nsfw;
  final double sfw;

  const NsfwResult({required this.nsfw, required this.sfw});

  double get porn => nsfw;
  double get hentai => 0.0;
  double get sexy => 0.0;
  double get neutral => sfw;
  double get drawings => 0.0;

  bool get isNsfw => nsfw > sfw;
  double get margin => (nsfw - sfw).abs();

  @override
  String toString() => 'NsfwResult(nsfw=${nsfw.toStringAsFixed(4)}, '
      'sfw=${sfw.toStringAsFixed(4)}, margin=${margin.toStringAsFixed(4)})';
}

// ──────────────────────────────────────────────────────────────────────────────
// 2. SERVICE STATE
// ──────────────────────────────────────────────────────────────────────────────

enum NsfwServiceState {
  idle,
  loading,
  ready,
  failed,
  disposing,
  disposed,
}

// ──────────────────────────────────────────────────────────────────────────────
// 3. CONFIGURATION
// ──────────────────────────────────────────────────────────────────────────────

final class _Cfg {
  static const String modelAsset = 'assets/models/model.onnx';
  static const String inputName = 'pixel_values';
  static const String outputName = 'logits';

  static const int inputSize = 384;
  static const double normMean = 0.5;
  static const double normStd = 0.5;

  static const int warmupSize = 384;

  static const Duration initTimeout = Duration(seconds: 30);
  static const Duration inferTimeout = Duration(seconds: 10);
  static const Duration preprocessLimit = Duration(seconds: 8);
  static const Duration warmupTimeout = Duration(seconds: 15);
  static const Duration drainTimeout = Duration(seconds: 15);
  static const Duration recoveryDelay = Duration(seconds: 2);

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
    print(line);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 5. ISOLATE PREPROCESSING
// ──────────────────────────────────────────────────────────────────────────────

final class _PreprocessArgs {
  // ✅ FIX: Uint8List بدل file path — zero disk IO
  // الـ bytes بتيجي من thumbnailData() مباشرة من memory
  final Uint8List bytes;
  final int size;
  final double mean;
  final double std;

  const _PreprocessArgs(this.bytes, this.size, this.mean, this.std);
}

Future<Float32List> _preprocessIsolate(_PreprocessArgs a) async {
  final decoded = img.decodeImage(a.bytes);
  if (decoded == null) {
    throw StateError('Failed to decode image bytes (${a.bytes.length} bytes)');
  }

  final resized = img.copyResize(
    decoded,
    width: a.size,
    height: a.size,
    interpolation: img.Interpolation.linear,
  );

  final pixels = a.size * a.size;
  final buffer = Float32List(3 * pixels);
  final g = pixels;
  final b = 2 * pixels;
  final mean = a.mean;
  final std = a.std;

  for (var y = 0; y < a.size; y++) {
    final row = y * a.size;
    for (var x = 0; x < a.size; x++) {
      final px = resized.getPixel(x, y);
      final idx = row + x;
      buffer[idx] = (px.r / 255.0 - mean) / std;
      buffer[g + idx] = (px.g / 255.0 - mean) / std;
      buffer[b + idx] = (px.b / 255.0 - mean) / std;
    }
  }

  return buffer;
}

Float32List _buildWarmupTensor(int size) {
  final buf = Float32List(3 * size * size);
  buf.fillRange(0, buf.length, -1.0);
  return buf;
}

// ──────────────────────────────────────────────────────────────────────────────
// 6. NSFW SERVICE
//
// ✅ FIX #1 & #2: أُزيل Singleton pattern تماماً
//
// السبب:
//   - الـ Dart isolates لا تشارك الـ heap — كل isolate له memory مستقلة
//   - الـ Singleton (static final _inst) يُنشأ من جديد في كل isolate
//   - يعني الـ Singleton وهمي: ما بيمنعش تعدد الـ instances أصلاً
//   - لكنه بيسبب مشكلة حقيقية: لو ScanQueue اتعمل dispose في isolate واحد
//     → _state = disposed → الـ isolate التاني يلاقي service مقفولة ويـ throw
//   - الحل: factory عادي — كل isolate يعمل instance مستقلة ويـ dispose نسخته
// ──────────────────────────────────────────────────────────────────────────────

class NsfwService {
  // ✅ FIX: constructor عادي — لا Singleton
  NsfwService();

  OrtSession? _session;
  NsfwServiceState _state = NsfwServiceState.idle;
  int _recoveries = 0;

  Completer<void>? _initLock;

  int _inflight = 0;
  final _drainedSignal = _ResettableCompleter();

  NsfwServiceState get state => _state;
  bool get isReady => _state == NsfwServiceState.ready;

  Future<void> initialize() async {
    switch (_state) {
      case NsfwServiceState.ready:
        return;

      case NsfwServiceState.loading:
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
        _state = NsfwServiceState.idle;
        break;

      case NsfwServiceState.idle:
        break;
    }

    _initLock = Completer<void>();
    _state = NsfwServiceState.loading;

    try {
      await _loadModel().timeout(
        _Cfg.initTimeout,
        onTimeout: () => throw TimeoutException(
          'Model load timed out (${_Cfg.initTimeout.inSeconds}s)',
        ),
      );

      await _warmup();

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

  // ✅ FIX: يقبل Uint8List بدل file path — zero disk read
  Future<NsfwResult> predict(Uint8List imageBytes) async {
    _assertUsable();

    if (_state != NsfwServiceState.ready) {
      await initialize();
    }

    return _guardedInference(() => _runPipeline(imageBytes));
  }

  Future<void> dispose() async {
    if (_state == NsfwServiceState.disposing ||
        _state == NsfwServiceState.disposed) return;

    _state = NsfwServiceState.disposing;
    _Log.i('dispose() — inflight=$_inflight');

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

  Future<NsfwResult> _runPipeline(Uint8List imageBytes) async {
    try {
      return await _executePipeline(imageBytes);
    } on StateError catch (e) {
      if (_recoveries < _Cfg.maxRecoveries &&
          _state == NsfwServiceState.ready) {
        _Log.w('session error — attempting recovery', e);
        await _recoverSession();
        _Log.i('retrying inference after recovery');
        return _executePipeline(imageBytes);
      }
      _Log.e('inference failure — no recovery attempts left', e);
      rethrow;
    } catch (e) {
      _Log.e('inference failure', e);
      rethrow;
    }
  }

  Future<NsfwResult> _executePipeline(Uint8List imageBytes) async {
    _assertUsable();

    final args =
        _PreprocessArgs(imageBytes, _Cfg.inputSize, _Cfg.normMean, _Cfg.normStd);

    final buffer = await compute(_preprocessIsolate, args).timeout(
      _Cfg.preprocessLimit,
      onTimeout: () => throw TimeoutException(
        'Preprocessing timed out: $imagePath',
      ),
    );

    _assertUsable();

    final session = _session;
    if (session == null) {
      throw StateError(
        'Session became null after preprocessing. state=$_state',
      );
    }

    final inputTensor = await OrtValue.fromList(
      buffer,
      [1, 3, _Cfg.inputSize, _Cfg.inputSize],
    );

    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run({_Cfg.inputName: inputTensor}).timeout(
        _Cfg.inferTimeout,
        onTimeout: () => throw TimeoutException(
          'Inference timed out (${_Cfg.inferTimeout.inSeconds}s): '
          '$imagePath',
        ),
      );

      return await _extractResult(outputs);
    } finally {
      await _disposeTensor(inputTensor);
      if (outputs != null) await _disposeOutputs(outputs);
    }
  }

  Future<NsfwResult> _extractResult(Map<String, OrtValue> outputs) async {
    final logitsTensor = outputs[_Cfg.outputName];
    if (logitsTensor == null) {
      final available = outputs.keys.join(', ');
      throw StateError(
        'Model output key "${_Cfg.outputName}" not found. '
        'Available: [$available].',
      );
    }

    final flat = await logitsTensor.asFlattenedList();

    if (flat.length < 2) {
      throw StateError(
        'logits tensor has ${flat.length} element(s), expected ≥ 2.',
      );
    }

    final l0 = (flat[0] as num).toDouble();
    final l1 = (flat[1] as num).toDouble();

    if (!l0.isFinite || !l1.isFinite) {
      throw StateError('Non-finite logits: [$l0, $l1].');
    }

    final probs = _softmax([l0, l1]);
    return NsfwResult(nsfw: probs[0], sfw: probs[1]);
  }

  Future<void> _loadModel() async {
    _Log.i('loading model: ${_Cfg.modelAsset}');
    final ort = OnnxRuntime();
    _session = await ort.createSessionFromAsset(_Cfg.modelAsset);
    _Log.i('model loaded');
  }

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

  Future<T> _guardedInference<T>(Future<T> Function() fn) async {
    _inflight++;
    _drainedSignal.reset();

    try {
      return await fn();
    } finally {
      _inflight--;
      if (_inflight == 0) {
        _drainedSignal.complete();
      }
    }
  }

  List<double> _softmax(List<double> logits) {
    final max = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - max)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

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
