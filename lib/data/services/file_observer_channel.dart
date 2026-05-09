import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class FileObserverChannel {
  static const _channel = MethodChannel('medi_guard/file_observer');
  static const _eventChannel = EventChannel('medi_guard/file_events');

  static Stream<String>? _fileStream;

  /// يبدأ مراقبة المجلدات ويربط الـ stream تلقائياً
  /// يُستدعى من الـ main isolate فقط (مش من TaskHandler)
  static Future<void> startWatching(List<String> folders) async {
    await _channel.invokeMethod('startWatching', {'folders': folders});

    // نستمع للأحداث ونبعتها لـ TaskHandler عن طريق sendDataToTask
    fileEvents.listen((filePath) {
      FlutterForegroundTask.sendDataToTask(filePath);
    });
  }

  /// Stream مباشر — للـ UI لو محتاجه
  static Stream<String> get fileEvents {
    _fileStream ??=
        _eventChannel.receiveBroadcastStream().map((event) => event as String);
    return _fileStream!;
  }
}
