// Encode CluckSprint sensitive strings into XOR byte-arrays.
//
// Usage:
//   dart run tool/wrap_secrets.dart
//
// Paste the printed arrays into:
//   lib/setup/backend_secrets.dart
//   lib/setup/tracking_secrets.dart
//   lib/runtime/device_agent.dart
//
// NEVER pipe a PowerShell `foreach` loop to do the XOR — on Windows
// the integer literals overflow at 32 bits and yield wrong bytes.
import '../lib/cipher/byte_cipher.dart';

void main() {
  // ----------------------------------------------------------------
  // Backend endpoint (split: host vs path)
  // ----------------------------------------------------------------
  // Full URL is: https://cllucksprint.com/config.php
  const String backendHost = 'https://cllucksprint.com';
  const String backendPath = '/config.php';

  // ----------------------------------------------------------------
  // AppsFlyer Dev Key — paste plain text here when ready
  // ----------------------------------------------------------------
  const String afDevKey = '8SPnxAnBWmB6MYt9whpFFE';

  // ----------------------------------------------------------------
  // Firebase sender / project number (digits only)
  // ----------------------------------------------------------------
  const String firebaseProject = '440691847656';

  // ----------------------------------------------------------------
  // GCD endpoint (host + path)
  // https://gcdsdk.appsflyer.com/install_data/v4.0/{appId}?device_id={uid}
  // ----------------------------------------------------------------
  const String gcdHost = 'https://gcdsdk.appsflyer.com';
  const String gcdPath = '/install_data/v4.0/';

  // ----------------------------------------------------------------
  // Browser version fragments injected into the User-Agent
  // ----------------------------------------------------------------
  const String chromeVer = '132.0.6834.163';
  const String webkitVer = '537.36';

  _emit('backendHost', backendHost);
  _emit('backendPath', backendPath);
  _emit('afDevKey', afDevKey);
  _emit('firebaseProject', firebaseProject);
  _emit('gcdHost', gcdHost);
  _emit('gcdPath', gcdPath);
  _emit('chromeVer', chromeVer);
  _emit('webkitVer', webkitVer);
}

void _emit(String label, String plain) {
  if (plain.isEmpty) {
    print('// $label  → (empty, skipped)');
    return;
  }
  final bytes = wrap(plain);
  final hex = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
  print('// $label  → "$plain"');
  print('const <int>[$hex],');
  print('');
}
