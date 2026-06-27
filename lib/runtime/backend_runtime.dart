import 'dart:async';
import 'dart:convert';

import '../setup/app_facade.dart';
import '../types/backend_reply.dart';
import 'device_agent.dart';
import 'vault.dart';

// ============================================================
//  BackendRuntime — single POST to the gating endpoint
// ============================================================
//  Sends the merged attribution + device payload, decodes the
//  reply, and (on success) persists the URL/expiry into the
//  vault so returning users can fall back to it if the network
//  hiccups later.
// ============================================================

class BackendRuntime {
  BackendRuntime(this._vault);

  final Vault _vault;

  Future<BackendReply> hit(Map<String, dynamic> payload) async {
    final endpoint = AppFacade.backendUrl;
    if (endpoint.isEmpty) {
      return BackendReply.fail('endpoint missing');
    }

    Uri uri;
    try {
      uri = Uri.parse(endpoint);
    } catch (e) {
      return BackendReply.fail('endpoint parse: $e');
    }

    try {
      final response = await DeviceAgent.instance
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: AppFacade.backendTimeoutSec));

      if (response.statusCode != 200) {
        return BackendReply.fail('http ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return BackendReply.fail('json shape');
      }

      final reply = BackendReply.fromJson(json);
      if (reply.ok && reply.hasUrl) {
        await _vault.saveShellUrl(reply.url!);
        if (reply.expiresAt != null) {
          await _vault.writeShellExpires(reply.expiresAt!);
        }
      }
      return reply;
    } on TimeoutException {
      return BackendReply.fail('timeout');
    } catch (e) {
      return BackendReply.fail(e.toString());
    }
  }

  /// Returns the previously-saved shell URL even if expired —
  /// stale content beats nothing on a returning visit.
  Future<String?> cachedShellUrl() => _vault.loadShellUrl();
}
