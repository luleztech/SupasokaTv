import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/admin_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _blocked => _loading || _cooldownSeconds > 0;

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSeconds = seconds;
      _error =
          'Server is temporarily rate-limited (shared edge IP). '
          'Wait $_cooldownSeconds s — do not keep retrying, that makes it worse.';
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        t.cancel();
        setState(() {
          _cooldownSeconds = 0;
          _error = 'You can try logging in again now.';
        });
        return;
      }
      setState(() {
        _cooldownSeconds -= 1;
        _error =
            'Server is temporarily rate-limited (shared edge IP). '
            'Wait $_cooldownSeconds s — do not keep retrying, that makes it worse.';
      });
    });
  }

  Future<void> _login() async {
    if (_blocked) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final store = context.read<AdminStore>();
    final error = await store.login(_passwordController.text);
    if (!mounted) return;
    if (error != null) {
      if (error.startsWith(AdminStore.rateLimitedLoginPrefix)) {
        final wait = int.tryParse(
              error.substring(AdminStore.rateLimitedLoginPrefix.length),
            ) ??
            60;
        setState(() => _loading = false);
        _startCooldown(wait);
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
      return;
    }
    // Success: AppLaunchGate watches Auth state and navigates away.
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF0a0c10),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 80,
                  color: cs.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'SupaAdmin Login',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your admin password to access the dashboard.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_blocked,
                  decoration: InputDecoration(
                    labelText: 'Admin Password',
                    hintText: 'Enter password',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      onPressed: _blocked
                          ? null
                          : () => setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: _cooldownSeconds > 0 ? const Color(0xFFfbbf24) : cs.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _blocked ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _cooldownSeconds > 0
                                ? 'Wait ${_cooldownSeconds}s'
                                : 'Login',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
