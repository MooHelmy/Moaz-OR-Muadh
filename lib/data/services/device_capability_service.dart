// ══════════════════════════════════════════════════════════════════════════════
//  device_capability_service.dart
//  يحدد مستوى الـ concurrency المناسب للجهاز بناءً على:
//    1. Hardware tier  (RAM + CPU cores + isLowRamDevice)  — native channel
//    2. Thermal state  (من /sys/class/thermal)              — Dart file read
//    3. Battery saver  (من native PowerManager)            — native channel
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/services.dart';

enum DeviceTier { low, mid, high }

class ConcurrencyState {
  final int concurrency;
  final DeviceTier hardwareTier;
  final String? throttleReason;

  const ConcurrencyState({
    required this.concurrency,
    required this.hardwareTier,
    this.throttleReason,
  });

  @override
  String toString() =>
      'ConcurrencyState(workers=$concurrency, tier=${hardwareTier.name}'
      '${throttleReason != null ? ", throttle=$throttleReason" : ""})';
}

class DeviceCapabilityService {
  // ✅ channel واحد بيجيب كل الـ info من Android في call واحدة
  static const MethodChannel _channel = MethodChannel('medi_guard/device_info');

  static const Map<DeviceTier, int> _baseConcurrency = {
    DeviceTier.low:  1,
    DeviceTier.mid:  2,
    DeviceTier.high: 3,
  };

  static const int _lowRamMb   = 2048;
  static const int _highRamMb  = 4096;
  static const int _lowCores   = 4;
  static const int _highCores  = 8;

  DeviceTier? _cachedTier;

  Future<DeviceTier> getHardwareTier() async {
    if (_cachedTier != null) return _cachedTier!;
    try {
      final caps = await _channel
          .invokeMapMethod<String, dynamic>('getDeviceCapabilities')
          .timeout(const Duration(seconds: 3));

      final cores        = (caps?['cpuCores']       as num?)?.toInt() ?? 4;
      final ramMb        = (caps?['totalRamMb']      as num?)?.toInt() ?? 2048;
      final isLowRam     = (caps?['isLowRamDevice']  as bool?) ?? false;

      if (isLowRam || ramMb < _lowRamMb || cores <= _lowCores) {
        _cachedTier = DeviceTier.low;
      } else if (ramMb >= _highRamMb && cores >= _highCores) {
        _cachedTier = DeviceTier.high;
      } else {
        _cachedTier = DeviceTier.mid;
      }
    } catch (_) {
      _cachedTier = DeviceTier.mid;
    }
    return _cachedTier!;
  }

  Future<ConcurrencyState> computeConcurrency() async {
    final tier = await getHardwareTier();
    int workers = _baseConcurrency[tier]!;
    String? throttleReason;

    // ─── Battery Saver ────────────────────────────────────────────────────────
    // ✅ FIX: نستخدم native channel بدل قراءة /sys مباشرة
    // /sys paths مختلفة على كل manufacturer — Samsung ≠ Xiaomi ≠ Pixel
    // PowerManager.isPowerSaveMode() هو الـ API الرسمي المضمون
    if (await _isBatterySaverEnabled()) {
      workers = (workers - 1).clamp(1, workers);
      throttleReason = 'battery_saver';
    }

    // ─── Thermal ─────────────────────────────────────────────────────────────
    // ✅ نقرأ أول thermal zone للـ CPU — أكثر موثوقية من فحص كل الـ zones
    if (await _isThermalThrottled()) {
      workers = 1;
      throttleReason = throttleReason != null
          ? '$throttleReason+thermal'
          : 'thermal';
    }

    return ConcurrencyState(
      concurrency: workers,
      hardwareTier: tier,
      throttleReason: throttleReason,
    );
  }

  // ✅ FIX: battery saver عبر native channel — موثوق على كل الأجهزة
  Future<bool> _isBatterySaverEnabled() async {
    try {
      final caps = await _channel
          .invokeMapMethod<String, dynamic>('getDeviceCapabilities')
          .timeout(const Duration(seconds: 2));
      return (caps?['isPowerSaveMode'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ✅ نفحص cpu thermal zone فقط — أسرع وأدق من فحص كل الـ zones
  Future<bool> _isThermalThrottled() async {
    try {
      // نجرب المسارات الشائعة للـ CPU thermal zone
      final candidates = [
        '/sys/class/thermal/thermal_zone0/temp',
        '/sys/class/thermal/thermal_zone1/temp',
        '/sys/class/thermal/thermal_zone4/temp', // Snapdragon CPU zone
      ];

      for (final path in candidates) {
        final f = File(path);
        if (!await f.exists()) continue;
        final raw = int.tryParse((await f.readAsString()).trim()) ?? 0;
        // Android: millidegrees → degrees, لو أقل من 1000 بالفعل بالـ degrees
        final celsius = raw > 1000 ? raw / 1000.0 : raw.toDouble();
        if (celsius > 47.0) return true;
        // لو وجدنا zone واحد صالح نوقف — مش محتاج نفحص الباقي
        if (celsius > 0) break;
      }
    } catch (_) {}
    return false;
  }
}
