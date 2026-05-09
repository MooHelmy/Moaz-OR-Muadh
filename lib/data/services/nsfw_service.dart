import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// نتيجة موديل Marqo NSFW
/// label_names: ["NSFW", "SFW"]  ← من config.json
class NsfwResult {
  final double nsfw; // index 0
  final double sfw; // index 1

  const NsfwResult({required this.nsfw, required this.sfw});

  // Getters للتوافق مع EnsembleScorer و DecisionEngine
  double get porn => nsfw;
  double get hentai => 0.0;
  double get sexy => 0.0;
  double get neutral => sfw;
  double get drawings => 0.0;

  bool get isNsfw => nsfw > sfw;

  @override
  String toString() =>
      'NsfwResult(nsfw: ${nsfw.toStringAsFixed(3)}, sfw: ${sfw.toStringAsFixed(3)})';
}

class NsfwService {
  OrtSession? _session;
  bool _isLoaded = false;

  static const int _inputSize = 384;
  static const double _mean = 0.5;
  static const double _std = 0.5;

  // ─── initialize ─────────────────────────────────────────
  Future<void> initialize() async {
    if (_isLoaded) return;
    try {
      final ort = OnnxRuntime();
      _session = await ort.createSessionFromAsset('assets/models/model.onnx');
      _isLoaded = true;
      debugPrint('✅ NsfwService: model loaded'
          ' | inputs: ${_session!.inputNames}'
          ' | outputs: ${_session!.outputNames}');
    } catch (e) {
      debugPrint('❌ NsfwService: Failed to load model → $e');
      rethrow;
    }
  }

  // ─── predict ────────────────────────────────────────────
  Future<NsfwResult> predict(String imagePath) async {
    if (!_isLoaded) await initialize();

    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image: $imagePath');

    final resized = img.copyResize(
      image,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.cubic,
    );

    // ✅ OrtValue.fromList — مش OrtTensor
    final inputTensor = await _buildInputTensor(resized);
    Map<String, OrtValue>? outputs;

    try {
      outputs = await _session!.run({'pixel_values': inputTensor});

      // ✅ asFlattenedList() — مش .shape ومش .data
      final flat = await outputs['logits']!.asFlattenedList();

      // ✅ .toDouble() عشان flat بيرجع List<dynamic> مش List<double>
      final logits = [
        (flat[0] as num).toDouble(),
        (flat[1] as num).toDouble(),
      ];

      final probs = _softmax(logits);

      debugPrint('🔞 NsfwService → '
          'NSFW=${probs[0].toStringAsFixed(3)}  '
          'SFW=${probs[1].toStringAsFixed(3)}');

      return NsfwResult(nsfw: probs[0], sfw: probs[1]);
    } finally {
      // ✅ dispose دايمًا عشان منحصلش memory leak
      await inputTensor.dispose();
      if (outputs != null) {
        for (final t in outputs.values) {
          await t.dispose();
        }
      }
    }
  }

  // ─── buildInputTensor ───────────────────────────────────
  // Format NCHW: [1, 3, 384, 384]
  // Normalize: (pixel/255 - 0.5) / 0.5  →  [-1, 1]
  Future<OrtValue> _buildInputTensor(img.Image image) async {
    final buffer = Float32List(3 * _inputSize * _inputSize);

    final rOffset = 0;
    final gOffset = _inputSize * _inputSize;
    final bOffset = 2 * _inputSize * _inputSize;

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        final idx = y * _inputSize + x;
        buffer[rOffset + idx] = (pixel.r / 255.0 - _mean) / _std;
        buffer[gOffset + idx] = (pixel.g / 255.0 - _mean) / _std;
        buffer[bOffset + idx] = (pixel.b / 255.0 - _mean) / _std;
      }
    }

    // ✅ OrtValue.fromList(data, shape) — async
    return await OrtValue.fromList(
      buffer,
      [1, 3, _inputSize, _inputSize],
    );
  }

  // ─── softmax ────────────────────────────────────────────
  List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((x) => math.exp(x - maxVal)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  // ─── dispose ────────────────────────────────────────────
  Future<void> dispose() async {
    await _session?.close();
    _isLoaded = false;
  }
}
