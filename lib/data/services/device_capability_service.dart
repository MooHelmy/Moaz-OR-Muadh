// ══════════════════════════════════════════════════════════════════════════════
//  device_capability_service.dart
//  يحدد مستوى الـ concurrency المناسب للجهاز بناءً على:
//    1. Hardware tier  (RAM + CPU cores + isLowRamDevice)
//    2. Thermal state  (لو الجهاز سخن → نخفض)
//    3. Battery saver  (لو موفر الطاقة شغال → نخفض)
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/services.dart';

// ─── Concurrency Tier ─────────────────────────────────────────────────────────
enum DeviceTier {
  /// أجهزة ضعيفة — RAM < 2GB أو isLowRamDevice أو CPU ≤ 4
  low,

  /// أجهزة متوسطة — RAM 2-4GB و CPU 5-7
  mid,

  /// أجهزة قوية — RAM > 4GB و CPU ≥ 8
  high,
}

// ─── Concurrency State ────────────────────────────────────────────────────────
// الحالة النهائية بعد تطبيق كل العوامل
class ConcurrencyState {
  /// عدد الـ workers الحالي
  final int concurrency;

  /// الـ tier بناءً على الـ hardware فقط
  final DeviceTier hardwareTier;

  /// سبب التخفيض إن وُجد
  final String? throttleReason;

  const ConcurrencyState({
    required this.concurrency,
    required this.hardwareTier,
    this.throttleReason,
  });

  @override
  String toString() =>
      'ConcurrencyState(workers=$concurrency, tier=$hardwareTier'
      '${throttleReason != null ? ", throttle=$throttleReason" : ""})';
}

// ─── Device Capability Service ────────────────────────────────────────────────
class DeviceCapabilityService {
  static const MethodChannel _channel = MethodChannel('medi_guard/device_info');

  // Concurrency limits per tier (baseline — قبل thermal/battery adjustments)
  static const Map<DeviceTier, int> _baseConcurrency = {
    DeviceTier.low:  1,
    DeviceTier.mid:  2,
    DeviceTier.high: 3,
  };

  // Hardware tier thresholds
  static const int _lowRamThresholdMb  = 2048; // < 2GB → low
  static const int _highRamThresholdMb = 4096; // > 4GB → high
  static const int _lowCpuCores        = 4;    // ≤ 4 → low
  static const int _highCpuCores       = 8;    // ≥ 8 → high

  DeviceTier? _cachedTier;

  /// يجيب hardware tier من native (مرة واحدة — نتيجة cached)
  Future<DeviceTier> getHardwareTier() async {
    if (_cachedTier != null) return _cachedTier!;

    try {
      final caps = await _channel
          .invokeMapMethod<String, dynamic>('getDeviceCapabilities')
          .timeout(const Duration(seconds: 3));

      if (caps == null) {
        _cachedTier = DeviceTier.mid;
        return _cachedTier!;
      }

      final cpuCores       = (caps['cpuCores']       as num?)?.toInt() ?? 4;
      final totalRamMb     = (caps['totalRamMb']     as num?)?.toInt() ?? 2048;
      final isLowRamDevice = (caps['isLowRamDevice'] as bool?) ?? false;

      // isLowRamDevice من Android نفسه = أقوى مؤشر → low فوراً
      if (isLowRamDevice || totalRamMb < _lowRamThresholdMb || cpuCores <= _lowCpuCores) {
        _cachedTier = DeviceTier.low;
      } else if (totalRamMb >= _highRamThresholdMb && cpuCores >= _highCpuCores) {
        _cachedTier = DeviceTier.high;
      } else {
        _cachedTier = DeviceTier.mid;
      }
    } catch (_) {
      // fallback آمن
      _cachedTier = DeviceTier.mid;
    }

    return _cachedTier!;
  }

  /// يحسب الـ concurrency النهائي بعد تطبيق thermal + battery adjustments
  Future<ConcurrencyState> computeConcurrency() async {
    final tier = await getHardwareTier();
    int workers = _baseConcurrency[tier]!;
    String? throttleReason;

    // ─── Battery Saver ────────────────────────────────────────────────────────
    // Android: لو Power Saving mode شغال → نخفض بمقدار 1 (minimum 1)
    if (await _isBatterySaverEnabled()) {
      workers = (workers - 1).clamp(1, workers);
      throttleReason = 'battery_saver';
    }

    // ─── Thermal Throttle ─────────────────────────────────────────────────────
    // Android API 29+: لو thermal status > LIGHT → نخفض لـ 1
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

  /// هل Battery Saver (Power Save Mode) شغال؟
  Future<bool> _isBatterySaverEnabled() async {
    try {
      // نقرأ من /sys/class/power_supply — متاح على معظم أجهزة Android
      // بديل لـ PowerManager.isPowerSaveMode() اللي محتاجة context
      final f = File('/sys/class/power_supply/battery/power_save_soc_thresh');
      if (await f.exists()) {
        // وجود الملف وقيمته > 0 = power save mode شغال
        final val = int.tryParse((await f.readAsString()).trim()) ?? 0;
        if (val > 0) return true;
      }
      // fallback: نقرأ من /sys/class/power_supply/battery/status
      final statusFile = File('/sys/class/power_supply/battery/status');
      if (await statusFile.exists()) {
        // لو الجهاز بيشحن ما نخفضش
        final status = (await statusFile.readAsString()).trim().toLowerCase();
        if (status == 'charging' || status == 'full') return false;
      }
    } catch (_) {}
    return false;
  }

  /// هل الجهاز في حالة thermal throttling؟
  /// يقرأ من /sys/class/thermal — متاح على Android بدون permissions
  Future<bool> _isThermalThrottled() async {
    try {
      // Android thermal zones — نبحث عن أي zone فوق 45°C
      final thermalDir = Directory('/sys/class/thermal');
      if (!await thermalDir.exists()) return false;

      final zones = await thermalDir
          .list()
          .where((e) => e.path.contains('thermal_zone'))
          .cast<Directory>()
          .take(8) // نفحص أول 8 zones فقط
          .toList();

      for (final zone in zones) {
        try {
          final tempFile = File('${zone.path}/temp');
          if (!await tempFile.exists()) continue;

          final raw = int.tryParse((await tempFile.readAsString()).trim()) ?? 0;
          // Android يعبّر عن درجة الحرارة بـ millidegrees
          // raw > 45000 = أكثر من 45°C
          final celsius = raw > 1000 ? raw / 1000.0 : raw.toDouble();
          if (celsius > 45.0) return true;
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    return false;
  }
}
