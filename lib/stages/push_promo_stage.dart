import 'package:flutter/material.dart';

import '../runtime/net_sensor.dart';
import '../runtime/push_runtime.dart';
import '../runtime/vault.dart';
import '../setup/app_facade.dart';
import 'webview_stage.dart' deferred as shell;

/// Static promo screen shown once before the WebView (per TZ): asks the
/// user to allow push. Accept = system prompt. Skip = 3-day cool-down.
class PushPromoStage extends StatefulWidget {
  const PushPromoStage({
    super.key,
    required this.vault,
    required this.push,
    required this.netSensor,
    required this.shellUrl,
  });

  final Vault vault;
  final PushRuntime push;
  final NetSensor netSensor;
  final String shellUrl;

  @override
  State<PushPromoStage> createState() => _PushPromoStageState();
}

class _PushPromoStageState extends State<PushPromoStage> {
  bool _busy = false;

  Future<void> _onAccept() async {
    if (_busy) return;
    setState(() => _busy = true);

    final granted = await widget.push.askPermission();
    if (!granted) {
      // Either OS denied or user dismissed the dialog. Either way,
      // schedule the 3-day cool-down (push runtime separately marks
      // the OS-blocked flag if status == denied).
      final until =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 +
              AppFacade.pushPromoCoolDownSec;
      await widget.vault.writePushSkipUntil(until);
    }
    if (!mounted) return;
    await _enterShell();
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);

    final until =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 +
            AppFacade.pushPromoCoolDownSec;
    await widget.vault.writePushSkipUntil(until);

    if (!mounted) return;
    await _enterShell();
  }

  Future<void> _enterShell() async {
    await shell.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => shell.WebViewStage(
          targetUrl: widget.shellUrl,
          vault: widget.vault,
          push: widget.push,
          netSensor: widget.netSensor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final bg = landscape
        ? 'assets/Notifications/Horizontal_Notifications_Screen.webp'
        : 'assets/Notifications/Vertical_Notifications_Screen.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            bg,
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
          ),
          if (!landscape)
            Positioned(
              left: size.width * 0.08,
              right: size.width * 0.08,
              bottom: size.height * 0.08,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AcceptCapsule(busy: _busy, onTap: _onAccept),
                  const SizedBox(height: 14),
                  _SkipLink(busy: _busy, onTap: _onSkip),
                ],
              ),
            )
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: size.height * 0.06,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: size.width * 0.34,
                    child: _AcceptCapsule(
                      busy: _busy,
                      onTap: _onAccept,
                      compact: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: size.width * 0.34,
                    child: _SkipLink(
                      busy: _busy,
                      onTap: _onSkip,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AcceptCapsule extends StatefulWidget {
  const _AcceptCapsule({
    required this.busy,
    required this.onTap,
    this.compact = false,
  });

  final bool busy;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_AcceptCapsule> createState() => _AcceptCapsuleState();
}

class _AcceptCapsuleState extends State<_AcceptCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  bool _down = false;

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        if (!widget.busy) widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _glow,
        builder: (_, child) {
          final t = Curves.easeInOut.transform(_glow.value);
          return AnimatedScale(
            scale: _down ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: Container(
              width: double.infinity,
              padding:
                  EdgeInsets.symmetric(vertical: widget.compact ? 10 : 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6CCFF6), Color(0xFF1E88E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E88E5)
                        .withValues(alpha: 0.35 + t * 0.4),
                    blurRadius: 12 + t * 14,
                    spreadRadius: t * 3,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Accept',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: widget.compact ? 16 : 20,
                    letterSpacing: 1.2,
                    shadows: const [
                      Shadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkipLink extends StatefulWidget {
  const _SkipLink({
    required this.busy,
    required this.onTap,
    this.compact = false,
  });

  final bool busy;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_SkipLink> createState() => _SkipLinkState();
}

class _SkipLinkState extends State<_SkipLink> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        if (!widget.busy) widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: double.infinity,
          padding:
              EdgeInsets.symmetric(vertical: widget.compact ? 10 : 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6CCFF6), Color(0xFF1E88E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x551E88E5),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: widget.compact ? 16 : 20,
                letterSpacing: 1.2,
                shadows: const [
                  Shadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
