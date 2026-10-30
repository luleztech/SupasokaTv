import 'dart:async';
import 'dart:io';

/// TCP to well-known public addresses. This does not depend on DNS, so a Wi‑Fi
/// network that blocks Google still counts as online when the route exists.
Future<bool> probePublicRoute(Duration timeout) {
  final checks = <Future<bool>>[
    _tcp('1.1.1.1', 443, timeout),
    _tcp('8.8.8.8', 53, timeout),
  ];
  final done = Completer<bool>();
  var left = checks.length;
  for (final check in checks) {
    check.then((ok) {
      if (ok && !done.isCompleted) done.complete(true);
    }, onError: (_) {}).whenComplete(() {
      left -= 1;
      if (left == 0 && !done.isCompleted) done.complete(false);
    });
  }
  return done.future;
}

Future<bool> _tcp(String host, int port, Duration timeout) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
