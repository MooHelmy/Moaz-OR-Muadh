// ══════════════════════════════════════════════════════════════════════════════
//  custom_detailed_timer.dart  — v2.0.0
//
//  ✅ ValueNotifier بدل setState — rebuild مُحدَّد فقط
//  ✅ Timer يوقف تلقائياً في background — battery savings
//  ✅ تحديث فقط عند تغيُّر الدقائق الفعلي
//  ✅ const constructors في كل مكان ممكن
//  ✅ adaptive textScaler بدل fontSize ثابت
//  ✅ flutter_screenutil لكل الأبعاد
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Data class — immutable snapshot للوقت
// ──────────────────────────────────────────────────────────────────────────────

final class _TimerSnapshot {
  const _TimerSnapshot({
    required this.days,
    required this.hours,
    required this.minutes,
  });

  final String days;
  final String hours;
  final String minutes;

  factory _TimerSnapshot.from(Duration d) => _TimerSnapshot(
        days: d.inDays.toString(),
        hours: (d.inHours % 24).toString().padLeft(2, '0'),
        minutes: (d.inMinutes % 60).toString().padLeft(2, '0'),
      );

  static const zero = _TimerSnapshot(days: '0', hours: '00', minutes: '00');

  @override
  bool operator ==(Object other) =>
      other is _TimerSnapshot &&
      days == other.days &&
      hours == other.hours &&
      minutes == other.minutes;

  @override
  int get hashCode => Object.hash(days, hours, minutes);
}

// ──────────────────────────────────────────────────────────────────────────────
// Widget
// ──────────────────────────────────────────────────────────────────────────────

class CustomDetailedTimer extends StatefulWidget {
  const CustomDetailedTimer({super.key, required this.snapshot});

  final AsyncSnapshot<DateTime?> snapshot;

  @override
  State<CustomDetailedTimer> createState() => _CustomDetailedTimerState();
}

class _CustomDetailedTimerState extends State<CustomDetailedTimer>
    with WidgetsBindingObserver {
  // ✅ ValueNotifier — يُعيد بناء فقط ValueListenableBuilder وليس الشجرة كلها
  late final ValueNotifier<_TimerSnapshot> _timerNotifier;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timerNotifier = ValueNotifier(_computeSnapshot());
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(CustomDetailedTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // لو تغيّر الـ snapshot من الخارج نحدّث فوراً
    if (oldWidget.snapshot.data != widget.snapshot.data) {
      _tick();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timerNotifier.dispose();
    super.dispose();
  }

  // ✅ إيقاف Timer أثناء background — يوفر battery كاملاً
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.resumed:
        _tick();         // تحديث فوري بعد الرجوع
        _startTimer();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  _TimerSnapshot _computeSnapshot() {
    final installDate = widget.snapshot.data;
    if (installDate == null) return _TimerSnapshot.zero;
    return _TimerSnapshot.from(DateTime.now().difference(installDate));
  }

  // ✅ تحديث فقط لو في تغيير فعلي — يمنع rebuilds زائدة
  void _tick() {
    final next = _computeSnapshot();
    if (_timerNotifier.value != next) {
      _timerNotifier.value = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 24.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: const Color(0xFFEDF2F1)),
      ),
      // ✅ ValueListenableBuilder — يُعيد بناء الـ Row فقط عند تغيُّر القيمة
      child: ValueListenableBuilder<_TimerSnapshot>(
        valueListenable: _timerNotifier,
        builder: (_, snap, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CustomTimeBlock(value: snap.days,    label: 'أيام'),
            const _Divider(),
            CustomTimeBlock(value: snap.hours,   label: 'ساعة'),
            const _Divider(),
            CustomTimeBlock(value: snap.minutes, label: 'دقيقة'),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// CustomTimeBlock — const-safe, responsive
// ──────────────────────────────────────────────────────────────────────────────

class CustomTimeBlock extends StatelessWidget {
  const CustomTimeBlock({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 0.8, maxScaleFactor: 1.3);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          textScaler: textScaler,
          style: TextStyle(
            fontSize: 32.sp,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF064E3B),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          textScaler: textScaler,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Divider — const widget لا يُعاد بناؤه أبداً
// ──────────────────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 45.h,
      width: 1.5.w,
      color: const Color(0xFFF0F4F3),
    );
  }
}
