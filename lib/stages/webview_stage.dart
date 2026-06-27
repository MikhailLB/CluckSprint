import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../runtime/device_agent.dart';
import '../runtime/net_sensor.dart';
import '../runtime/push_runtime.dart';
import '../runtime/vault.dart';
import '../setup/app_facade.dart';
import 'offline_stage.dart';

// Called from boot_stage via deferred import.
Future<void> primeShellEngine() async {
  // Reserve hook for any future warm-up; no-op for now.
}

class WebViewStage extends StatefulWidget {
  const WebViewStage({
    super.key,
    required this.targetUrl,
    required this.vault,
    required this.push,
    required this.netSensor,
  });

  final String targetUrl;
  final Vault vault;
  final PushRuntime push;
  final NetSensor netSensor;

  @override
  State<WebViewStage> createState() => _WebViewStageState();
}

class _WebViewStageState extends State<WebViewStage>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _loading = true;
  bool _offlineShown = false;
  String? _lastMainFrameUrl;
  int _redirectAttempts = 0;

  StreamSubscription<List<ConnectivityResult>>? _netSub;
  Timer? _offlineDebounce;

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersive();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(DeviceAgent.instance.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _redirectAttempts = 0;
            _injectSafeAreaKill();
            _injectKeyboardLift();
          },
          onWebResourceError: _handleResourceError,
          onHttpError: (_) {},
          onNavigationRequest: _onNavRequest,
        ),
      );

    _wireAndroidExtras();
    _controller.loadRequest(Uri.parse(widget.targetUrl));

    // Live push routing
    widget.push.onPayloadUrl = (url) {
      if (mounted) _controller.loadRequest(Uri.parse(url));
    };

    _netSub = widget.netSensor.statusStream.listen(_onNetChange);
  }

  void _onNetChange(List<ConnectivityResult> statuses) {
    final allNone = statuses.every((s) => s == ConnectivityResult.none);
    if (!allNone) {
      _offlineDebounce?.cancel();
      _offlineDebounce = null;
      return;
    }
    _offlineDebounce?.cancel();
    _offlineDebounce = Timer(
      Duration(milliseconds: AppFacade.connectivityDebounceMs),
      _routeToOfflineDirect,
    );
  }

  void _handleResourceError(WebResourceError error) {
    if (error.isForMainFrame != true) return;
    final desc = error.description.toLowerCase();

    // Redirect-loop retry: keep an in-flight loop up to 3 tries
    // from the last known main-frame URL.
    final isTooManyRedirects = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        error.errorCode == -1007 ||
        error.errorCode == -9;
    if (isTooManyRedirects &&
        _lastMainFrameUrl != null &&
        _redirectAttempts < 3) {
      _redirectAttempts++;
      _controller.loadRequest(Uri.parse(_lastMainFrameUrl!));
      return;
    }

    // Cover the WebView immediately so the native black/robot page
    // is never visible.
    if (mounted) setState(() => _loading = true);

    final dnsLike = desc.contains('name_not_resolved') ||
        desc.contains('err_name_not_resolved') ||
        desc.contains('internet_disconnected') ||
        desc.contains('network_changed') ||
        error.errorCode == -105 ||
        error.errorCode == -106 ||
        error.errorCode == -21;

    if (dnsLike) {
      _routeToOfflineDirect();
    } else {
      _routeToOfflineIfDown();
    }
  }

  Future<NavigationDecision> _onNavRequest(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    final scheme = uri.scheme;
    if (scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'about' ||
        scheme == 'data' ||
        scheme == 'blob') {
      if (request.isMainFrame) _lastMainFrameUrl = request.url;
      return NavigationDecision.navigate;
    }
    _launchOutside(uri);
    return NavigationDecision.prevent;
  }

  Future<void> _routeToOfflineIfDown() async {
    if (_offlineShown) return;
    final live = await widget.netSensor.isLive();
    if (live || !mounted) return;
    _routeToOfflineDirect();
  }

  void _routeToOfflineDirect() {
    if (_offlineShown || !mounted) return;
    _offlineShown = true;

    _controller.currentUrl().then((current) {
      if (!mounted) return;
      final fallback = current ?? widget.targetUrl;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OfflineStage(
            rebuilder: (_) => WebViewStage(
              targetUrl: fallback,
              vault: widget.vault,
              push: widget.push,
              netSensor: widget.netSensor,
            ),
          ),
        ),
      );
    });
  }

  void _wireAndroidExtras() {
    if (!Platform.isAndroid) return;
    if (_controller.platform is! AndroidWebViewController) return;

    final ctrl = _controller.platform as AndroidWebViewController;
    ctrl.setMediaPlaybackRequiresUserGesture(false);
    ctrl.setOnShowFileSelector(_pickFiles);

    final cookieMgr = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookieMgr.setAcceptThirdPartyCookies(ctrl, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      // file_picker pinned to 8.x — use platform instance call.
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result == null) return const [];
      return result.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _launchOutside(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _injectKeyboardLift() {
    _controller.runJavaScript('''
(function() {
  if (window.__csKbLift) return;
  window.__csKbLift = true;

  function isField(el) {
    if (!el) return false;
    return el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable;
  }

  function nudge() {
    var el = document.activeElement;
    if (!isField(el)) return;
    var vv = window.visualViewport;
    if (vv) {
      var r = el.getBoundingClientRect();
      var bottom = vv.offsetTop + vv.height;
      if (r.bottom > bottom - 18 || r.top < vv.offsetTop + 4) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(ev) {
    if (isField(ev.target)) setTimeout(nudge, 350);
  });

  if (window.visualViewport) {
    var lastH = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < lastH) setTimeout(nudge, 110);
      lastH = h;
    });
  }
})();
''');
  }

  void _injectSafeAreaKill() {
    _controller.runJavaScript(r'''
(function() {
  if (window.__csKillsa) return;
  window.__csKillsa = true;

  var TAG = '__csSafePatch';
  var CSS =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}' +
    'html,body,#__nuxt,#__layout,#app,#root{' +
      'padding-top:0!important;padding-left:0!important;' +
      'padding-right:0!important;margin-top:0!important;' +
    '}';

  function kbOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }

  function apply() {
    if (kbOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta && !/viewport-fit\s*=\s*contain/i.test(meta.getAttribute('content') || '')) {
      var c = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      meta.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var s = document.getElementById(TAG);
    if (!s) {
      s = document.createElement('style');
      s.id = TAG;
      head.appendChild(s);
    }
    if (s.textContent !== CSS) s.textContent = CSS;
    if (head.lastElementChild !== s) head.appendChild(s);
  }

  apply();

  ['pushState', 'replaceState'].forEach(function(fn) {
    var orig = history[fn];
    history[fn] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 420);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineDebounce?.cancel();
    _netSub?.cancel();
    widget.push.onPayloadUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<bool> _onBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final pad = MediaQuery.of(context).viewPadding;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // CRITICAL: must be false; manifest already declares adjustResize.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: landscape
                  ? EdgeInsets.only(left: pad.left, right: pad.right)
                  : EdgeInsets.only(top: pad.top),
              child: WebViewWidget(controller: _controller),
            ),
            if (_loading)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF6CCFF6),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
