/// The runtime decides between two app personalities on first launch
/// and then sticks with it forever:
///
///   - [shell]   → attributed user; show the WebView shell.
///   - [native]  → organic / unattributed user; show the chicken game.
///   - [unknown] → first launch, gate not yet evaluated.
enum RuntimeMode {
  unknown,
  shell,
  native;

  static RuntimeMode parse(String? raw) {
    switch (raw) {
      case 'shell':
        return RuntimeMode.shell;
      case 'native':
        return RuntimeMode.native;
      default:
        return RuntimeMode.unknown;
    }
  }

  String encode() {
    switch (this) {
      case RuntimeMode.shell:
        return 'shell';
      case RuntimeMode.native:
        return 'native';
      case RuntimeMode.unknown:
        return 'unknown';
    }
  }
}
