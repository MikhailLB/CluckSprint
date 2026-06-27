/// Wire-format reply from the backend config endpoint.
///
/// Successful gate (shell mode):
///   { "ok": true, "url": "https://...", "expires": 1700000000 }
///
/// Negative gate (organic / unmatched):
///   { "ok": false, "message": "organic" }
///
/// Network or HTTP error:
///   constructed via [BackendReply.fail].
class BackendReply {
  const BackendReply({
    required this.ok,
    this.url,
    this.expiresAt,
    this.message,
  });

  final bool ok;
  final String? url;
  final int? expiresAt;
  final String? message;

  factory BackendReply.fromJson(Map<String, dynamic> json) {
    return BackendReply(
      ok: (json['ok'] as bool?) ?? false,
      url: json['url'] as String?,
      expiresAt: json['expires'] as int?,
      message: json['message'] as String?,
    );
  }

  factory BackendReply.fail(String reason) =>
      BackendReply(ok: false, message: reason);

  bool get hasUrl => url != null && url!.isNotEmpty;
}
