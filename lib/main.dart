import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The loading screen supports both orientations, so we allow all of them on
  // startup. They are restricted to portrait once the menu/game begins.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const CluckSprintApp());
}

class CluckSprintApp extends StatelessWidget {
  const CluckSprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cluck Sprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'sans-serif',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFC107)),
      ),
      home: const LoadingScreen(),
    );
  }
}
