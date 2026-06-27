import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'game_assets.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  static const _verticalBg = 'assets/Vertical_LoadingScreen.webp';
  static const _horizontalBg = 'assets/Horizontal_LoadingScreen.webp';

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Real progress climbs toward this soft cap while assets load, so the bar is
  // never fully filled until the very last moment before launch.
  static const double _softCap = 0.9;
  double _progress = 0.0;
  bool _assetsReady = false;
  bool _finishing = false;
  GameAssets? _assets;
  int _dots = 0;
  double _dotTimer = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _startLoading();
  }

  Future<void> _startLoading() async {
    try {
      final loaded = await GameAssets.load();
      if (!mounted) return;
      await Future.wait([
        precacheImage(const AssetImage(_verticalBg), context),
        precacheImage(const AssetImage(_horizontalBg), context),
        precacheImage(const AssetImage('assets/chikenmenu.webp'), context),
        precacheImage(const AssetImage('assets/logo-2.webp'), context),
      ]);
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() {
        _assets = loaded;
        _assetsReady = true;
      });
    } catch (_) {
      // If anything fails, wait a beat and retry once.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      _startLoading();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    // Animate the "Loading..." dots.
    _dotTimer += dt;
    if (_dotTimer >= 0.4) {
      _dotTimer = 0;
      _dots = (_dots + 1) % 4;
    }

    if (!_finishing) {
      if (!_assetsReady) {
        // Climb gradually toward the soft cap while loading.
        _progress = (_progress + dt * 0.45).clamp(0.0, _softCap);
      } else {
        // Assets are ready: rush to 100% right before launch.
        _progress = (_progress + dt * 1.6).clamp(0.0, 1.0);
        if (_progress >= 1.0) {
          _finishing = true;
          _launch();
        }
      }
    }
    setState(() {});
  }

  Future<void> _launch() async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    // The actual game is portrait-only.
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, anim, secondary) =>
            MenuScreen(assets: _assets!),
        transitionsBuilder: (context, anim, secondary, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

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
                isPortrait ? _verticalBg : _horizontalBg,
                fit: BoxFit.cover,
              ),
              // Soft gradient at the bottom so the bar/text stay readable.
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
                  child: _LoadingControls(progress: _progress, dots: _dots),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingControls extends StatelessWidget {
  const _LoadingControls({required this.progress, required this.dots});

  final double progress;
  final int dots;

  @override
  Widget build(BuildContext context) {
    final dotText = '.' * dots;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Horizontal progress bar, fills left -> right.
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
          'Loading$dotText',
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
