import 'backend_secrets.dart';
import 'tracking_secrets.dart';
import 'web_endpoints.dart';

// ============================================================
//  AppFacade — the one constant table the rest of the app reads
// ============================================================
//  Every screen, runtime and helper that needs the bundle id,
//  app name, push delay or any backend URL talks to this class
//  exclusively. Nothing else may hardcode these values, so we
//  can swap any source (config → env → remote flag) without
//  touching the consumers.
// ============================================================

class AppFacade {
  // -- App identity -----------------------------------------------------
  static const String packageId = 'com.cluckrun.cluckrungame';
  static const String storeListingId = 'com.cluckrun.cluckrungame';
  static const String displayName = 'CluckSprint';
  // iOS-only App Store numeric id (unused on Android).
  static const String iosNumericId = '';

  // -- Resolved (encoded) endpoints ------------------------------------
  static String get backendUrl => resolveBackendEndpoint();
  static String get trackingKey => resolveTrackingKey();
  static String get messagingSender => resolveMessagingSender();

  // -- Public-facing URLs ----------------------------------------------
  static String get privacyUrl => cluckSprintPrivacyUrl;
  static String get supportUrl => cluckSprintSupportUrl;
  static String get siteUrl => cluckSprintSiteUrl;

  // -- Timings ---------------------------------------------------------
  /// Cool-down between "Skip" taps on the push promo (per TZ: 3 days).
  static const int pushPromoCoolDownSec = 3 * 24 * 60 * 60;

  /// Wait before re-querying GCD when first callback reports Organic.
  static const int organicRetryDelaySec = 5;

  /// First-launch attribution wait window (paid users → backend).
  static const int firstLaunchAttribTimeoutSec = 30;

  /// Returning-user attribution wait window (already-known users).
  static const int returningAttribTimeoutSec = 10;

  /// Backend POST timeout.
  static const int backendTimeoutSec = 15;

  /// DNS probe for the offline check — bumped from 3s to 7s so VPN
  /// users don't trip the false-negative path.
  static const int dnsProbeTimeoutSec = 7;

  /// Connectivity-stream debounce before we route to the offline stage.
  static const int connectivityDebounceMs = 700;
}
