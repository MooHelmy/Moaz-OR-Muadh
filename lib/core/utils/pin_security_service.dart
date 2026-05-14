import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PinSecurityService
// يتولى كل منطق الـ PIN:
//   • تشفير الـ PIN بـ SHA-256 + salt قبل الحفظ
//   • lockout بعد 5 محاولات فاشلة (3 دقائق)
//   • فرق كامل بين user PIN وmaster PIN
// ─────────────────────────────────────────────────────────────────────────────
class PinSecurityService {
  static const _keyUserPinHash   = 'sec_user_pin_hash';
  static const _keyUserPinSalt   = 'sec_user_pin_salt';
  static const _keyMasterHash    = 'sec_master_hash';
  static const _keyMasterSalt    = 'sec_master_salt';
  static const _keyFailedCount   = 'sec_failed_count';
  static const _keyLockUntil     = 'sec_lock_until';
  static const _lockDurationMs   = 3 * 60 * 1000; // 3 دقائق
  static const _maxAttempts      = 5;

  // ─── Hashing ──────────────────────────────────────────────────────────────
  static String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  static String _randomSalt() {
    final ts  = DateTime.now().microsecondsSinceEpoch;
    final rnd = Object().hashCode;
    return sha256.convert(utf8.encode('$ts-$rnd')).toString().substring(0, 16);
  }

  // ─── User PIN ─────────────────────────────────────────────────────────────
  static Future<void> saveUserPin(SharedPreferences prefs, String pin) async {
    final salt = _randomSalt();
    await prefs.setString(_keyUserPinSalt, salt);
    await prefs.setString(_keyUserPinHash, _hash(pin, salt));
  }

  static bool hasUserPin(SharedPreferences prefs) =>
      prefs.containsKey(_keyUserPinHash);

  static bool verifyUserPin(SharedPreferences prefs, String pin) {
    final salt = prefs.getString(_keyUserPinSalt);
    final hash = prefs.getString(_keyUserPinHash);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  // ─── Master PIN ───────────────────────────────────────────────────────────
  static Future<void> saveMasterPin(SharedPreferences prefs, String pin) async {
    final salt = _randomSalt();
    await prefs.setString(_keyMasterSalt, salt);
    await prefs.setString(_keyMasterHash, _hash(pin, salt));
  }

  static bool hasMasterPin(SharedPreferences prefs) =>
      prefs.containsKey(_keyMasterHash);

  static bool verifyMasterPin(SharedPreferences prefs, String pin) {
    final salt = prefs.getString(_keyMasterSalt);
    final hash = prefs.getString(_keyMasterHash);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  // ─── Lockout ──────────────────────────────────────────────────────────────
  static bool isLocked(SharedPreferences prefs) {
    final lockUntil = prefs.getInt(_keyLockUntil) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < lockUntil;
  }

  static Duration lockRemaining(SharedPreferences prefs) {
    final lockUntil = prefs.getInt(_keyLockUntil) ?? 0;
    final remaining = lockUntil - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  static Future<void> recordFailedAttempt(SharedPreferences prefs) async {
    final count = (prefs.getInt(_keyFailedCount) ?? 0) + 1;
    await prefs.setInt(_keyFailedCount, count);
    if (count >= _maxAttempts) {
      final lockUntil =
          DateTime.now().millisecondsSinceEpoch + _lockDurationMs;
      await prefs.setInt(_keyLockUntil, lockUntil);
      await prefs.setInt(_keyFailedCount, 0);
    }
  }

  static Future<void> resetFailedAttempts(SharedPreferences prefs) async {
    await prefs.remove(_keyFailedCount);
    await prefs.remove(_keyLockUntil);
  }

  static int remainingAttempts(SharedPreferences prefs) {
    final count = prefs.getInt(_keyFailedCount) ?? 0;
    return (_maxAttempts - count).clamp(0, _maxAttempts);
  }

  // ─── Verify any (user OR master) ──────────────────────────────────────────
  static bool verifyAny(SharedPreferences prefs, String pin) {
    if (verifyUserPin(prefs, pin)) return true;
    if (hasMasterPin(prefs) && verifyMasterPin(prefs, pin)) return true;
    return false;
  }
}
