import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _securityChannel = MethodChannel('com.ayubu.supasoka/security_guard');

class CaptureGuardScreen extends StatefulWidget {
  const CaptureGuardScreen({
    super.key,
    required this.initialApps,
    required this.onAllowed,
  });

  final List<Map<String, String>> initialApps;
  final Future<void> Function() onAllowed;

  @override
  State<CaptureGuardScreen> createState() => _CaptureGuardScreenState();
}

class _CaptureGuardScreenState extends State<CaptureGuardScreen>
    with WidgetsBindingObserver {
  late List<Map<String, String>> _apps = widget.initialApps;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAgain();
  }

  Future<void> _checkAgain() async {
    if (_checking) return;
    _checking = true;
    try {
      final result = await _securityChannel.invokeMethod<List<dynamic>>(
        'findCaptureApps',
      );
      final apps = (result ?? const <dynamic>[])
          .whereType<Map>()
          .map((app) => <String, String>{
                'packageName': app['packageName']?.toString() ?? '',
                'label': app['label']?.toString() ?? 'Unknown app',
              })
          .where((app) => app['packageName']!.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      if (apps.isEmpty) {
        await widget.onAllowed();
      } else {
        setState(() => _apps = apps);
      }
    } on MissingPluginException {
      // This guard is Android-specific; a missing bridge should not trap users
      // on other platforms.
      if (mounted) await widget.onAllowed();
    } on PlatformException {
      if (mounted) setState(() {});
    } finally {
      _checking = false;
    }
  }

  Future<void> _openSettings() async {
    if (_apps.isEmpty) return;
    try {
      await _securityChannel.invokeMethod<void>(
        'openCaptureAppSettings',
        {'packageName': _apps.first['packageName']},
      );
    } on PlatformException {
      // Keep the blocker visible if Android cannot open the app settings.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.security, size: 56),
                    const SizedBox(height: 20),
                    const Text(
                      'App ya kunasa mtandao imegunduliwa',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Zima au ondoa app hizi ili kulinda URLs na taarifa za Supasoka, kisha urudi hapa:',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ..._apps.map((app) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text('• ${app['label']}'),
                        )),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Fungua mipangilio ya app'),
                    ),
                    TextButton(
                      onPressed: _checking ? null : _checkAgain,
                      child: Text(_checking ? 'Inakagua…' : 'Nimeizima/kuiondoa, kagua tena'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
