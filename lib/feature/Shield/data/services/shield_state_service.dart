import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ShieldState {
  final bool vpnActive;
  final bool accessibilityActive;
  final bool antiUninstallActive;
  final String? antiUninstallPin;
  final String? accessibilityPin;
  final String? adminPin;

  const ShieldState({
    this.vpnActive = false,
    this.accessibilityActive = false,
    this.antiUninstallActive = false,
    this.antiUninstallPin,
    this.accessibilityPin,
    this.adminPin,
  });

  Map<String, dynamic> toJson() {
    return {
      'vpnActive': vpnActive,
      'accessibilityActive': accessibilityActive,
      'antiUninstallActive': antiUninstallActive,
      'antiUninstallPin': antiUninstallPin,
      'accessibilityPin': accessibilityPin,
      'adminPin': adminPin,
    };
  }

  factory ShieldState.fromJson(Map<String, dynamic> json) {
    return ShieldState(
      vpnActive: json['vpnActive'] == true,
      accessibilityActive: json['accessibilityActive'] == true,
      antiUninstallActive: json['antiUninstallActive'] == true,
      antiUninstallPin: json['antiUninstallPin'] as String?,
      accessibilityPin: json['accessibilityPin'] as String?,
      adminPin: json['adminPin'] as String?,
    );
  }
}

class ShieldStateService {
  static const _fileName = 'shield_state.json';
  static const _directoryName = '.maadh_shield';

  static Future<Directory?> _stateDirectory() async {
    try {
      // ✅ FIX: getApplicationDocumentsDirectory بدل getExternalStorageDirectory
      // External storage: يُفقد لو الـ SD card اتنزعت، ومش محتاج permissions زيادة
      // App documents: خاص بالتطبيق، محمي، وبيستمر طالما التطبيق موجود
      final baseDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${baseDir.path}/$_directoryName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _stateFile() async {
    final dir = await _stateDirectory();
    if (dir == null) return null;
    return File('${dir.path}/$_fileName');
  }

  static Future<ShieldState> loadState() async {
    try {
      final file = await _stateFile();
      if (file == null || !await file.exists()) {
        return const ShieldState();
      }
      final raw = await file.readAsString();
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      return ShieldState.fromJson(jsonMap);
    } catch (_) {
      return const ShieldState();
    }
  }

  static Future<void> saveState(ShieldState state) async {
    try {
      final file = await _stateFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(state.toJson()));
    } catch (_) {
      // ignore storage failures, we still want app to continue.
    }
  }

  static Future<void> updateVpnActive(bool value) async {
    final state = await loadState();
    await saveState(ShieldState(
      vpnActive: value,
      accessibilityActive: state.accessibilityActive,
      antiUninstallActive: state.antiUninstallActive,
      antiUninstallPin: state.antiUninstallPin,
      accessibilityPin: state.accessibilityPin,
      adminPin: state.adminPin,
    ));
  }

  static Future<void> updateAccessibilityActive(bool value) async {
    final state = await loadState();
    await saveState(ShieldState(
      vpnActive: state.vpnActive,
      accessibilityActive: value,
      antiUninstallActive: state.antiUninstallActive,
      antiUninstallPin: state.antiUninstallPin,
      accessibilityPin: state.accessibilityPin,
      adminPin: state.adminPin, // ✅ FIX: كان ناقص → data loss bug
    ));
  }

  static Future<void> updateAntiUninstallActive(bool value) async {
    final state = await loadState();
    await saveState(ShieldState(
      vpnActive: state.vpnActive,
      accessibilityActive: state.accessibilityActive,
      antiUninstallActive: value,
      antiUninstallPin: state.antiUninstallPin,
      accessibilityPin: state.accessibilityPin,
      adminPin: state.adminPin, // ✅ FIX: كان ناقص → data loss bug
    ));
  }

  static Future<void> saveAntiUninstallPin(String pin) async {
    final state = await loadState();
    await saveState(ShieldState(
      vpnActive: state.vpnActive,
      accessibilityActive: state.accessibilityActive,
      antiUninstallActive: state.antiUninstallActive,
      antiUninstallPin: pin,
      accessibilityPin: state.accessibilityPin,
      adminPin: state.adminPin, // ✅ FIX: كان ناقص → يُفقد الـ admin PIN
    ));
  }

  static Future<void> saveAccessibilityPin(String pin) async {
    final state = await loadState();
    await saveState(ShieldState(
      vpnActive: state.vpnActive,
      accessibilityActive: state.accessibilityActive,
      antiUninstallActive: state.antiUninstallActive,
      antiUninstallPin: state.antiUninstallPin,
      accessibilityPin: pin,
      adminPin: state.adminPin, // ✅ FIX: كان ناقص → يُفقد الـ admin PIN
    ));
  }

  static Future<bool> hasPin(String type) async {
    final state = await loadState();
    if (type == 'antiUninstall') {
      return state.antiUninstallPin != null &&
          state.antiUninstallPin!.isNotEmpty;
    }
    if (type == 'accessibility') {
      return state.accessibilityPin != null &&
          state.accessibilityPin!.isNotEmpty;
    }
    if (type == 'admin') {
      return state.adminPin != null && state.adminPin!.isNotEmpty;
    }
    return false;
  }

  static Future<void> saveAdminPin(String pin) async {
    final state = await loadState();
    await saveState(ShieldState(
      vpnActive: state.vpnActive,
      accessibilityActive: state.accessibilityActive,
      antiUninstallActive: state.antiUninstallActive,
      antiUninstallPin: state.antiUninstallPin,
      accessibilityPin: state.accessibilityPin,
      adminPin: pin,
    ));
  }

  static Future<void> removeAdminPin() async {
    final state = await loadState();
    await saveState(ShieldState(
      vpnActive: state.vpnActive,
      accessibilityActive: state.accessibilityActive,
      antiUninstallActive: state.antiUninstallActive,
      antiUninstallPin: state.antiUninstallPin,
      accessibilityPin: state.accessibilityPin,
      adminPin: null,
    ));
  }

  static Future<bool> validatePin(String pin, String type) async {
    final state = await loadState();
    final adminPin = state.adminPin;
    if (adminPin != null && adminPin.isNotEmpty && adminPin == pin) {
      return true;
    }
    if (type == 'antiUninstall') {
      return state.antiUninstallPin == pin;
    }
    if (type == 'accessibility') {
      return state.accessibilityPin == pin;
    }
    return false;
  }
}
