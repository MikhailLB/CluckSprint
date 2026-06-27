import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../setup/app_facade.dart';

// ============================================================
//  NetSensor — connectivity probe + reactive stream
// ============================================================
//  The connectivity_plus stream is a hint, not a verdict. It can
//  fire `none` for a few hundred milliseconds while a VPN tunnel
//  is being raised — without a debounce that would route the user
//  to the offline stage on every VPN toggle.
//
//  Real "no internet" cases throw `SocketException` from DNS
//  almost instantly, so the lookup timeout is generous (7s by
//  default). That window only matters for VPN-throttled DNS,
//  where the longer timeout is the whole point.
// ============================================================

const Set<ConnectivityResult> _liveInterfaces = {
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  ConnectivityResult.vpn,
  ConnectivityResult.bluetooth,
  ConnectivityResult.other,
};

const List<String> _dnsTargets = <String>[
  'one.one.one.one',
  'dns.google',
  'cloudflare.com',
];

class NetSensor {
  final Connectivity _backend = Connectivity();

  /// True if at least one live interface is reported AND DNS
  /// resolves one of the well-known anchor hosts within the
  /// configured probe timeout.
  Future<bool> isLive() async {
    final results = await _backend.checkConnectivity();
    if (!results.any(_liveInterfaces.contains)) return false;

    for (final host in _dnsTargets) {
      try {
        final answer = await InternetAddress.lookup(host)
            .timeout(Duration(seconds: AppFacade.dnsProbeTimeoutSec));
        if (answer.isNotEmpty && answer.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        // try next host
      } catch (_) {
        // try next host
      }
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get statusStream =>
      _backend.onConnectivityChanged;
}
