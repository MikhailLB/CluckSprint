import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'runtime/attribution_runtime.dart';
import 'runtime/backend_runtime.dart';
import 'runtime/device_agent.dart';
import 'runtime/net_sensor.dart';
import 'runtime/push_runtime.dart';
import 'runtime/vault.dart';
import 'stages/boot_stage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check come first so the backend hit can be challenged
  // by Play Integrity in release builds. Failures here are non-fatal:
  // the gate still works without App Check on devices that don't support it.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  // Both portrait and landscape are needed for the boot/offline/promo
  // backgrounds. The WebView itself re-asserts the same set when it
  // takes over; the native game restricts to portrait inside its own
  // loading screen.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await DeviceAgent.instance.prime();

  final vault = Vault();
  await vault.warmUp();

  final netSensor = NetSensor();
  final attribution = AttributionRuntime();
  final backend = BackendRuntime(vault);
  final push = PushRuntime(vault);

  runApp(CluckSprintShell(
    vault: vault,
    netSensor: netSensor,
    attribution: attribution,
    backend: backend,
    push: push,
  ));
}

class CluckSprintShell extends StatelessWidget {
  const CluckSprintShell({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CluckSprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'sans-serif',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFC107)),
      ),
      home: BootStage(
        vault: vault,
        netSensor: netSensor,
        attribution: attribution,
        backend: backend,
        push: push,
      ),
    );
  }
}
