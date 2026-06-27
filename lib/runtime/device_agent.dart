import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../cipher/byte_cipher.dart';

// ============================================================
//  DeviceAgent — real-browser User-Agent + HTTP plumbing
// ============================================================
//  Every outbound request and the WebView itself must look like
//  a stock mobile browser. A Dart/Flutter UA stands out in any
//  attribution log and would put this binary on the wrong side
//  of the routing model.
// ============================================================

class DeviceAgent extends http.BaseClient {
  DeviceAgent._();
  static final DeviceAgent instance = DeviceAgent._();

  final http.Client _delegate = http.Client();
  String? _uaCache;

  /// Encoded `Chrome/<version>` fragment (e.g. 132.0.6834.163).
  String get _chromeFragment => unwrap(const <int>[
        0x89, 0xeb, 0x29, 0x43, 0xb5, 0x51, 0x82, 0xd2,
        0x04, 0xe5, 0xca, 0xbe, 0xf9, 0xef,
      ]);

  /// Encoded WebKit revision (e.g. 537.36).
  String get _webkitFragment => unwrap(const <int>[
        0x8d, 0xeb, 0x2c, 0x43, 0xb6, 0x49,
      ]);

  /// Build (or rebuild) the user-agent string from live device info.
  Future<void> prime() async {
    final chrome = _chromeFragment.isNotEmpty ? _chromeFragment : '132.0.6834.163';
    final webkit = _webkitFragment.isNotEmpty ? _webkitFragment : '537.36';

    String base;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final brand = a.brand;
        final model = a.model;
        final sdk = a.version.sdkInt;
        final tag = a.display.isNotEmpty ? a.display : a.id;
        base = 'Mozilla/5.0 (Linux; Android $sdk; $brand $model '
            'Build/$tag) AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        final ver = i.systemVersion.replaceAll('.', '_');
        base = 'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$webkit';
      } else {
        base = _fallbackBase(chrome, webkit);
      }
    } catch (_) {
      base = _fallbackBase(chrome, webkit);
    }

    _uaCache = base;
  }

  String _fallbackBase(String chrome, String webkit) {
    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 15; SM-S931U Build/AP3A.240905.015.A2) '
          'AppleWebKit/$webkit (KHTML, like Gecko) '
          'Chrome/$chrome Mobile Safari/$webkit';
    }
    return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/$webkit (KHTML, like Gecko) '
        'Version/17.0 Mobile/15E148 Safari/$webkit';
  }

  String get userAgent => _uaCache ?? 'Mozilla/5.0';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}
