import 'dart:io';

/// Many home and café Wi‑Fi routers advertise IPv6 but do not route it.
/// Dart tries that address first and the app looks offline, while mobile data
/// (usually IPv4) works. Prefer an IPv4 address, and fall back to the normal
/// lookup when the network is IPv6-only.
void installIpv4FirstHttp() {
  HttpOverrides.global = _Ipv4FirstOverrides();
}

class _Ipv4FirstOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 20);
    client.connectionFactory = _connectIpv4First;
    return client;
  }
}

Future<ConnectionTask<Socket>> _connectIpv4First(
  Uri uri,
  String? proxyHost,
  int? proxyPort,
) async {
  if (proxyHost != null && proxyHost.isNotEmpty) {
    return Socket.startConnect(proxyHost, proxyPort ?? 80);
  }

  final secure = uri.scheme == 'https';
  final port = uri.hasPort ? uri.port : (secure ? 443 : 80);
  Object target = uri.host;
  try {
    final v4 = await InternetAddress.lookup(
      uri.host,
      type: InternetAddressType.IPv4,
    ).timeout(const Duration(seconds: 3));
    if (v4.isNotEmpty) target = v4.first;
  } catch (_) {}

  if (secure) {
    return SecureSocket.startConnect(target, port);
  }
  return Socket.startConnect(target, port);
}
