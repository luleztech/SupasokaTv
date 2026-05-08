import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/api.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/config/payment_helpers.dart'
    show
        isPaymentCompleted,
        isPaymentTerminalFailure,
        normalizedPaymentStatus;
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/user_id.dart';
import 'package:supasoka/data/pay_plan.dart';

const _accentCta = Color(0xFF22C55E);
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

/// USSD / wallet confirmation often takes 1–3+ minutes; 60s caused false “Anza upya” while Zeno was still pending.
const int _kPaymentWaitSeconds = 300;

/// Shown only after the server has activated premium (same moment admin sees it).
const _kPremiumSuccessTitle = 'HONGERA';
const _kPremiumSuccessMessage =
    'Umefanikiwa kufungua channel zote na karibu sana katika familia ya Supasoka. Hautojutia.';

enum _PaymentUiPhase { none, instruction, waiting, timedOut, failed }
enum _PayDialogTone { success, error, info }
enum _ConfirmProbeKind { pending, completed, terminalFailure }

class _ConfirmProbeOutcome {
  const _ConfirmProbeOutcome._(this.kind, {this.paymentStatus});
  final _ConfirmProbeKind kind;
  final String? paymentStatus;

  factory _ConfirmProbeOutcome.pending() => const _ConfirmProbeOutcome._(_ConfirmProbeKind.pending);
  factory _ConfirmProbeOutcome.completed() => const _ConfirmProbeOutcome._(_ConfirmProbeKind.completed);
  factory _ConfirmProbeOutcome.terminalFailure(String? status) =>
      _ConfirmProbeOutcome._(_ConfirmProbeKind.terminalFailure, paymentStatus: status);
}

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
  String? _userId;
  bool _submitting = false;
  bool _statusOpen = false;
  String _statusTitle = '';
  String _statusMsg = '';
  _PayDialogTone _statusTone = _PayDialogTone.info;
  String? _pendingBundleLabel;
  String? _pollingOrderId;
  int _notFoundStreak = 0;
  bool _simulating = false;
  int _waitingSeconds = _kPaymentWaitSeconds;
  Timer? _waitingTimer;
  _PaymentUiPhase _paymentUiPhase = _PaymentUiPhase.none;
  String? _sessionEndDetail;
  AnimationController? _entryCtrl;
  /// Incremented to cancel in-flight adaptive poll [Future]s (replaces fixed [Timer] polling).
  int _pollGen = 0;
  /// Avoids double [addPostFrameCallback] / double-tap starting two polls so the first gen is never invalidated before any HTTP check.
  bool _paymentPollArmed = false;
  /// Prevents countdown timeout from racing past a successful poll / [confirm] round-trip.
  bool _paymentCompletionInProgress = false;

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

  List<_Bundle> _bundlesFromStore(List<PayPlan> plans) {
    final out = <_Bundle>[];
    for (final p in plans) {
      final amountRaw = p.amount.replaceAll(RegExp(r'[^0-9]'), '');
      final amount = int.tryParse(amountRaw);
      if (amount == null || amount <= 0) continue;
      final priceDigits = amount.toString();
      final priceLine = p.priceLines.trim().isNotEmpty
          ? p.priceLines.trim().replaceAll('\n', '. ')
          : 'TSh $priceDigits/=';
      out.add(
        _Bundle(
          id: p.id,
          name: p.label.trim().isEmpty ? p.period : p.label,
          price: priceDigits,
          duration: p.period,
          value: amount,
          popular: p.popular,
          priceLine: priceLine,
          accent1: p.accent1,
          accent2: p.accent2,
          badge: p.badge,
        ),
      );
    }
    return out;
  }

  bool _phoneValid(String raw) {
    final clean = raw.replaceAll(RegExp(r'\s+'), '');
    if (clean.length != 10) return false;
    if (!RegExp(r'^0\d{9}$').hasMatch(clean)) return false;
    return _tzPrefixes.any((p) => clean.startsWith(p));
  }

  String get _cleanPhone => _phoneCtrl.text.replaceAll(RegExp(r'\s+'), '');
  bool get _phoneOk => _phoneValid(_phoneCtrl.text);

  /// Zeno / proxy responses vary; normalize so [isPaymentCompleted] sees the real status.
  Object? _paymentStatusFromCheckResponse(Map<String, dynamic> response) {
    Object? pickRow(Map<String, dynamic> m) {
      for (final k in const [
        'payment_status',
        'PaymentStatus',
        'paymentStatus',
        'transaction_status',
        'TransactionStatus',
        'order_status',
        'OrderStatus',
        'payment_state',
        'PaymentState',
      ]) {
        final v = m[k];
        if (v == null) continue;
        if (v.toString().trim().isEmpty) continue;
        return v;
      }
      return null;
    }

    final top = pickRow(response);
    if (top != null) return top;

    final raw = response['raw'];
    if (raw is Map) {
      final rawMap = Map<String, dynamic>.from(raw);
      final fromRaw = pickRow(rawMap);
      if (fromRaw != null) return fromRaw;

      final data = rawMap['data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        final row = pickRow(Map<String, dynamic>.from(data.first as Map));
        if (row != null) return row;
      }
      if (data is Map) {
        final row = pickRow(Map<String, dynamic>.from(data));
        if (row != null) return row;
      }
    }

    final dataTop = response['data'];
    if (dataTop is List && dataTop.isNotEmpty && dataTop.first is Map) {
      return pickRow(Map<String, dynamic>.from(dataTop.first as Map));
    }
    if (dataTop is Map) {
      return pickRow(Map<String, dynamic>.from(dataTop));
    }
    return null;
  }

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
    final uid = await getOrCreateUserId();
    if (uid != null && uid.isNotEmpty) {
      setState(() => _userId = uid);
    }

    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pendingPaymentOrderId')?.trim();
    if (pending == null || pending.isEmpty) return;

    try {
      final res = await paymentsApi.checkZenoStatus(pending);
      final st = _paymentStatusFromCheckResponse(res);
      if (isPaymentCompleted(st)) {
        _stopPaymentTimersOnly();
        await _markPaymentCompleted();
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
    _stopPaymentTimersOnly();
    _phoneCtrl.dispose();
    _entryCtrl?.dispose();
    super.dispose();
  }

  void _stopPaymentTimersOnly() {
    _pollGen++;
    _paymentPollArmed = false;
    _waitingTimer?.cancel();
    _waitingTimer = null;
    if (mounted) {
      setState(() {
        _waitingSeconds = 0;
      });
    }
  }

  void _startPolling() {
    final orderId = _pollingOrderId?.trim();
    if (orderId == null || orderId.isEmpty) return;
    if (_paymentPollArmed) return;
    _paymentPollArmed = true;

    _pollGen++;
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

    final gen = _pollGen;
    unawaited(_adaptivePaymentPollLoop(orderId, gen));
  }

  /// Fast status checks first (like [ZenoPayService.waitForCompleted]), then ~2s — detects paid sooner than fixed 3s polling.
  Future<void> _adaptivePaymentPollLoop(String orderId, int gen) async {
    const warmDelaysMs = <int>[0, 650, 950, 1300, 1700, 2100, 2500];
    var warmIdx = 0;
    var confirmProbeTick = 0;
    final deadline = DateTime.now().add(Duration(seconds: _kPaymentWaitSeconds));

    while (mounted && gen == _pollGen && !_paymentCompletionInProgress) {
      if (DateTime.now().isAfter(deadline)) {
        if (_pollingOrderId != null && _pollingOrderId == orderId && !_paymentCompletionInProgress) {
          await _finalizeSessionTimedOut(
            detail:
                'Muda wa kusubiri umeisha. Malipo ya simu yanaweza bado yanaendelea — jaribu tena au fungua programu baada ya muda mfupi.',
          );
        }
        return;
      }

      final delayMs = warmIdx < warmDelaysMs.length ? warmDelaysMs[warmIdx] : 2000;
      warmIdx++;
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      if (!mounted || gen != _pollGen || _paymentCompletionInProgress) return;

      try {
        final response = await paymentsApi.checkZenoStatus(orderId);
        if (!mounted || gen != _pollGen || _paymentCompletionInProgress) return;
        final paymentStatus = _paymentStatusFromCheckResponse(response);
        if (isPaymentCompleted(paymentStatus)) {
          _stopPaymentTimersOnly();
          await _markPaymentCompleted();
          return;
        }
        if (isPaymentTerminalFailure(paymentStatus)) {
          await _finalizeSessionFailed(_paymentFailureUserMessage(paymentStatus));
          return;
        }
        confirmProbeTick++;
        if (confirmProbeTick % 3 == 0) {
          try {
            final probe = await _probeConfirmWhilePending(orderId);
            if (!mounted || gen != _pollGen || _paymentCompletionInProgress) return;
            if (probe.kind == _ConfirmProbeKind.completed) {
              _stopPaymentTimersOnly();
              await _markPaymentCompleted();
              return;
            }
            if (probe.kind == _ConfirmProbeKind.terminalFailure) {
              await _finalizeSessionFailed(_paymentFailureUserMessage(probe.paymentStatus));
              return;
            }
          } catch (_) {
            // keep polling; transient backend/provider lag.
          }
        }
        _notFoundStreak = 0;
      } catch (e) {
        if (!mounted || gen != _pollGen) return;
        final msg = e.toString().toLowerCase();
        if (msg.contains('no order') || msg.contains('not found')) {
          _notFoundStreak++;
          if (_notFoundStreak >= 20) {
            _stopPaymentTimersOnly();
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
            return;
          }
        }
      }
    }
  }

  Future<void> _clearPendingOrderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingPaymentOrderId');
    await prefs.remove('pendingPaymentPlanId');
    await prefs.remove('pendingPaymentPhone');
  }

  void _handleWaitWindowExpired() {
    if (!mounted || _pollingOrderId == null) return;
    if (_paymentCompletionInProgress) return;
    unawaited(_handleWaitWindowExpiredAsync());
  }

  /// Last chance: Zeno may flip to completed right as the countdown hits zero.
  Future<void> _handleWaitWindowExpiredAsync() async {
    if (_paymentCompletionInProgress || !mounted) return;
    final id = _pollingOrderId?.trim();
    if (id == null || id.isEmpty) {
      await _finalizeSessionTimedOut(
        detail:
            'Muda wa kusubiri umeisha bila uthibitisho. Hakikisha umeingiza PIN kwenye simu, kisha jaribu tena.',
      );
      return;
    }
    try {
      final response = await paymentsApi.checkZenoStatus(id);
      final paymentStatus = _paymentStatusFromCheckResponse(response);
      if (isPaymentCompleted(paymentStatus)) {
        _stopPaymentTimersOnly();
        await _markPaymentCompleted();
        return;
      }
      if (isPaymentTerminalFailure(paymentStatus)) {
        await _finalizeSessionFailed(_paymentFailureUserMessage(paymentStatus));
        return;
      }
    } catch (_) {
      // fall through to timeout
    }
    if (!mounted || _paymentCompletionInProgress) return;
    await _finalizeSessionTimedOut(
      detail:
          'Muda wa dakika ${_kPaymentWaitSeconds ~/ 60} umeisha bila uthibitisho wa haraka. Malipo yako yanaweza bado yanaendelea — jaribu tena au subiri kidogo kisha fungua programu tena.',
    );
  }

  Future<void> _finalizeSessionTimedOut({String? detail}) async {
    if (_paymentCompletionInProgress) return;
    _stopPaymentTimersOnly();
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
    if (_paymentCompletionInProgress) return;
    _stopPaymentTimersOnly();
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
    _paymentCompletionInProgress = false;
    _stopPaymentTimersOnly();
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

  /// Returns server [premiumUntilMs] only when the backend has verified Zeno and written premium.
  Future<int?> _confirmPremiumOnBackend({
    required String orderId,
    required String publicId,
    required String planId,
    required String phone,
  }) async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return null;
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/confirm-zeno-premium');
    for (var attempt = 0; attempt < 5; attempt++) {
      final res = await http
          .post(
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
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          if (j['ok'] == true) {
            final raw = j['premiumUntilMs'];
            if (raw is int) return raw;
            if (raw is num) return raw.toInt();
          }
        } catch (_) {}
      } else if (kDebugMode) {
        debugPrint('confirm-zeno-premium HTTP ${res.statusCode}: ${res.body}');
      }

      // 402 from backend means "still not completed on provider side".
      if (res.statusCode == 402 && attempt < 4) {
        await Future<void>.delayed(Duration(milliseconds: 900 + (attempt * 600)));
        continue;
      }
      break;
    }
    return null;
  }

  Future<_ConfirmProbeOutcome> _probeConfirmWhilePending(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final planId = prefs.getString('pendingPaymentPlanId')?.trim();
    final phone = prefs.getString('pendingPaymentPhone')?.trim();
    if (planId == null || planId.isEmpty) return _ConfirmProbeOutcome.pending();

    final publicId = await UserIdentity.getOrCreatePublicId();
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return _ConfirmProbeOutcome.pending();
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/confirm-zeno-premium');

    final res = await http
        .post(
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
            'phone': phone ?? '',
          }),
        )
        .timeout(const Duration(seconds: 18));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return _ConfirmProbeOutcome.completed();
    }

    if (res.statusCode == 409) {
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return _ConfirmProbeOutcome.terminalFailure(j['paymentStatus']?.toString());
      } catch (_) {
        return _ConfirmProbeOutcome.terminalFailure(null);
      }
    }
    return _ConfirmProbeOutcome.pending();
  }

  /// Zeno reports completed — unlock premium immediately, then sync with server.
  Future<void> _markPaymentCompleted() async {
    if (_paymentCompletionInProgress) return;
    _paymentCompletionInProgress = true;
    
    // Stop all timers and polling FIRST
    _stopPaymentTimersOnly();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final planId = prefs.getString('pendingPaymentPlanId')?.trim();
      final phone = prefs.getString('pendingPaymentPhone')?.trim();
      final pendingOrderFromPrefs = prefs.getString('pendingPaymentOrderId')?.trim();
      final orderId = pendingOrderFromPrefs ?? '';
      final publicId = await UserIdentity.getOrCreatePublicId();

      if (phone != null && phone.isNotEmpty) {
        await UserIdentity.savePhoneNumber(phone);
        await UserIdentity.registerWithBackend(phone: phone);
      }

      // Unlock premium locally immediately
      if (planId != null && planId.isNotEmpty) {
        await SubscriptionStore.activatePlan(planId);
      }

      // Try to confirm with server for accurate timing and admin visibility
      int? serverUntilMs;
      if (orderId.isNotEmpty && planId != null && planId.isNotEmpty) {
        try {
          serverUntilMs = await _confirmPremiumOnBackend(
            orderId: orderId,
            publicId: publicId,
            planId: planId,
            phone: phone ?? '',
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('confirm-zeno-premium request failed: $e');
          }
        }
      }

      // If server confirmation succeeded, update with precise server time
      if (serverUntilMs != null) {
        await SubscriptionStore.setPremiumUntilMs(serverUntilMs);
      }

      // Sync premium status from backend
      await SubscriptionStore.syncPremiumFromBackend();
      SubscriptionStore.refreshNotifierFromPrefs();
      await _clearPendingOrderPrefs();

      if (mounted) {
        // Clear the waiting modal completely and show success
        setState(() {
          _pollingOrderId = null;
          _paymentUiPhase = _PaymentUiPhase.none;
          _notFoundStreak = 0;
          _sessionEndDetail = null;
          _pendingBundleLabel = null;
          _waitingSeconds = 0;
        });

        _showStatus(_kPremiumSuccessTitle, _kPremiumSuccessMessage, _PayDialogTone.success);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await widget.onPaymentSuccess?.call();
      }
    } finally {
      _paymentCompletionInProgress = false;
    }
  }

  Future<void> _send() async {
    final bundles = _bundlesFromStore(context.read<ContentStore>().malipoPayPlans);
    if (bundles.isEmpty) {
      _showStatus(
        'Mipango hayajapatikana',
        'Bei zinasimamiwa na msimamizi kwenye SupaAdmin (Malipo). Sasisha ukurasa huu baada ya kuweka mipango.',
        _PayDialogTone.info,
      );
      return;
    }
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

    _Bundle? bundle;
    for (final b in bundles) {
      if (b.id == _selectedBundle) {
        bundle = b;
        break;
      }
    }
    if (bundle == null) {
      _showStatus(
        'Chagua mpango tena',
        'Mipango yalisasishwa. Chagua bei/kipindi tena.',
        _PayDialogTone.info,
      );
      return;
    }
    final plan = bundle;

    setState(() => _submitting = true);
    try {
      final result = await paymentsApi.startZenoPayment(
        externalId: _userId!,
        bundle: plan.id,
        amount: plan.value,
        phone: clean,
        email: '$_userId@eamax.app',
        name: _userId!,
      );
      final orderId = (result['orderId']?.toString() ?? '').trim();
      final serverMsg = (result['message']?.toString() ?? '').trim();

      if (orderId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pendingPaymentOrderId', orderId);
        await prefs.setString('pendingPaymentPlanId', plan.id);
        await prefs.setString('pendingPaymentPhone', clean);
        if (!mounted) return;
        setState(() {
          _pollingOrderId = orderId;
          _notFoundStreak = 0;
          _paymentUiPhase = _PaymentUiPhase.instruction;
          _pendingBundleLabel = plan.name;
        });
      } else {
        final msg = serverMsg.isNotEmpty
            ? serverMsg
            : 'Ombi la malipo la Tsh.${plan.price} (${plan.name}) limepokelewa kwa $clean. Ikiwa hutooni ujumbe kwenye simu, jaribu tena au wasiliana na msaada.';
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
      await _markPaymentCompleted();
    } catch (e) {
      _showStatus('Tatizo', _mapPaymentError(e), _PayDialogTone.error);
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottom = 28 + safeBottom + widget.bottomPadding;
    final ac = widget.accentColor;
    final content = context.watch<ContentStore>();
    final bundles = _bundlesFromStore(content.malipoPayPlans);
    if (_selectedBundle != null && !bundles.any((b) => b.id == _selectedBundle)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedBundle = null);
      });
    }
    final canPay = _phoneOk && _selectedBundle != null && !_submitting;

    return Material(
      color: _scaffold,
      child: Stack(
        children: [
          Positioned.fill(child: _PayAmbientLayer(accent: ac)),
          SafeArea(
            top: true,
            bottom: false,
            child: RefreshIndicator(
              color: _accentCta,
              onRefresh: () => context.read<ContentStore>().refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                          if (bundles.isEmpty)
                            _MalipoPlansEmptyPanel(
                              accent: ac,
                              refreshing: content.refreshing,
                              onRefresh: () => context.read<ContentStore>().refresh(),
                            )
                          else
                            ...bundles.map(
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
                            padding: const EdgeInsets.only(top: 16),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.98, end: 1.0),
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              builder: (_, scale, child) =>
                                  Transform.scale(scale: scale, child: child),
                              child: _PremiumPayCta(
                                submitting: _submitting,
                                onPressed: _send,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-pay-button')),
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
                elapsedSeconds: (_kPaymentWaitSeconds - _waitingSeconds).clamp(0, _kPaymentWaitSeconds),
                maxWaitSeconds: _kPaymentWaitSeconds,
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

/// Full-width premium CTA — gradient, glow, clear hierarchy (Fungua zote tab only; no WhatsApp FAB here).
class _PremiumPayCta extends StatelessWidget {
  const _PremiumPayCta({required this.submitting, required this.onPressed});

  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF4ADE80),
        Color(0xFF22C55E),
        Color(0xFF15803D),
      ],
      stops: [0.0, 0.48, 1.0],
    );
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: gradient,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22C55E).withValues(alpha: 0.42),
              blurRadius: 22,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: submitting ? null : onPressed,
            borderRadius: BorderRadius.circular(20),
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Center(
                child: submitting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Inatuma…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, color: Colors.white.withValues(alpha: 0.95), size: 26),
                          const SizedBox(width: 10),
                          Text(
                            'Lipia sasa',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.98),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.35,
                            ),
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
    required this.elapsedSeconds,
    required this.maxWaitSeconds,
  });

  final int elapsedSeconds;
  final int maxWaitSeconds;

  @override
  Widget build(BuildContext context) {
    final max = maxWaitSeconds <= 0 ? 1 : maxWaitSeconds;
    final progress = (elapsedSeconds / max).clamp(0.0, 1.0);
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
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.white10,
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Sekunde $elapsedSeconds · tunahakiki malipo mara kwa mara (haraka mwanzoni)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.82), height: 1.35),
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

class _MalipoPlansEmptyPanel extends StatelessWidget {
  const _MalipoPlansEmptyPanel({
    required this.accent,
    required this.refreshing,
    required this.onRefresh,
  });

  final Color accent;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _payLine),
        color: _paySurface2.withValues(alpha: 0.65),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.settings_suggest_rounded,
            size: 42,
            color: accent.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 14),
          const Text(
            'Hakuna vifurushi',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Vifurushi vitaonekana pale admin akiweka kwasasa furahia channel za bure ahsante',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: _payMuted.withValues(alpha: 0.95),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: refreshing ? null : () => onRefresh(),
            icon: refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent.withValues(alpha: 0.9),
                    ),
                  )
                : const Icon(Icons.sync_rounded, size: 20),
            label: Text(refreshing ? 'inatafuta...' : 'Jaribu tena'),
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: accent.withValues(alpha: 0.22),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
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
    final lineAccent = bundle.accent1;
    final lineAccent2 = bundle.accent2;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? _accentCta.withValues(alpha: 0.65) : _payLine,
                width: selected ? 1.5 : 1,
              ),
              color: _paySurface,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [lineAccent, lineAccent2],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        bundle.priceLine,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (bundle.badge.trim().isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: lineAccent.withValues(alpha: 0.55),
                                          ),
                                          color: lineAccent.withValues(alpha: 0.14),
                                        ),
                                        child: Text(
                                          bundle.badge.trim(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                            color: lineAccent.withValues(alpha: 1),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${bundle.name}  ·  ${bundle.duration}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: _payMuted,
                                  ),
                                ),
                                if (bundle.popular) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.star_rounded, size: 15, color: accent.withValues(alpha: 0.9)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Mpango maarufu',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: accent.withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (selected)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.check_rounded, color: _accentCta),
                            ),
                        ],
                      ),
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

class _Bundle {
  const _Bundle({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    required this.value,
    required this.popular,
    required this.priceLine,
    required this.accent1,
    required this.accent2,
    this.badge = '',
  });
  final String id;
  final String name;
  final String price;
  final String duration;
  final int value;
  final bool popular;
  final String priceLine;
  final Color accent1;
  final Color accent2;
  final String badge;
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
