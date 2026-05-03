import 'dart:io';

/// Android emulator maps `localhost` to the emulator itself — use `10.0.2.2` for host machine.
String rewriteLocalApiHost(String url) {
  if (url.isEmpty) return url;
  if (!Platform.isAndroid) return url;
  var u = url;
  if (u.contains('localhost')) {
    u = u.replaceAll('localhost', '10.0.2.2');
  }
  if (u.contains('127.0.0.1')) {
    u = u.replaceAll('127.0.0.1', '10.0.2.2');
  }
  return u;
}
