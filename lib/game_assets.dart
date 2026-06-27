import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Decoded [ui.Image] sprites used by the game's [CustomPainter].
class GameAssets {
  GameAssets({
    required this.chicken,
    required this.carRed,
    required this.carYellow,
    required this.carBlue,
    required this.road,
    required this.grass,
    required this.grassTexture,
  });

  final ui.Image chicken;
  final ui.Image carRed;
  final ui.Image carYellow;
  final ui.Image carBlue;
  final ui.Image road;
  final ui.Image grass;
  final ui.Image grassTexture;

  static Future<ui.Image> _load(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<GameAssets> load() async {
    final results = await Future.wait<ui.Image>([
      _load('assets/chikengame.webp'),
      _load('assets/carred.webp'),
      _load('assets/yellowcar.webp'),
      _load('assets/bluecar.webp'),
      _load('assets/road.webp'),
      _load('assets/grass.webp'),
      _load('assets/grawee.webp'),
    ]);
    return GameAssets(
      chicken: results[0],
      carRed: results[1],
      carYellow: results[2],
      carBlue: results[3],
      road: results[4],
      grass: results[5],
      grassTexture: results[6],
    );
  }
}
