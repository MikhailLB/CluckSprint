import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../types/runtime_mode.dart';

// ============================================================
//  Vault — persistent state used across launches
// ============================================================
//  Non-sensitive flags (mode, timestamps, granted booleans) sit
//  in SharedPreferences. URLs that must survive uninstall-like
//  scenarios (or that we'd rather keep out of `adb backup`) go
//  to FlutterSecureStorage which encrypts them with the
//  Android Keystore.
// ============================================================

class Vault {
  static const _modeKey = 'runtime_mode_v2';
  static const _shellUrlKey = 'shell_url_blob';
  static const _shellExpiresKey = 'shell_url_expires_v2';
  static const _pushPromoSkipKey = 'push_promo_skip_until';
  static const _pushPromoGrantedKey = 'push_promo_granted';
  static const _pushPromoOsBlockedKey = 'push_promo_os_blocked';
  static const _pushPayloadUrlKey = 'push_payload_url_blob';

  late SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // -- mode ----------------------------------------------------------

  RuntimeMode readMode() => RuntimeMode.parse(_prefs.getString(_modeKey));

  Future<void> writeMode(RuntimeMode mode) =>
      _prefs.setString(_modeKey, mode.encode());

  // -- shell URL (secure) -------------------------------------------

  Future<String?> loadShellUrl() => _secure.read(key: _shellUrlKey);

  Future<void> saveShellUrl(String url) =>
      _secure.write(key: _shellUrlKey, value: url);

  Future<void> dropShellUrl() => _secure.delete(key: _shellUrlKey);

  int? readShellExpires() => _prefs.getInt(_shellExpiresKey);

  Future<void> writeShellExpires(int unixSeconds) =>
      _prefs.setInt(_shellExpiresKey, unixSeconds);

  bool isShellExpired() {
    final exp = readShellExpires();
    if (exp == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  // -- push permission state ----------------------------------------

  bool isPushGranted() => _prefs.getBool(_pushPromoGrantedKey) ?? false;
  Future<void> setPushGranted(bool v) =>
      _prefs.setBool(_pushPromoGrantedKey, v);

  /// True only when the OS itself has denied permission and will not show
  /// the prompt again (Android user pressed "Don't allow"). Without this
  /// the promo screen would keep re-appearing every 3 days even though
  /// tapping Accept would do nothing.
  bool isPushOsBlocked() => _prefs.getBool(_pushPromoOsBlockedKey) ?? false;
  Future<void> markPushOsBlocked() =>
      _prefs.setBool(_pushPromoOsBlockedKey, true);

  int? readPushSkipUntil() => _prefs.getInt(_pushPromoSkipKey);
  Future<void> writePushSkipUntil(int unixSeconds) =>
      _prefs.setInt(_pushPromoSkipKey, unixSeconds);

  /// Decide whether the push promo stage should be shown ahead of the
  /// WebView. Respects: prior grant, OS-level block, and the 3-day skip
  /// cool-down.
  bool shouldShowPushPromo() {
    if (isPushGranted()) return false;
    if (isPushOsBlocked()) return false;
    final skip = readPushSkipUntil();
    if (skip == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= skip;
  }

  // -- push payload URL (secure, one-shot) --------------------------

  Future<void> stashPushUrl(String? url) async {
    if (url == null || url.isEmpty) {
      await _secure.delete(key: _pushPayloadUrlKey);
    } else {
      await _secure.write(key: _pushPayloadUrlKey, value: url);
    }
  }

  /// Read + immediately delete the push URL. The push spec says these are
  /// one-shot: the next cold-start should fall back to the regular config
  /// URL, not the saved push URL.
  Future<String?> popPushUrl() async {
    final value = await _secure.read(key: _pushPayloadUrlKey);
    if (value != null) {
      await _secure.delete(key: _pushPayloadUrlKey);
    }
    return value;
  }
}
