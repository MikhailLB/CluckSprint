import '../cipher/byte_cipher.dart';

// ============================================================
//  Tracking secrets — AppsFlyer + Firebase
// ============================================================
//  Both the AppsFlyer Dev Key and the Firebase sender id are
//  stored as XOR-wrapped byte arrays. The plaintext values come
//  from the operator and are not in this file under any branch.
//
//  Encode each value with `dart run tool/wrap_secrets.dart`
//  after filling the corresponding plaintext at the top of the
//  tool source. Paste the printed arrays below.
// ============================================================

/// AppsFlyer Dev Key. Plaintext: provided separately by ops.
String resolveTrackingKey() {
  // Fill after running `dart run tool/wrap_secrets.dart`.
  const wrapped = <int>[];
  if (wrapped.isEmpty) return '';
  return unwrap(wrapped);
}

/// Firebase project/sender number (digits only).
String resolveMessagingSender() {
  // Fill after running `dart run tool/wrap_secrets.dart`.
  const wrapped = <int>[];
  if (wrapped.isEmpty) return '';
  return unwrap(wrapped);
}

/// Builds the AppsFlyer GCD attribution-retry URL.
/// Format:
///   {host}{path}{appId}?device_id={uid}
/// Auth header: `Bearer {trackingKey}`
String resolveGcdEndpoint(String appId, String uid) {
  const host = <int>[
    0xd0, 0xac, 0x6f, 0x1d, 0xf6, 0x45, 0x9b, 0xc5,
    0x50, 0xb2, 0x80, 0xfc, 0xab, 0xb7, 0x43, 0x51,
    0xa2, 0xf5, 0x20, 0x38, 0xef, 0x4f, 0x27, 0x0c,
    0x96, 0xbb, 0x74, 0x00,
  ];

  const path = <int>[
    0x97, 0xb1, 0x75, 0x1e, 0xf1, 0x1e, 0xd8, 0x86,
    0x68, 0xb5, 0x85, 0xfb, 0xae, 0xf3, 0x1b, 0x04,
    0xfc, 0xb5, 0x7c,
  ];

  if (host.isEmpty || path.isEmpty) return '';
  return '${unwrap(host)}${unwrap(path)}$appId?device_id=$uid';
}
