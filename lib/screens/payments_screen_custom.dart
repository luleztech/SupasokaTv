import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supasoka/config/api.dart';
import 'package:supasoka/config/payment_helpers.dart'
    show
        isPaymentCompleted,
        isPaymentTerminalFailure,
        normalizedPaymentStatus;
import 'package:supasoka/services/user_id.dart';

const _accentCta = Color(0xFF22C55E);
const _accentCtaDark = Color(0xFF16A34A);
const _accentBlue = Color(0xFF2563EB);
const _scaffoldColor = Color(0xFF02040A);

const _tzPrefixes = [
  '061',
  '062',
  '063',
  '065',
  '067',
  '068',
  '069',
  '071',
  '074',
  '075',
  '076',
  '077',
  '078',
  '079',
];

const _paySurface = Color(0xFF0C1222);
const _paySurface2 = Color(0xFF151B2E);
const _payLine = Color(0x14FFFFFF);
const _payMuted = Color(0xFF8B9CAF);

const int _kPaymentWaitSeconds = 60;

enum _PaymentUiPhase { none, instruction, waiting, timedOut, failed }

enum _PayDialogTone { success, error, info }

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    this.accentColor = _accentBlue,
    this.bottomPadding = 0,
    this.onPaymentSuccess,
  });

  final Color accentColor;
  final double bottomPadding;
  final Future<void> Function()? onPaymentSuccess;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String? _selectedBundle;
  final _phoneCtrl = TextEditingController();
  String? _whatsapp;
  String? _userId;
  bool _submitting = false;
  bool _statusOpen = false;
  String _statusTitle = '';
  String _statusMsg = '';
  _PayDialogTone _statusTone = _PayDialogTone.info;
  String? _pendingBundleLabel;
  String? _pollingOrderId;
  Timer? _pollTimer;
  int _notFoundStreak = 0;
  bool _simulating = false;
  int _waitingSeconds = _kPaymentWaitSeconds;
  Timer? _waitingTimer;
  _PaymentUiPhase _paymentUiPhase = _PaymentUiPhase.none;
  String? _sessionEndDetail;

  final _bundles = const [
    _Bundle(
      id: 'week',
      name: 'Kwa Wiki',
      price: '2,000',
      duration: '7 siku',
      value: 2000,
      popular: false,
      priceLine: 'Tsh.2,000/= wiki moja',
    ),
    _Bundle(
      id: 'month',
      name: 'Mwezi',
      price: '5,000',
      duration: '30 siku',
      value: 5000,
      popular: true,
      priceLine: 'Tsh.5,000/= mwezi mmoja',
    ),
    _Bundle(
      id: 'year',
      name: 'Miezi 3',
      price: '12,000',
      duration: 'miezi 3',
      value: 12000,
      popular: false,
      priceLine: 'Tsh.12,000/= miezi mitatu',
    ),
  ];

  bool _phoneValid(String raw) {
    final clean = raw.replaceAll(RegExp(r'\s+'), '');
    if (clean.length != 10) return false;
    if (!RegExp(r'^0\d{9}$').hasMatch(clean)) return false;
    return _tzPrefixes.any((p) => clean.startsWith(p));
  }

  String get _cleanPhone => _phoneCtrl.text.replaceAll(RegExp(r'\s+'), '');
  bool get _phoneOk => _phoneValid(_phoneCtrl.text);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await settingsApi.getWhatsAppNumber();
      final n = w['number']?.toString();
      if (n != null && n.isNotEmpty) {
        setState(() => _whatsapp = n.replaceAll(RegExp(r'\s+'), ''));
      }
    } catch (_) {}

    final uid = await getOrCreateUserId();
    if (uid != null && uid.isNotEmpty) {
      setState(() => _userId = uid);
    }

    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pendingPaymentOrderId')?.trim();
    if (pending == null || pending.isEmpty) return;

    try {
      final res = await paymentsApi.checkZenoStatus(pending);
      final st = res['status'] ?? res['raw']?['data']?[0]?['payment_status'];
      if (isPaymentCompleted(st)) {
        await _markPaymentCompleted(
          title: 'Hongera — malipo yamehakikiwa',
          message:
              'Malipo yaliyokuwa yanasubiri yamekamilika. Akaunti yako inasasishwa kwa Premium.',
        );
      } else if (isPaymentTerminalFailure(st)) {
        await prefs.remove('pendingPaymentOrderId');
        if (mounted) {
          setState(() {
            _paymentUiPhase = _PaymentUiPhase.failed;
            _sessionEndDetail = _paymentFailureUserMessage(st);
          });
        }
      } else {
        setState(() {
          _pollingOrderId = pending;
          _paymentUiPhase = _PaymentUiPhase.waiting;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paymentUiPhase = _PaymentUiPhase.failed;
          _sessionEndDetail = _mapPaymentError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _waitingTimer?.cancel();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _waitingTimer?.cancel();
    setState(() {
      _waitingSeconds = _kPaymentWaitSeconds;
      _paymentUiPhase = _PaymentUiPhase.waiting;
    });

    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_waitingSeconds <= 1) {
        timer.cancel();
        setState(() => _waitingSeconds = 0);
        _handleWaitWindowExpired();
        return;
      }
      setState(() => _waitingSeconds -= 1);
    });

    final orderId = _pollingOrderId;
    if (orderId == null || orderId.isEmpty) return;

    var polls = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      polls++;
      if (!mounted) return;
      try {
        final response = await paymentsApi.checkZenoStatus(orderId);
        final paymentStatus =
            response['status'] ?? response['raw']?['data']?[0]?['payment_status'];
        if (isPaymentCompleted(paymentStatus)) {
          await _markPaymentCompleted(
            title: 'Hongera — malipo yamehakikiwa',
            message:
                'Malipo yako yamekamilika kwa uhakika. Akaunti yako inasasishwa; channel zote zitafunguliwa.',
          );
          return;
        }
        if (isPaymentTerminalFailure(paymentStatus)) {
          await _finalizeSessionFailed(_paymentFailureUserMessage(paymentStatus));
          return;
        }
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('no order') || msg.contains('not found')) {
          _notFoundStreak++;
          if (_notFoundStreak >= 20) {
            _pollTimer?.cancel();
            _pollTimer = null;
            _waitingTimer?.cancel();
            _waitingTimer = null;
            await _clearPendingOrderPrefs();
            if (mounted) {
              setState(() {
                _pollingOrderId = null;
                _notFoundStreak = 0;
                _paymentUiPhase = _PaymentUiPhase.timedOut;
                _sessionEndDetail =
                    'Hatukuweza kuthibitisha ombi la malipo. Hakikisha una mtandao mzuri kisha anza upya kutoka hatua ya 1.';
              });
            }
          }
        }
      }
      if (polls >= 100) {
        _pollTimer?.cancel();
        _pollTimer = null;
        _waitingTimer?.cancel();
        _waitingTimer = null;
        unawaited(_finalizeSessionTimedOut(
          detail:
              'Hatukuweza kupata uthibitisho baada ya muda mrefu. Anza upya na nambari yako.',
        ));
      }
    });
  }

  Future<void> _clearPendingOrderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingPaymentOrderId');
  }

  void _handleWaitWindowExpired() {
    if (!mounted || _pollingOrderId == null) return;
    unawaited(_finalizeSessionTimedOut(
      detail:
          'Muda wa dakika 1 umeisha bila uthibitisho. Hakikisha umeingiza namba ya siri au PIN kwenye simu. Unaweza kujaribu tena.',
    ));
  }

  Future<void> _finalizeSessionTimedOut({String? detail}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _waitingTimer?.cancel();
    _waitingTimer = null;
    await _clearPendingOrderPrefs();
    if (!mounted) return;
    setState(() {
      _pollingOrderId = null;
      _notFoundStreak = 0;
      _paymentUiPhase = _PaymentUiPhase.timedOut;
      _sessionEndDetail = detail;
    });
  }

  Future<void> _finalizeSessionFailed(String message) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _waitingTimer?.cancel();
    _waitingTimer = null;
    await _clearPendingOrderPrefs();
    if (!mounted) return;
    setState(() {
      _pollingOrderId = null;
      _notFoundStreak = 0;
      _paymentUiPhase = _PaymentUiPhase.failed;
      _sessionEndDetail = message;
    });
  }

  void _resetPaymentFlowFromStepOne() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _waitingTimer?.cancel();
    _waitingTimer = null;
    setState(() {
      _paymentUiPhase = _PaymentUiPhase.none;
      _pollingOrderId = null;
      _notFoundStreak = 0;
      _waitingSeconds = _kPaymentWaitSeconds;
      _sessionEndDetail = null;
      _selectedBundle = null;
      _pendingBundleLabel = null;
      _phoneCtrl.clear();
    });
  }

  void _showStatus(String title, String msg, _PayDialogTone tone) {
    setState(() {
      _statusOpen = true;
      _statusTitle = title;
      _statusMsg = msg;
      _statusTone = tone;
    });
  }

  String _mapPaymentError(Object e) {
    final raw = e.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('failed host') ||
        lower.contains('timed out')) {
      return 'Hakuna muunganisho thabiti. Washa data ya simu au Wi-Fi, kisha ujaribu tena.';
    }
    if (lower.contains('401') || lower.contains('403')) {
      return 'Ombi halikuidhinishwa. Fungua tena programu kisha ujaribu.';
    }
    if (lower.contains('404')) {
      return 'Huduma ya malipo haipatikani kwa sasa. Jaribu tena baadaye.';
    }
    if (lower.contains('500') || lower.contains('502') || lower.contains('503')) {
      return 'Seva ya malipo ina tatizo. Jaribu tena baada ya dakika chache.';
    }
    if (raw.length > 200) {
      return 'Malipo hayajaweza kukamilika. Jaribu tena au wasiliana na msaada.';
    }
    return raw;
  }

  String _paymentFailureUserMessage(Object? status) {
    final s = normalizedPaymentStatus(status);
    if (s == 'CANCELLED' || s == 'CANCELED' || s == 'CANCEL') {
      return 'Malipo yameghairiwa au haujakamilisha hatua kwenye simu. Unaweza kujaribu tena ukiwa tayari — gusa “Anza upya”.';
    }
    if (s == 'EXPIRED') {
      return 'Muda wa malipo umeisha kabla ya uthibitisho. Anza upya kutoka hatua ya 1.';
    }
    if (s == 'REJECTED' || s == 'DECLINED') {
      return 'Muamala haukuidhinishwa. Hakikisha una salio au namba sahihi, kisha jaribu tena.';
    }
    if (s == 'FAILED' || s == 'ERROR') {
      return 'Malipo hayajaweza kukamilika kwa sasa. Jaribu tena baada ya muda mfupi.';
    }
    return 'Malipo hayajakamilika. Jaribu tena au wasiliana na msaada wa WhatsApp.';
  }

  void _onInstructionContinue() {
    if (!mounted || _pollingOrderId == null) return;
    setState(() => _paymentUiPhase = _PaymentUiPhase.waiting);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
  }

  Future<void> _markPaymentCompleted({
    required String title,
    required String message,
  }) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _waitingTimer?.cancel();
    _waitingTimer = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingPaymentOrderId');

    if (!mounted) return;

    setState(() {
      _pollingOrderId = null;
      _notFoundStreak = 0;
      _paymentUiPhase = _PaymentUiPhase.none;
      _sessionEndDetail = null;
      _pendingBundleLabel = null;
    });

    _showStatus(title, message, _PayDialogTone.success);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await widget.onPaymentSuccess?.call();
  }

  Future<void> _openWhatsApp() async {
    if (_whatsapp == null || _whatsapp!.isEmpty) {
      _showStatus(
        'Hakuna namba ya WhatsApp',
        'Tafadhali wasiliana na admin kuongeza namba ya WhatsApp kwenye sehemu ya Settings.',
        _PayDialogTone.error,
      );
      return;
    }
    final phone = _whatsapp!.startsWith('+') ? _whatsapp!.substring(1) : _whatsapp!;
    final uri = Uri.parse('https://wa.me/$phone');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showStatus(
        'Tatizo',
        'Imeshindwa kufungua WhatsApp kwenye kifaa chako.',
        _PayDialogTone.error,
      );
    }
  }

  Future<void> _send() async {
    if (_selectedBundle == null) {
      _showStatus('Chagua bundle', 'Tafadhali chagua bundle unayotaka kulipa.', _PayDialogTone.error);
      return;
    }
    final clean = _cleanPhone;
    if (!_phoneValid(_phoneCtrl.text)) {
      _showStatus(
        'Nambari ya simu',
        'Hakikisha umeandika namba yako kwa usahihi na ukamilifu.',
        _PayDialogTone.error,
      );
      return;
    }
    if (_userId == null) {
      _showStatus(
        'Tatizo la akaunti',
        'Hatukuweza kutambua akaunti yako. Fungua tena sehemu ya wasifu (Profile) kisha ujaribu tena.',
        _PayDialogTone.error,
      );
      return;
    }

    final bundle = _bundles.firstWhere((b) => b.id == _selectedBundle);
    setState(() => _submitting = true);
    try {
      final result = await paymentsApi.startZenoPayment(
        externalId: _userId!,
        bundle: bundle.id,
        amount: bundle.value,
        phone: clean,
        email: '$_userId@eamax.app',
        name: _userId!,
      );
      final orderId = (result['orderId']?.toString() ?? '').trim();
      final serverMsg = (result['message']?.toString() ?? '').trim();

      if (orderId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pendingPaymentOrderId', orderId);
        if (!mounted) return;
        setState(() {
          _pollingOrderId = orderId;
          _notFoundStreak = 0;
          _paymentUiPhase = _PaymentUiPhase.instruction;
          _pendingBundleLabel = bundle.name;
        });
      } else {
        final msg = serverMsg.isNotEmpty
            ? serverMsg
            : 'Ombi la malipo la Tsh.${bundle.price} (${bundle.name}) limepokelewa kwa $clean. Ikiwa hutooni ujumbe kwenye simu, jaribu tena au wasiliana na msaada.';
        _showStatus('Tumepokea ombi', msg, _PayDialogTone.info);
      }
    } catch (e) {
      _showStatus('Malipo hayajatumika', _mapPaymentError(e), _PayDialogTone.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _simulatePaid() async {
    final id = _pollingOrderId;
    if (id == null || _simulating) return;
    setState(() => _simulating = true);
    try {
      await paymentsApi.completePaymentForTesting(id);
      await _markPaymentCompleted(
        title: 'Hongera — malipo yamehakikiwa',
        message: 'Malipo yamefaulu (jaribio la maendelezi). Akaunti yako inasasishwa kwa Premium.',
      );
    } catch (e) {
      _showStatus('Tatizo', _mapPaymentError(e), _PayDialogTone.error);
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = 48.0 + widget.bottomPadding;
    final ac = widget.accentColor;
    final canPay = _phoneOk && _selectedBundle != null && !_submitting;

    return Material(
      color: _scaffoldColor,
      child: Stack(
        children: [
          Positioned.fill(child: _PayAmbientLayer(accent: ac)),
          SafeArea(
            top: true,
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, 8, 22, bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PayPremiumHero(accent: ac),
                  const SizedBox(height: 22),
                  _PayTrustStrip(accent: ac),
                  const SizedBox(height: 26),
                  _PayGlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PayStepTitle(number: '01', title: 'Nambari ya simu', accent: ac),
                        const SizedBox(height: 6),
                        Text(
                          'Weka tarakimu 10 zote (anza na 0). Hatua inayofuata itaonekana ukimaliza namba yote.',
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: _payMuted,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 18),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: _paySurface,
                            border: Border.all(
                              color: _phoneOk ? _accentCta.withValues(alpha: 0.55) : _payLine,
                              width: _phoneOk ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 10,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    decoration: TextDecoration.none,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '074xxxxxxx',
                                    hintStyle: TextStyle(
                                      color: _payMuted.withValues(alpha: 0.65),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    counterText: '',
                                    contentPadding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Icon(
                                        Icons.phone_iphone_rounded,
                                        color: _phoneOk ? _accentCta : _payMuted,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) {
                                    setState(() {
                                      if (!_phoneOk) _selectedBundle = null;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_phoneOk) ...[
                    const SizedBox(height: 18),
                    _PayGlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PayStepTitle(number: '02', title: 'Chagua muda', accent: ac),
                          const SizedBox(height: 16),
                          ..._bundles.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PriceOptionTile(
                                bundle: b,
                                accent: ac,
                                selected: _selectedBundle == b.id,
                                onTap: () => setState(() => _selectedBundle = b.id),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (canPay) ...[
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _send,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: _accentCtaDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                                SizedBox(width: 10),
                                Text(
                                  'Lipia sasa',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                  if (kDebugMode && _pollingOrderId != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _simulating ? null : _simulatePaid,
                      child: Text(_simulating ? '...' : 'Test: Mark as paid'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_paymentUiPhase == _PaymentUiPhase.instruction && _pollingOrderId != null)
            Positioned.fill(
              child: _PaymentInstructionModal(
                bundleLabel: _pendingBundleLabel,
                onContinue: _onInstructionContinue,
              ),
            ),
          if (_paymentUiPhase == _PaymentUiPhase.waiting && _pollingOrderId != null)
            Positioned.fill(
              child: _PaymentWaitingModal(
                secondsRemaining: _waitingSeconds,
                totalSeconds: _kPaymentWaitSeconds,
              ),
            ),
          if (_paymentUiPhase == _PaymentUiPhase.timedOut || _paymentUiPhase == _PaymentUiPhase.failed)
            Positioned.fill(
              child: _PaymentSessionEndedModal(
                failed: _paymentUiPhase == _PaymentUiPhase.failed,
                detail: _sessionEndDetail,
                onStartOver: _resetPaymentFlowFromStepOne,
              ),
            ),
          if (_statusOpen)
            Center(
              child: Material(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_statusTitle, style: const TextStyle(color: Colors.white, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text(_statusMsg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => setState(() => _statusOpen = false),
                        child: const Text('Sawa'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PayAmbientLayer extends StatelessWidget {
  const _PayAmbientLayer({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PaymentInstructionModal extends StatelessWidget {
  const _PaymentInstructionModal({required this.bundleLabel, required this.onContinue});
  final String? bundleLabel;
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black87,
        child: Center(
          child: FilledButton(onPressed: onContinue, child: const Text('Nimeelewa — endelea')),
        ),
      );
}

class _PaymentSessionEndedModal extends StatelessWidget {
  const _PaymentSessionEndedModal({
    required this.failed,
    required this.detail,
    required this.onStartOver,
  });
  final bool failed;
  final String? detail;
  final VoidCallback onStartOver;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black87,
        child: Center(
          child: FilledButton(onPressed: onStartOver, child: const Text('Anza upya — hatua ya 1')),
        ),
      );
}

class _PaymentWaitingModal extends StatelessWidget {
  const _PaymentWaitingModal({required this.secondsRemaining, required this.totalSeconds});
  final int secondsRemaining;
  final int totalSeconds;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        child: Center(
          child: Text(
            'Tunasubiri uthibitisho: $secondsRemaining / $totalSeconds sekunde',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
}

class _PayPremiumHero extends StatelessWidget {
  const _PayPremiumHero({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) =>
      const Text('Fungua channel zote papo hapo', textAlign: TextAlign.center);
}

class _PayTrustStrip extends StatelessWidget {
  const _PayTrustStrip({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PayGlassPanel extends StatelessWidget {
  const _PayGlassPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _PayStepTitle extends StatelessWidget {
  const _PayStepTitle({
    required this.number,
    required this.title,
    required this.accent,
  });
  final String number;
  final String title;
  final Color accent;
  @override
  Widget build(BuildContext context) =>
      Text('$number $title', style: const TextStyle(color: Colors.white));
}

class _PriceOptionTile extends StatelessWidget {
  const _PriceOptionTile({
    required this.bundle,
    required this.accent,
    required this.selected,
    required this.onTap,
  });
  final _Bundle bundle;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        title: Text(bundle.priceLine, style: const TextStyle(color: Colors.white)),
        subtitle: Text('${bundle.name} · ${bundle.duration}', style: const TextStyle(color: Colors.white70)),
        trailing: selected ? const Icon(Icons.check, color: _accentCta) : null,
      );
}

class _Bundle {
  const _Bundle({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    required this.value,
    required this.popular,
    required this.priceLine,
  });
  final String id;
  final String name;
  final String price;
  final String duration;
  final int value;
  final bool popular;
  final String priceLine;
}
