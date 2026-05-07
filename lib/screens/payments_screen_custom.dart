import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/api.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/config/payment_helpers.dart'
    show
        isPaymentCompleted,
        isPaymentTerminalFailure,
        normalizedPaymentStatus;
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/user_id.dart';
import 'package:url_launcher/url_launcher.dart';

const _accentCta = Color(0xFF22C55E);
const _accentCtaDark = Color(0xFF16A34A);
const _accentBlue = Color(0xFF2563EB);

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
const _scaffold = Color(0xFF02040A);

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

class _PaymentsScreenState extends State<PaymentsScreen>
    with SingleTickerProviderStateMixin {
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
  AnimationController? _entryCtrl;

  AnimationController get _entryCtrlSafe {
    final existing = _entryCtrl;
    if (existing != null) return existing;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    _entryCtrl = created;
    return created;
  }

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
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
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
    _entryCtrl?.dispose();
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
      if (!mounted) {
        timer.cancel();
        return;
      }
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
    await prefs.remove('pendingPaymentPlanId');
    await prefs.remove('pendingPaymentPhone');
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
    _clearPendingOrderPrefs();
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
    final raw = e.toString().replaceFirst('Exception:', '').trim();
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
    if (raw.length > 220) {
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

  Future<void> _confirmPremiumOnBackend({
    required String orderId,
    required String publicId,
    required String planId,
    required String phone,
  }) async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return;
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/confirm-zeno-premium');
    await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
      body: jsonEncode({
        'orderId': orderId,
        'publicId': publicId,
        'planId': planId,
        'phone': phone,
      }),
    ).timeout(const Duration(seconds: 25));
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
    final planId = prefs.getString('pendingPaymentPlanId')?.trim();
    final phone = prefs.getString('pendingPaymentPhone')?.trim();
    final orderId = _pollingOrderId?.trim();
    final publicId = await UserIdentity.getOrCreatePublicId();

    if (planId != null && planId.isNotEmpty) {
      await SubscriptionStore.activatePlan(planId);
    }
    if (phone != null && phone.isNotEmpty) {
      await UserIdentity.savePhoneNumber(phone);
      await UserIdentity.registerWithBackend(phone: phone);
    }
    if (orderId != null &&
        orderId.isNotEmpty &&
        planId != null &&
        planId.isNotEmpty &&
        phone != null &&
        phone.isNotEmpty) {
      try {
        await _confirmPremiumOnBackend(
          orderId: orderId,
          publicId: publicId,
          planId: planId,
          phone: phone,
        );
        await SubscriptionStore.syncPremiumFromBackend();
      } catch (_) {}
    }
    SubscriptionStore.refreshNotifierFromPrefs();
    await _clearPendingOrderPrefs();

    if (!mounted) return;
    setState(() {
      _pollingOrderId = null;
      _notFoundStreak = 0;
      _paymentUiPhase = _PaymentUiPhase.none;
      _sessionEndDetail = null;
      _pendingBundleLabel = null;
    });

    _showStatus(title, message, _PayDialogTone.success);
    await Future<void>.delayed(const Duration(milliseconds: 300));
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
        await prefs.setString('pendingPaymentPlanId', bundle.id);
        await prefs.setString('pendingPaymentPhone', clean);
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
        message:
            'Malipo yamefaulu (jaribio la maendelezi). Akaunti yako inasasishwa kwa Premium.',
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
      color: _scaffold,
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
                  _Reveal(
                    controller: _entryCtrlSafe,
                    delay: 0.00,
                    child: _PayPremiumHero(accent: ac),
                  ),
                  const SizedBox(height: 22),
                  _Reveal(
                    controller: _entryCtrlSafe,
                    delay: 0.08,
                    child: _PayTrustStrip(accent: ac),
                  ),
                  const SizedBox(height: 26),
                  _Reveal(
                    controller: _entryCtrlSafe,
                    delay: 0.16,
                    child: _PayGlassPanel(
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
                              if (_phoneOk)
                                Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _accentCta.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: _accentCta,
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                  if (_phoneOk) ...[
                    const SizedBox(height: 18),
                    _Reveal(
                      controller: _entryCtrlSafe,
                      delay: 0.26,
                      child: _PayGlassPanel(
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
                    ),
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(sizeFactor: animation, child: child),
                    ),
                    child: canPay
                        ? Padding(
                            key: const ValueKey('pay-button'),
                            padding: const EdgeInsets.only(top: 12),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.97, end: 1.0),
                              duration: const Duration(milliseconds: 230),
                              curve: Curves.easeOutBack,
                              builder: (_, scale, child) =>
                                  Transform.scale(scale: scale, child: child),
                              child: SizedBox(
                                height: 58,
                                child: FilledButton.icon(
                                  onPressed: _send,
                                  icon: _submitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.bolt_rounded),
                                  label: Text(_submitting ? 'Inatuma...' : 'Lipia sasa'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _accentCtaDark,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-pay-button')),
                  ),
                  const SizedBox(height: 14),
                  _Reveal(
                    controller: _entryCtrlSafe,
                    delay: 0.36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF86EFAC), Color(0xFF4ADE80), Color(0xFF22C55E)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4ADE80).withValues(alpha: 0.34),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: const Color(0xFF86EFAC).withValues(alpha: 0.20),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openWhatsApp,
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.20),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.chat_rounded,
                                    color: Color(0xFF065F46),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Msaada wa haraka - WhatsApp',
                                    style: TextStyle(
                                      color: Color(0xFF064E3B),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Color(0xFF065F46),
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (kDebugMode && _pollingOrderId != null) ...[
                    const SizedBox(height: 10),
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
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Material(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _statusTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _statusMsg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blueGrey.shade300,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: () => setState(() => _statusOpen = false),
                            style: FilledButton.styleFrom(
                              backgroundColor: _statusTone == _PayDialogTone.error
                                  ? const Color(0xFFE8002D)
                                  : _accentBlue,
                            ),
                            child: const Text('Sawa'),
                          ),
                        ],
                      ),
                    ),
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
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF02040A), Color(0xFF0B1220), Color(0xFF050810)],
              stops: [0.0, 0.42, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -100,
          right: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.11)),
          ),
        ),
      ],
    );
  }
}

class _PaymentInstructionModal extends StatelessWidget {
  const _PaymentInstructionModal({
    required this.bundleLabel,
    required this.onContinue,
  });

  final String? bundleLabel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF151B2E), Color(0xFF0A0F18)],
                ),
                border: Border.all(color: const Color(0x28FFFFFF)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.smartphone_rounded, size: 38, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'Hatua inayofuata - simu yako',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  if (bundleLabel != null && bundleLabel!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Chaguo: $bundleLabel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _accentBlue.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Angalia katika simu yako na umalizie hatua zilizobakia kukamilisha zoezi zima.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.55, color: Colors.white.withValues(alpha: 0.82)),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onContinue,
                      child: const Text('Nimeelewa - endelea'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.84),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFF171F35),
              border: Border.all(color: const Color(0x28FFFFFF)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  failed ? 'Malipo hayajakamilika' : 'Muda wa kusubiri umeisha',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  detail ?? 'Jaribu tena.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onStartOver,
                    child: const Text('Anza upya - hatua ya 1'),
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

class _PaymentWaitingModal extends StatelessWidget {
  const _PaymentWaitingModal({
    required this.secondsRemaining,
    required this.totalSeconds,
  });

  final int secondsRemaining;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final total = totalSeconds <= 0 ? 1 : totalSeconds;
    return Material(
      color: Colors.black.withValues(alpha: 0.76),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: const Color(0xFF141B2D),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Subiri uthibitisho kwenye simu',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 14),
              Text(
                'Tunasubiri uthibitisho: $secondsRemaining / $total sekunde',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayPremiumHero extends StatelessWidget {
  const _PayPremiumHero({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Fungua channel zote papo hapo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.75,
            color: accent,
          ),
        ),
      ],
    );
  }
}

class _PayTrustStrip extends StatelessWidget {
  const _PayTrustStrip({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _payLine),
        gradient: LinearGradient(
          colors: [
            _paySurface.withValues(alpha: 0.9),
            _paySurface2.withValues(alpha: 0.5),
          ],
        ),
      ),
      child: Text(
        'Mitandao ya Tanzania: M-Pesa, Airtel, Mix, HaloPesa',
        textAlign: TextAlign.center,
        style: TextStyle(color: _payMuted, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PayGlassPanel extends StatelessWidget {
  const _PayGlassPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _payLine),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: child,
    );
  }
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: accent.withValues(alpha: 0.35),
          ),
          child: Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? _accentCta.withValues(alpha: 0.65) : _payLine,
              width: selected ? 1.5 : 1,
            ),
            color: _paySurface,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.priceLine,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${bundle.name}  ·  ${bundle.duration}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _payMuted),
                      ),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_rounded, color: _accentCta),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.controller,
    required this.delay,
    required this.child,
  });

  final AnimationController controller;
  final double delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = delay.clamp(0.0, 0.9);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        final t = animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
