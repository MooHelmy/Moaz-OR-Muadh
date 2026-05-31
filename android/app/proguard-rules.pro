# ═══════════════════════════════════════════════════════
# Flutter Core — الحد الأدنى المطلوب
# ═══════════════════════════════════════════════════════
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ═══════════════════════════════════════════════════════
# Play Core (Flutter Deferred Components)
# ═══════════════════════════════════════════════════════
-dontwarn com.google.android.play.core.**

# ═══════════════════════════════════════════════════════
# TensorFlow Lite / ONNX Runtime
# ═══════════════════════════════════════════════════════
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# ═══════════════════════════════════════════════════════
# Firebase — الكلاسات المستخدمة فعلياً فقط
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
# WorkManager
# ═══════════════════════════════════════════════════════
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
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
# ML Kit Face Detection
# ═══════════════════════════════════════════════════════
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }
-dontwarn com.google.mlkit.**

# ═══════════════════════════════════════════════════════
# Kotlin — الحد الأدنى فقط (مش كل شيء)
# ═══════════════════════════════════════════════════════
-dontwarn kotlin.**
-dontwarn kotlinx.**
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.** { *; }

# ═══════════════════════════════════════════════════════
# General Android
# ═══════════════════════════════════════════════════════
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ═══════════════════════════════════════════════════════
# R8 Full Mode — تجاهل تحذيرات الكلاسات الغائبة
# ═══════════════════════════════════════════════════════
-ignorewarnings
