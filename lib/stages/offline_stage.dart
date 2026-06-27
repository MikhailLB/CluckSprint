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
          Positioned(
            left: 0,
            right: 0,
            bottom: landscape ? size.height * 0.22 : size.height * 0.18,
            child: Center(
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1.02).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: _RetryPill(
                  busy: _busy,
                  onTap: _retry,
                  compact: landscape,
                ),
              ),
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
    final pad = widget.compact ? 8.0 : 10.0;
    final wide = MediaQuery.of(context).size.width *
        (widget.compact ? 0.26 : 0.50);

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
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: widget.busy
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
          ),
          child: widget.busy
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Connecting…',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Text(
                    'TRY AGAIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: widget.compact ? 13 : 14,
                      letterSpacing: 1.4,
                      shadows: const [
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
