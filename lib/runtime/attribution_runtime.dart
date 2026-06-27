import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../setup/app_facade.dart';
import '../setup/tracking_secrets.dart';
import 'device_agent.dart';

// ============================================================
//  AttributionRuntime — AppsFlyer wrapper + payload builder
// ============================================================
//  Three independent callbacks may carry useful data:
//    * onInstallConversionData — primary attribution.
//    * onAppOpenAttribution    — re-attribution on warm starts.
//    * onDeepLinking (UDL)     — deferred deep link metadata.
//
//  Each is mirrored into a separate map and only merged when we
//  build the backend payload, so the order of arrival doesn't
//  matter and a missing source doesn't lose the others.
//
//  Organic-false-positive guard: when the first callback reports
//  af_status="Organic", we wait the configured cool-down and re-query
//  the GCD API. Whichever response yields the most fields wins.
// ============================================================

class AttributionRuntime {
  AppsflyerSdk? _sdk;
  bool _booted = false;

  Map<String, dynamic>? _conversionMap;
  Map<String, dynamic>? _deepLinkMap;
  Map<String, dynamic>? _reopenMap;

  final Completer<Map<String, dynamic>> _conversionGate = Completer();
  final Completer<void> _deepLinkGate = Completer();

  Future<void> boot() async {
    if (_booted) return;
    _booted = true;

    final devKey = AppFacade.trackingKey;
    if (devKey.isEmpty) {
      // Without a key the SDK can't initialize; resolve gates so the
      // caller doesn't wait the full attribution timeout.
      if (!_conversionGate.isCompleted) _conversionGate.complete(const {});
      if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: AppFacade.iosNumericId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    try {
      _sdk = AppsflyerSdk(options);

      _sdk!.onInstallConversionData((data) async {
        final raw = (data['payload'] ?? data) as Map<dynamic, dynamic>?;
        final payload = raw == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(raw);

        if (_looksOrganic(payload)) {
          await Future.delayed(
            Duration(seconds: AppFacade.organicRetryDelaySec),
          );
          final retry = await _retryViaGcd();
          _conversionMap = (retry != null && retry.isNotEmpty)
              ? retry
              : payload;
        } else {
          _conversionMap = payload;
        }

        if (!_conversionGate.isCompleted) {
          _conversionGate.complete(_conversionMap!);
        }
      });

      _sdk!.onAppOpenAttribution((data) {
        final raw = (data['payload'] ?? data) as Map<dynamic, dynamic>?;
        if (raw != null) {
          _reopenMap = Map<String, dynamic>.from(raw);
        }
      });

      _sdk!.onDeepLinking((result) {
        final click = result.deepLink?.clickEvent;
        if (click != null) {
          _deepLinkMap = Map<String, dynamic>.from(click);
        }
        if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
      });

      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      if (!_conversionGate.isCompleted) {
        _conversionGate.complete(const {});
      }
      if (!_deepLinkGate.isCompleted) _deepLinkGate.complete();
    }
  }

  bool _looksOrganic(Map<String, dynamic> p) {
    final status = (p['af_status'] ?? p['status'])?.toString();
    return status != null && status.toLowerCase() == 'organic';
  }

  Future<Map<String, dynamic>?> _retryViaGcd() async {
    final uid = await uuid();
    if (uid == null) return null;
    final appId = Platform.isIOS ? AppFacade.iosNumericId : AppFacade.packageId;
    final url = resolveGcdEndpoint(appId, uid);
    if (url.isEmpty) return null;

    try {
      final response = await DeviceAgent.instance.get(
        Uri.parse(url),
        headers: {'authorization': 'Bearer ${AppFacade.trackingKey}'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json is Map<String, dynamic>) return json;
        if (json is Map) return Map<String, dynamic>.from(json);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> uuid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Wait at most [timeout] for the conversion callback.
  Future<Map<String, dynamic>> awaitConversion(Duration timeout) {
    return _conversionGate.future
        .timeout(timeout, onTimeout: () => <String, dynamic>{});
  }

  /// Wait at most [timeout] for the deep-link callback.
  Future<void> awaitDeepLink(Duration timeout) {
    return _deepLinkGate.future.timeout(timeout, onTimeout: () {});
  }

  /// Compose the backend payload.
  ///
  /// Order (first writer wins for everything except device fields):
  ///   1. conversion data (full, unfiltered)
  ///   2. deep-link click event (putIfAbsent)
  ///   3. app-open re-attribution (putIfAbsent)
  ///   4. device + identity columns (always overwritten)
  Future<Map<String, dynamic>> buildPayload({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    body.addAll(_conversionMap ?? const {});
    _deepLinkMap?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _reopenMap?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await uuid() ?? '';
    body['bundle_id'] = AppFacade.packageId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = AppFacade.storeListingId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final sender = AppFacade.messagingSender;
    if (sender.isNotEmpty) {
      body['firebase_project_id'] = sender;
    }

    if (kDebugMode) {
      debugPrint('[AttributionRuntime] payload: ${jsonEncode(body)}');
    }
    return body;
  }
}
