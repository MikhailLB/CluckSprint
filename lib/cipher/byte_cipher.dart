import 'dart:typed_data';

// ============================================================
//  byte_cipher — sensitive-string XOR transformer
// ============================================================
//  All endpoint hosts, third-party keys and version strings live
//  in the binary as XOR-encoded byte lists rather than plain
//  literals. The decoder is deterministic but depends on a
//  per-project seed phrase, so two binaries with different
//  seeds produce different output for the same input.
//
//  Pipeline:
//   1. _spinKey() walks an LCG primed by a 32-bit hash of the
//      seed bytes and emits a 24-byte rolling key.
//   2. unwrap(bytes) XORs each byte with key[i % 24] and returns
//      the decoded UTF-8 string.
//
//  The seed phrase below ("cluckrun") MUST be unique per project.
//  Changing it requires re-encoding every sensitive string with
//  tool/wrap_secrets.dart and pasting the new arrays back into
//  setup/*.dart.
// ============================================================

const List<int> _seedPhrase = <int>[
  0x63, 0x6C, 0x75, 0x63, 0x6B, 0x72, 0x75, 0x6E, // c l u c k r u n
];

Uint8List _spinKey() {
  if (_seedPhrase.isEmpty) return Uint8List(24);

  // FNV-ish accumulator → 32-bit seed
  int acc = 0x811C9DC5;
  for (final b in _seedPhrase) {
    acc ^= b;
    acc = (acc * 16777619) & 0xFFFFFFFF;
  }

  final out = Uint8List(24);
  int state = acc | 1; // never zero
  for (var i = 0; i < out.length; i++) {
    // xorshift32
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= (state >> 17);
    state ^= (state << 5) & 0xFFFFFFFF;
    state &= 0xFFFFFFFF;
    out[i] = state & 0xFF;
  }
  return out;
}

final Uint8List _cipherKey = _spinKey();

/// Decode an XOR-wrapped byte list back to its UTF-8 string form.
String unwrap(List<int> wrapped) {
  if (wrapped.isEmpty) return '';
  final buf = Uint8List(wrapped.length);
  for (var i = 0; i < wrapped.length; i++) {
    buf[i] = wrapped[i] ^ _cipherKey[i % _cipherKey.length];
  }
  return String.fromCharCodes(buf);
}

/// Encode a string into the XOR-wrapped byte list used by `unwrap`.
/// Only used by the local secrets-encoder tool, never at runtime.
List<int> wrap(String plain) {
  final bytes = plain.codeUnits;
  final out = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ _cipherKey[i % _cipherKey.length];
  }
  return out;
}
