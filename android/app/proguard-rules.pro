# ═══════════════════════════════════════════════════════
# Flutter
# ═══════════════════════════════════════════════════════
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ═══════════════════════════════════════════════════════
# ✅ Fix: R8 "Missing class" — Play Core (Flutter Deferred Components)
# هذه المكتبة اختيارية في Flutter، R8 بيشتكي منها لو مش موجودة
# الحل: نقوله تجاهلها بدل ما يوقف البناء
# ═══════════════════════════════════════════════════════
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
-keepclassmembers class com.google.android.play.core.** { *; }

# ═══════════════════════════════════════════════════════
# ✅ Fix: R8 "Missing class" — TensorFlow Lite GPU Delegate
# GpuDelegateFactory$Options مش موجودة في الـ TFLite المستخدم
# ═══════════════════════════════════════════════════════
-dontwarn org.tensorflow.**
-keep class org.tensorflow.** { *; }

# ═══════════════════════════════════════════════════════
# Firebase
# ═══════════════════════════════════════════════════════
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ═══════════════════════════════════════════════════════
# Hive
# ═══════════════════════════════════════════════════════
-keep class com.hivedb.** { *; }
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ═══════════════════════════════════════════════════════
# ONNX Runtime
# ═══════════════════════════════════════════════════════
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# ═══════════════════════════════════════════════════════
# WorkManager
# ═══════════════════════════════════════════════════════
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-dontwarn androidx.work.**

# ═══════════════════════════════════════════════════════
# Flutter Foreground Task
# ═══════════════════════════════════════════════════════
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**

# ═══════════════════════════════════════════════════════
# ML Kit
# ═══════════════════════════════════════════════════════
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }
-dontwarn com.google.mlkit.**

# ═══════════════════════════════════════════════════════
# Kotlin
# ═══════════════════════════════════════════════════════
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**

# ═══════════════════════════════════════════════════════
# General Android
# ═══════════════════════════════════════════════════════
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
