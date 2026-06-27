import 'package:flutter/material.dart';

/// Shown whenever the device has lost connectivity. Background art is
/// the project-specific webp; the Retry button below it rebuilds the
/// caller-provided screen on tap (usually the boot stage).
class OfflineStage extends StatefulWidget {
  const OfflineStage({super.key, required this.rebuilder});

  final WidgetBuilder rebuilder;

  @override
  State<OfflineStage> createState() => _OfflineStageState();
}

class _OfflineStageState extends State<OfflineStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  bool _busy = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.rebuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final bg = landscape
        ? 'assets/Nowifi/Horizontal_Nowifi_Screen.webp'
        : 'assets/Nowifi/Vertical_Nowifi_Screen.webp';

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
          Align(
            alignment: landscape
                ? const Alignment(0, 0.55)
                : const Alignment(0, 0.6),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.03)
                  .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
              child: _RetryPill(busy: _busy, onTap: _retry, compact: landscape),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetryPill extends StatefulWidget {
  const _RetryPill({
    required this.busy,
    required this.onTap,
    required this.compact,
  });

  final bool busy;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_RetryPill> createState() => _RetryPillState();
}

class _RetryPillState extends State<_RetryPill> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pad = widget.compact ? 12.0 : 16.0;
    final wide = MediaQuery.of(context).size.width *
        (widget.compact ? 0.34 : 0.66);

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: wide,
          padding: EdgeInsets.symmetric(vertical: pad),
          decoration: BoxDecoration(
            gradient: widget.busy
                ? null
                : const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFD63F00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: widget.busy
                ? const Color(0xFFD63F00).withValues(alpha: 0.35)
                : null,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: widget.busy
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: widget.busy
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Connecting…',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                )
              : const Center(
                  child: Text(
                    'TRY AGAIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 2)),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
