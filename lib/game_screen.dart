import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'game_assets.dart';

enum RowType { grass, road }

class Car {
  Car({
    required this.leftX,
    required this.type,
    required this.width,
    required this.height,
  });

  double leftX; // left edge in lane space [0, span)
  final int type; // 0 = red, 1 = taxi, 2 = truck
  final double width;
  final double height;
}

class RowData {
  RowData.grass()
    : type = RowType.grass,
      direction = 0,
      speed = 0,
      span = 0,
      cars = const [];

  RowData.road({
    required this.direction,
    required this.speed,
    required this.span,
    required this.cars,
  }) : type = RowType.road;

  final RowType type;
  final int direction; // -1 left, 1 right
  final double speed; // px / second
  final double span; // lane wrap length
  final List<Car> cars;
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.assets});

  final GameAssets assets;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  static const int columns = 5;
  static const int safeStartRows = 2;
  static const double baseYFactor = 0.66;
  static const double multiplierStep = 0.10;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  final Random _rng = Random();

  // Layout-derived; set on first build.
  double _tile = 0;
  double _worldWidth = 0;
  double _height = 0;
  bool _ready = false;

  // World rows generated lazily and sequentially. Rows come in blocks: a road
  // block of 2-5 lanes, then exactly 1 grass line, repeating.
  final Map<int, RowData> _rows = {};
  int _maxGenerated = -1;
  int _blockRemaining = 0;
  bool _blockIsRoad = false;

  // Chicken state.
  int _chickenCol = columns ~/ 2;
  int _chickenRow = 0;
  double _animCol = (columns ~/ 2).toDouble();
  double _animRow = 0;
  double _camRow = 0;

  // Scoring.
  int _maxRowReached = 0;
  int _score = 0;
  int _roadsCrossed = 0;
  double _multiplier = 1.0;
  bool _gameOver = false;

  // Briefly ignore input so the tap that opened this screen (PLAY) doesn't
  // immediately hop the chicken forward.
  int _inputUnlockMs = 0;
  final Stopwatch _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _inputUnlockMs = 400;
    _ticker = createTicker(_onTick)..start();
  }

  void _initWorld() {
    _rows.clear();
    _maxGenerated = -1;
    _blockRemaining = 0;
    _blockIsRoad = false;
    _chickenCol = columns ~/ 2;
    _chickenRow = 0;
    _animCol = _chickenCol.toDouble();
    _animRow = 0;
    _camRow = 0;
    _maxRowReached = 0;
    _score = 0;
    _roadsCrossed = 0;
    _multiplier = 1.0;
    _gameOver = false;
    // Re-arm the input guard so the PLAY AGAIN tap doesn't move the chicken.
    _inputUnlockMs = _clock.elapsedMilliseconds + 400;
    _ensureRow(40);
  }

  double _carAspect(int type) => _kCarOpaque[type][2] / _kCarOpaque[type][3];

  void _ensureRow(int index) {
    while (_maxGenerated < index) {
      _maxGenerated++;
      _rows[_maxGenerated] = _buildRow(_maxGenerated);
    }
  }

  RowData _buildRow(int i) {
    if (i < safeStartRows) return RowData.grass();

    // Start a new block when the current one runs out: roads come in groups of
    // 2-5 lanes, separated by a small random grass strip (1-2 lines).
    if (_blockRemaining <= 0) {
      _blockIsRoad = !_blockIsRoad;
      _blockRemaining = _blockIsRoad ? (2 + _rng.nextInt(4)) : (1 + _rng.nextInt(2));
    }
    _blockRemaining--;

    if (!_blockIsRoad) return RowData.grass();
    return _buildRoadRow(i);
  }

  RowData _buildRoadRow(int i) {
    // Difficulty creeps up with depth; each lane also gets its own random feel.
    final double diff = (i * 0.03).clamp(0.0, 3.5);
    final double base = 1.4 + diff;
    final double speedTiles = base * (0.75 + _rng.nextDouble() * 0.7);
    final double speed = speedTiles * _tile;
    final int direction = _rng.nextBool() ? 1 : -1;
    final double span = _worldWidth + 4 * _tile;
    // Cars roughly as tall as the lane.
    final double carHeight = _tile * 0.88 * 0.70; // −30 %

    // Light, irregular traffic: large random gaps between cars so there is
    // always room to slip through and the level stays beatable.
    final double minGap = _tile * 2.4;
    final double gapJitter = _tile * (2.5 + _rng.nextDouble() * 2.5);

    final cars = <Car>[];
    double x = _rng.nextDouble() * (minGap + gapJitter);
    while (x < span) {
      final type = _rng.nextInt(3);
      final width = carHeight * _carAspect(type);
      if (x + width > span) break;
      cars.add(Car(leftX: x, type: type, width: width, height: carHeight));
      x += width + minGap + _rng.nextDouble() * gapJitter;
    }

    return RowData.road(
      direction: direction,
      speed: speed,
      span: span,
      cars: cars,
    );
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_ready || dt <= 0) {
      setState(() {});
      return;
    }
    final double clampedDt = dt > 0.05 ? 0.05 : dt;

    // Smoothly slide the chicken and camera toward their grid targets.
    final double followChicken = (clampedDt * 16).clamp(0.0, 1.0);
    final double followCam = (clampedDt * 9).clamp(0.0, 1.0);
    _animCol += (_chickenCol - _animCol) * followChicken;
    _animRow += (_chickenRow - _animRow) * followChicken;
    _camRow += (_chickenRow - _camRow) * followCam;

    // Update traffic for the visible rows.
    final int renderTop = (_camRow + _height * baseYFactor / _tile + 3).ceil();
    final int renderBottom = (_camRow - _height * (1 - baseYFactor) / _tile - 3)
        .floor();
    for (int r = renderBottom; r <= renderTop; r++) {
      if (r < 0) continue;
      _ensureRow(r);
      final row = _rows[r]!;
      if (row.type != RowType.road) continue;
      final double delta = row.direction * row.speed * clampedDt;
      for (final car in row.cars) {
        car.leftX += delta;
        if (car.leftX >= row.span) car.leftX -= row.span;
        if (car.leftX < 0) car.leftX += row.span;
      }
    }

    if (!_gameOver) _checkCollision();
    setState(() {});
  }

  void _checkCollision() {
    final row = _rows[_chickenRow];
    if (row == null || row.type != RowType.road) return;

    final double m = _tile * 0.2;
    final double chickenLeft = _chickenCol * _tile + m;
    final double chickenRight = (_chickenCol + 1) * _tile - m;

    for (final car in row.cars) {
      final double screenLeft = car.leftX - 2 * _tile;
      final double cm = car.width * 0.12;
      final double carLeft = screenLeft + cm;
      final double carRight = screenLeft + car.width - cm;
      if (carRight > chickenLeft && carLeft < chickenRight) {
        _onDeath();
        return;
      }
    }
  }

  void _onDeath() {
    // Collision burns every multiplier - the run is over.
    setState(() {
      _gameOver = true;
    });
  }

  void _advanceTo(int newRow) {
    if (newRow <= _maxRowReached) return;
    _maxRowReached = newRow;
    _ensureRow(newRow + 30);
    final row = _rows[newRow]!;
    _score += (5 * _multiplier).round();
    if (row.type == RowType.road) {
      _roadsCrossed++;
      _multiplier = 1.0 + _roadsCrossed * multiplierStep;
    }
  }

  void _move(int dCol, int dRow) {
    if (_gameOver || !_ready) return;
    if (_clock.elapsedMilliseconds < _inputUnlockMs) return;
    final int newCol = (_chickenCol + dCol).clamp(0, columns - 1);
    final int newRow = max(0, _chickenRow + dRow);
    setState(() {
      _chickenCol = newCol;
      _chickenRow = newRow;
    });
    if (dRow > 0) _advanceTo(newRow);
    _checkCollision();
  }

  void _handleSwipe(Offset velocity) {
    if (velocity.dx.abs() > velocity.dy.abs()) {
      _move(velocity.dx > 0 ? 1 : -1, 0);
    } else {
      _move(0, velocity.dy < 0 ? 1 : -1);
    }
  }

  void _restart() {
    setState(_initWorld);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _grassColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double tile = constraints.maxWidth / columns;
          if (!_ready || _tile != tile || _height != constraints.maxHeight) {
            _tile = tile;
            _worldWidth = constraints.maxWidth;
            _height = constraints.maxHeight;
            if (!_ready) {
              _ready = true;
              _initWorld();
            } else {
              // Layout changed mid-game (rare): rebuild lanes for new metrics.
              _initWorld();
            }
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (_) => _move(0, 1),
            onPanEnd: (details) =>
                _handleSwipe(details.velocity.pixelsPerSecond),
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GamePainter(
                        assets: widget.assets,
                        rows: _rows,
                        camRow: _camRow,
                        animCol: _animCol,
                        animRow: _animRow,
                        tile: _tile,
                        columns: columns,
                        baseYFactor: baseYFactor,
                      ),
                    ),
                  ),
                  _buildHud(),
                  if (_gameOver) _buildGameOver(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HudChip(
              label: 'SCORE',
              value: '$_score',
              color: const Color(0xCC2C3E50),
            ),
            const Spacer(),
            _HudChip(
              label: 'MULTIPLIER',
              value: 'x${_multiplier.toStringAsFixed(2)}',
              color: const Color(0xCCE67E22),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOver() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xAA000000),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE67E22), width: 4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'GAME OVER',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFE74C3C),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Score: $_score',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your multiplier burned out!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF7F8C8D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                _MenuActionButton(
                  label: 'PLAY AGAIN',
                  color: const Color(0xFF3FA34D),
                  onTap: _restart,
                ),
                const SizedBox(height: 12),
                _MenuActionButton(
                  label: 'MENU',
                  color: const Color(0xFF34495E),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuActionButton extends StatelessWidget {
  const _MenuActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: 54,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: Colors.white, width: 3),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

const Color _grassColor = Color(0xFF90C634);
const Color _roadColor = Color(0xFF55585F);

// Opaque bounding box of each car sprite as fractions of the image
// [left, top, width, height]. The sprites have large transparent margins, so
// we draw only this region to make the vehicles fill their intended size.
const List<List<double>> _kCarOpaque = [
  [0.293, 0.309, 0.453, 0.242], // 0 red sedan
  [0.215, 0.289, 0.496, 0.277], // 1 yellow taxi
  [0.250, 0.395, 0.496, 0.207], // 2 blue truck
];

// Whether the sprite art already faces RIGHT by default.
// truck (2): cab on LEFT → faces LEFT → false
// red/yellow: hood/front on RIGHT → faces RIGHT → true
const List<bool> _kCarFacesRight = [true, true, false];

// Opaque region of the in-game chicken sprite [left, top, width, height].
const List<double> _kChickenOpaque = [0.293, 0.164, 0.414, 0.492];

class _GamePainter extends CustomPainter {
  _GamePainter({
    required this.assets,
    required this.rows,
    required this.camRow,
    required this.animCol,
    required this.animRow,
    required this.tile,
    required this.columns,
    required this.baseYFactor,
  });

  final GameAssets assets;
  final Map<int, RowData> rows;
  final double camRow;
  final double animCol;
  final double animRow;
  final double tile;
  final int columns;
  final double baseYFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;

    final double baseY = size.height * baseYFactor;
    double rowCenterY(double r) => baseY - (r - camRow) * tile;

    final int renderTop = (camRow + baseY / tile + 2).ceil();
    final int renderBottom = (camRow - (size.height - baseY) / tile - 2)
        .floor();

    // 1) Row backgrounds. Grass is a clean solid fill (no visible cell squares).
    // Road uses only the opaque centre of the asphalt sprite, stretched across
    // the whole lane so the asphalt and dashed line never break up.
    final Paint fill = Paint();
    final ui.Image road = assets.road;
    final Rect roadSrc = Rect.fromLTWH(
      road.width * 0.25,
      road.height * 0.25,
      road.width * 0.5,
      road.height * 0.5,
    );
    for (int r = renderBottom; r <= renderTop; r++) {
      final RowData? row = r < 0 ? null : rows[r];
      final bool isRoad = row != null && row.type == RowType.road;
      final double cy = rowCenterY(r.toDouble());
      final double top = cy - tile / 2;
      fill.color = isRoad ? _roadColor : _grassColor;
      canvas.drawRect(Rect.fromLTWH(0, top - 0.5, size.width, tile + 1), fill);
      if (isRoad) {
        canvas.drawImageRect(
          road,
          roadSrc,
          Rect.fromLTWH(0, top, size.width, tile),
          paint,
        );
      } else {
        // Tile the grass texture horizontally so it fills the strip without
        // stretching. The texture is square so one tile = tile × tile pixels.
        final ui.Image gt = assets.grassTexture;
        final Rect gtSrc = Rect.fromLTWH(
          0,
          0,
          gt.width.toDouble(),
          gt.height.toDouble(),
        );
        double gx = 0;
        while (gx < size.width) {
          final double drawW = (size.width - gx).clamp(0, tile);
          // Partial tile at the right edge: crop src proportionally.
          final Rect partSrc = drawW < tile
              ? Rect.fromLTWH(0, 0, gt.width * (drawW / tile), gt.height.toDouble())
              : gtSrc;
          canvas.drawImageRect(
            gt,
            partSrc,
            Rect.fromLTWH(gx, top, drawW, tile),
            paint,
          );
          gx += tile;
        }
      }
    }

    // 2) Cars on road rows.
    for (int r = renderBottom; r <= renderTop; r++) {
      if (r < 0) continue;
      final RowData? row = rows[r];
      if (row == null || row.type != RowType.road) continue;
      final double cy = rowCenterY(r.toDouble());
      for (final car in row.cars) {
        final double screenLeft = car.leftX - 2 * tile;
        if (screenLeft > size.width + tile || screenLeft + car.width < -tile) {
          continue;
        }
        _drawCar(canvas, paint, car, screenLeft, cy, row.direction);
      }
    }

    // 3) Chicken (drawn from its opaque region so the hero reads large).
    final ui.Image chicken = assets.chicken;
    final double chH = tile * 1.02 * 0.75; // −25 %
    final double chW = chH * (_kChickenOpaque[2] / _kChickenOpaque[3]);
    final double centerX = (animCol + 0.5) * tile;
    final double centerY = baseY - (animRow - camRow) * tile;
    canvas.drawImageRect(
      chicken,
      Rect.fromLTWH(
        chicken.width * _kChickenOpaque[0],
        chicken.height * _kChickenOpaque[1],
        chicken.width * _kChickenOpaque[2],
        chicken.height * _kChickenOpaque[3],
      ),
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: chW,
        height: chH,
      ),
      paint,
    );
  }

  void _drawCar(
    Canvas canvas,
    Paint paint,
    Car car,
    double screenLeft,
    double centerY,
    int direction,
  ) {
    final ui.Image img = switch (car.type) {
      0 => assets.carRed,
      1 => assets.carYellow,
      _ => assets.carBlue,
    };
    final List<double> o = _kCarOpaque[car.type];
    final Rect src = Rect.fromLTWH(
      img.width * o[0],
      img.height * o[1],
      img.width * o[2],
      img.height * o[3],
    );
    final double centerX = screenLeft + car.width / 2;
    canvas.save();
    canvas.translate(centerX, centerY);
    // Flip so the car always faces the direction of travel.
    // shouldFlip is true when the art's native facing differs from travel direction.
    final bool artFacesRight = _kCarFacesRight[car.type];
    final bool shouldFlip = (direction > 0) != artFacesRight;
    if (shouldFlip) canvas.scale(-1, 1);
    canvas.drawImageRect(
      img,
      src,
      Rect.fromCenter(
        center: Offset.zero,
        width: car.width,
        height: car.height,
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => true;
}
