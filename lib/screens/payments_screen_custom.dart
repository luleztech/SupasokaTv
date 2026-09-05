import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/big_screen_payment_pricing.dart';
import 'package:supasoka/config/api.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/config/payment_helpers.dart'
    show
        isPaymentCompleted,
        isPaymentTerminalFailure,
        normalizedPaymentStatus,
        paymentStatusFromCheckResponse;
import 'package:supasoka/services/premium_recovery.dart';
import 'package:supasoka/services/app_update_service.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/tanzania_phone.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/user_id.dart';
import 'package:supasoka/data/pay_plan.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supasoka/widgets/audio_guide_card.dart';

const _accentCta = BrandPalette.accent;
const _accentBlue = BrandPalette.accent;

const _paySurface = BrandPalette.bgMid;
const _paySurface2 = BrandPalette.bgDeep;
const _payLine = Color(0x14FFFFFF);
const _payMuted = Color(0xFF8B9CAF);
const _scaffold = BrandPalette.bgDeep;

/// Active wait overlay while the user confirms USSD on the phone.
const int _kPaymentWaitSeconds = 90;

/// Shown only after the server has activated premium (same moment admin sees it).
const _kPremiumSuccessTitle = 'HONGERA';
const _kPremiumSuccessMessage =
    'Umefanikiwa kufungua channel zote na karibu sana katika familia ya Supasoka. Hautojutia.';

enum _PaymentUiPhase { none, instruction, waiting, timedOut, failed }
enum _PayDialogTone { success, error, info }
enum _ConfirmProbeKind { pending, completed }

class _ConfirmProbeOutcome {
  const _ConfirmProbeOutcome._(this.kind, {this.premiumUntilMs});
  final _ConfirmProbeKind kind;
  final int? premiumUntilMs;

  factory _ConfirmProbeOutcome.pending() => const _ConfirmProbeOutcome._(_ConfirmProbeKind.pending);
  factory _ConfirmProbeOutcome.completed({int? premiumUntilMs}) =>
      _ConfirmProbeOutcome._(_ConfirmProbeKind.completed, premiumUntilMs: premiumUntilMs);
}

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    this.accentColor = _accentBlue,
    this.bottomPadding = 0,
    this.onPaymentSuccess,
    this.autoPlayGuide = true,
    this.desktopLayout = false,
    this.onClose,
    this.contextTitle,
    this.audioAssetPackage,
  });

  final Color accentColor;
  final double bottomPadding;
  final Future<void> Function()? onPaymentSuccess;
  /// Auto-start the audio guide while this screen is the active payments view.
  final bool autoPlayGuide;
  /// Wide-screen layout for SupaTV / desktop (two-column checkout).
  final bool desktopLayout;
  final VoidCallback? onClose;
  /// e.g. locked channel name shown in the TV checkout header.
  final String? contextTitle;
  /// Package that owns payment audio assets (e.g. `supatv` on desktop builds).
  final String? audioAssetPackage;

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
  /// Ensures only one expiry handler runs when the poll loop and countdown fire together.
  bool _waitExpiryHandling = false;
  String _submitStatus = '';
  Timer? _submitStageTimer;

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
    final source = widget.desktopLayout ? BigScreenPaymentPricing.applyAll(plans) : plans;
    final out = <_Bundle>[];
    for (final p in source) {
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

  bool _phoneValid(String raw) => TanzaniaPhone.isValid(raw);

  String get _cleanPhone => TanzaniaPhone.normalize(_phoneCtrl.text) ?? '';

  String get _paymentWaitWindowLabel {
    if (_kPaymentWaitSeconds >= 60 && _kPaymentWaitSeconds % 60 == 0) {
      final mins = _kPaymentWaitSeconds ~/ 60;
      return mins == 1 ? 'dakika 1' : 'dakika $mins';
    }
    return 'sekunde $_kPaymentWaitSeconds';
  }

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
    final uid = await getOrCreateUserId();
    if (uid != null && uid.isNotEmpty) {
      setState(() => _userId = uid);
      unawaited(UserIdentity.registerWithBackend());
    }

    final savedPhone = await UserIdentity.getSavedPhoneNumber();
    final savedLocal = savedPhone != null ? TanzaniaPhone.normalize(savedPhone) : null;
    if (savedLocal != null && savedLocal.length == 10 && mounted) {
      _phoneCtrl.text = savedLocal;
    }

    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pendingPaymentOrderId')?.trim();
    if (pending == null || pending.isEmpty) return;

    try {
      final res = await paymentsApi.checkPaymentStatus(pending);
      final st = paymentStatusFromCheckResponse(res);
      if (isPaymentCompleted(st)) {
        final premiumMs = res['premiumUntilMs'];
        final serverActivated = res['activated'] == true;
        if (serverActivated && premiumMs is num) {
          _stopPaymentTimersOnly();
          await _markPaymentCompleted(serverPremiumUntilMs: premiumMs.toInt());
        } else {
          final recovered = await PremiumRecovery.recoverPendingPaymentIfAny();
          if (recovered && mounted) {
            _stopPaymentTimersOnly();
            setState(() {
              _pollingOrderId = null;
              _paymentUiPhase = _PaymentUiPhase.none;
            });
            _showStatus(_kPremiumSuccessTitle, _kPremiumSuccessMessage, _PayDialogTone.success);
            await widget.onPaymentSuccess?.call();
            return;
          }
          setState(() {
            _pollingOrderId = pending;
            _paymentUiPhase = _PaymentUiPhase.waiting;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
        }
      } else if (isPaymentTerminalFailure(st)) {
        await _clearPendingOrderPrefs();
        if (mounted) {
          setState(() {
            _paymentUiPhase = _PaymentUiPhase.failed;
            _sessionEndDetail = _paymentFailureUserMessage(st);
          });
        }
      } else {
        final createdAtMs = prefs.getInt('pendingPaymentCreatedAtMs') ?? 0;
        final ageMs = createdAtMs > 0
            ? DateTime.now().millisecondsSinceEpoch - createdAtMs
            : 0;
        if (createdAtMs > 0 && ageMs > const Duration(minutes: 20).inMilliseconds) {
          await _clearPendingOrderPrefs();
          return;
        }
        setState(() {
          _pollingOrderId = pending;
          _paymentUiPhase = _PaymentUiPhase.waiting;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
      }
    } catch (e) {
      await _clearPendingOrderPrefs();
      if (mounted) {
        setState(() {
          _paymentUiPhase = _PaymentUiPhase.failed;
          _sessionEndDetail = _mapPaymentError(e);
        });
      }
    }
  }

  /// Drop abandoned pending checkout before a fresh "Lipia sasa" tap.
  Future<void> _prepareForNewPaymentAttempt() async {
    if (_paymentUiPhase == _PaymentUiPhase.waiting &&
        _pollingOrderId != null &&
        _pollingOrderId!.isNotEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pendingPaymentOrderId')?.trim();
    if (pending == null || pending.isEmpty) return;

    try {
      final res = await paymentsApi.checkPaymentStatus(pending);
      final st = paymentStatusFromCheckResponse(res);
      if (isPaymentCompleted(st)) return;
      if (isPaymentTerminalFailure(st)) {
        await _clearPendingOrderPrefs();
        return;
      }
    } catch (_) {
      if (_paymentUiPhase == _PaymentUiPhase.failed ||
          _paymentUiPhase == _PaymentUiPhase.timedOut) {
        await _clearPendingOrderPrefs();
        return;
      }
    }

    if (_paymentUiPhase == _PaymentUiPhase.failed ||
        _paymentUiPhase == _PaymentUiPhase.timedOut ||
        _paymentUiPhase == _PaymentUiPhase.none) {
      final createdAtMs = prefs.getInt('pendingPaymentCreatedAtMs') ?? 0;
      final ageMs = createdAtMs > 0
          ? DateTime.now().millisecondsSinceEpoch - createdAtMs
          : const Duration(hours: 1).inMilliseconds;
      if (ageMs >= _kPaymentWaitSeconds * 1000) {
        await _clearPendingOrderPrefs();
      }
    }
  }

  @override
  void dispose() {
    _submitStageTimer?.cancel();
    _stopPaymentTimersOnly(notify: false);
    _phoneCtrl.dispose();
    _entryCtrl?.dispose();
    super.dispose();
  }

  void _stopPaymentTimersOnly({bool notify = true}) {
    _pollGen++;
    _paymentPollArmed = false;
    _waitExpiryHandling = false;
    _waitingTimer?.cancel();
    _waitingTimer = null;
    _waitingSeconds = 0;
    // Never call setState from dispose — the element is already unmounting.
    if (notify && mounted) {
      setState(() {});
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

  /// Fast status checks first, then ~1.5s — fits the 60s confirmation window.
  Future<String> _resolvePlanIdForOrder(
    Map<String, dynamic> response,
    SharedPreferences prefs,
  ) async {
    final fromPrefs = prefs.getString('pendingPaymentPlanId')?.trim();
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;
    final fromStatus = (response['intentPlanId'] ?? response['planId'])?.toString().trim();
    if (fromStatus != null && fromStatus.isNotEmpty) {
      await prefs.setString('pendingPaymentPlanId', fromStatus);
      return fromStatus;
    }
    return '';
  }

  Future<void> _adaptivePaymentPollLoop(String orderId, int gen) async {
    const warmDelaysMs = <int>[0, 500, 800, 1100, 1400, 1800, 2200];
    var warmIdx = 0;
    var confirmProbeTick = 0;
    final deadline = DateTime.now().add(Duration(seconds: _kPaymentWaitSeconds));

    while (mounted && gen == _pollGen && !_paymentCompletionInProgress) {
      if (DateTime.now().isAfter(deadline)) {
        if (_pollingOrderId != null && _pollingOrderId == orderId && !_paymentCompletionInProgress) {
          _handleWaitWindowExpired();
        }
        return;
      }

      final delayMs = warmIdx < warmDelaysMs.length ? warmDelaysMs[warmIdx] : 1500;
      warmIdx++;
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      if (!mounted || gen != _pollGen || _paymentCompletionInProgress) return;

      try {
        final response = await paymentsApi.checkPaymentStatus(orderId);
        if (!mounted || gen != _pollGen || _paymentCompletionInProgress) return;
        final paymentStatus = paymentStatusFromCheckResponse(response);
        if (isPaymentCompleted(paymentStatus)) {
          final premiumMs = response['premiumUntilMs'];
          final serverActivated = response['activated'] == true;
          if (serverActivated && premiumMs is num) {
            _stopPaymentTimersOnly();
            await _markPaymentCompleted(serverPremiumUntilMs: premiumMs.toInt());
            return;
          }
          final prefs = await SharedPreferences.getInstance();
          final planId = await _resolvePlanIdForOrder(response, prefs);
          if (planId.isEmpty) {
            // Wait for intent metadata before confirm — avoids 400 spam.
            continue;
          }
          final phone = prefs.getString('pendingPaymentPhone')?.trim();
          final publicId = await UserIdentity.getOrCreatePublicId();
          final serverUntil = await PremiumRecovery.confirmPremiumOnBackend(
            orderId: orderId,
            publicId: publicId,
            planId: planId,
            phone: phone ?? '',
          );
          if (serverUntil != null) {
            _stopPaymentTimersOnly();
            await _markPaymentCompleted(serverPremiumUntilMs: serverUntil);
            return;
          }
          // Provider says paid but server has not activated yet — keep polling.
        }
        if (isPaymentTerminalFailure(paymentStatus)) {
          await _finalizeSessionFailed(_paymentFailureUserMessage(paymentStatus));
          return;
        }
        confirmProbeTick++;
        if (confirmProbeTick % 5 == 0) {
          try {
            final probe = await _probeConfirmWhilePending(orderId);
            if (!mounted || gen != _pollGen || _paymentCompletionInProgress) return;
            if (probe.kind == _ConfirmProbeKind.completed) {
              _stopPaymentTimersOnly();
              await _markPaymentCompleted(serverPremiumUntilMs: probe.premiumUntilMs);
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
          if (_notFoundStreak >= 10) {
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
    await prefs.remove('pendingPaymentProvider');
    await prefs.remove('pendingPaymentCreatedAtMs');
  }

  void _handleWaitWindowExpired() {
    if (!mounted || _pollingOrderId == null) return;
    if (_paymentCompletionInProgress) return;
    unawaited(_handleWaitWindowExpiredAsync());
  }

  /// Last chance: gateway may flip to completed right as the countdown hits zero.
  Future<void> _handleWaitWindowExpiredAsync() async {
    if (_waitExpiryHandling || _paymentCompletionInProgress || !mounted) return;
    if (_paymentUiPhase != _PaymentUiPhase.waiting) return;
    _waitExpiryHandling = true;
    try {
      final id = _pollingOrderId?.trim();
      if (id == null || id.isEmpty) {
        await _finalizeSessionTimedOut(
          detail:
              'Muda wa kusubiri umeisha bila uthibitisho. Hakikisha umeingiza PIN kwenye simu, kisha jaribu tena.',
        );
        return;
      }
      try {
        final response = await paymentsApi.checkPaymentStatus(id);
        final paymentStatus = paymentStatusFromCheckResponse(response);
        if (isPaymentCompleted(paymentStatus)) {
          final premiumMs = response['premiumUntilMs'];
          if (response['activated'] == true && premiumMs is num) {
            _stopPaymentTimersOnly();
            await _markPaymentCompleted(serverPremiumUntilMs: premiumMs.toInt());
            return;
          }
          final prefs = await SharedPreferences.getInstance();
          final planId = await _resolvePlanIdForOrder(response, prefs);
          if (planId.isEmpty) {
            await _finalizeSessionTimedOut(
              detail:
                  'Malipo yamekamilika lakini bado hatujafungua akaunti yako. Fungua programu tena baada ya dakika 1–2 au wasiliana na msaada.',
            );
            return;
          }
          final phone = prefs.getString('pendingPaymentPhone')?.trim();
          final publicId = await UserIdentity.getOrCreatePublicId();
          final serverUntil = await PremiumRecovery.confirmPremiumOnBackend(
            orderId: id,
            publicId: publicId,
            planId: planId,
            phone: phone ?? '',
          );
          if (serverUntil != null) {
            _stopPaymentTimersOnly();
            await _markPaymentCompleted(serverPremiumUntilMs: serverUntil);
            return;
          }
          // Paid at provider but premium not granted yet — keep pending prefs and retry via recovery.
          final recovered = await PremiumRecovery.recoverPendingPaymentIfAny();
          if (recovered && mounted) {
            _stopPaymentTimersOnly();
            setState(() {
              _pollingOrderId = null;
              _paymentUiPhase = _PaymentUiPhase.none;
              _sessionEndDetail = null;
            });
            _showStatus(_kPremiumSuccessTitle, _kPremiumSuccessMessage, _PayDialogTone.success);
            await widget.onPaymentSuccess?.call();
            return;
          }
          await _finalizeSessionTimedOut(
            detail:
                'Malipo yamekamilika lakini bado hatujafungua akaunti yako. Fungua programu tena baada ya dakika 1–2 au wasiliana na msaada.',
          );
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
      final recovered = await PremiumRecovery.recoverPendingPaymentIfAny();
      if (recovered && mounted) {
        _stopPaymentTimersOnly();
        setState(() {
          _pollingOrderId = null;
          _paymentUiPhase = _PaymentUiPhase.none;
          _sessionEndDetail = null;
        });
        _showStatus(_kPremiumSuccessTitle, _kPremiumSuccessMessage, _PayDialogTone.success);
        await widget.onPaymentSuccess?.call();
        return;
      }
      await _finalizeSessionTimedOut(
        detail:
            'Muda wa $_paymentWaitWindowLabel umeisha bila uthibitisho wa haraka. Ukiisha thibitisha PIN kwenye simu, fungua programu tena — malipo yanaweza kukamilika kiotomatiki.',
      );
    } finally {
      _waitExpiryHandling = false;
    }
  }

  Future<void> _finalizeSessionTimedOut({String? detail}) async {
    if (_paymentCompletionInProgress) return;
    if (_paymentUiPhase != _PaymentUiPhase.waiting) return;
    _stopPaymentTimersOnly();
    // Keep pending order prefs so [PremiumRecovery] / [_load] can finish activation after reopen.
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
    _waitExpiryHandling = false;
    _stopPaymentTimersOnly();
    unawaited(_prepareForNewPaymentAttempt());
    // Keep pending order prefs only while recovery can still finish activation.
    setState(() {
      _paymentUiPhase = _PaymentUiPhase.none;
      _pollingOrderId = null;
      _notFoundStreak = 0;
      _waitingSeconds = _kPaymentWaitSeconds;
      _sessionEndDetail = null;
      _selectedBundle = null;
      _pendingBundleLabel = null;
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

  bool _isPaymentCooldownDetail(String lower) {
    return lower.contains('limetumwa kwenye simu') ||
        lower.contains('angalia pin') ||
        lower.contains('payment_cooldown');
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
    if (_isPaymentCooldownDetail(lower)) {
      return raw.length > 20 && raw.length < 220
          ? raw
          : 'Ombi la malipo limetumwa kwenye simu yako. Angalia PIN kwenye simu, kisha subiri.';
    }
    // Per-number Sonic quota — not our post-success cooldown or API throttle.
    final isPerNumberQuota = lower.contains('majaribio mengi') ||
        lower.contains('umefanya majaribio') ||
        lower.contains('umejaribu mara nyingi') ||
        ((lower.contains('nambari') ||
                lower.contains('number') ||
                lower.contains('phone') ||
                lower.contains('msisdn')) &&
            (lower.contains('attempt') ||
                lower.contains('majaribio') ||
                lower.contains('mara nyingi') ||
                lower.contains('rate limit') ||
                lower.contains('limit reached')));
    if (isPerNumberQuota) {
      if (raw.length > 20 && raw.length < 220) return raw;
      return 'Umefanya majaribio mengi kwa nambari hii. Subiri dakika 2–5 bila kubonyeza tena, kisha jaribu.';
    }
    if (RegExp(r'too many attempts?', caseSensitive: false).hasMatch(lower) ||
        lower.contains('too many requests') ||
        lower == 'rate limited' ||
        lower.contains('huduma ina shughuli')) {
      return 'Huduma ina shughuli nyingi sasa. Subiri sekunde chache, kisha jaribu tena.';
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
    if (lower.contains('hayajatumika') ||
        lower.contains('hayajaweza kutumika') ||
        lower.contains('hayajaweza kutuma')) {
      if (raw.length > 40 && !lower.startsWith('exception')) {
        return raw;
      }
      return 'Hatukuweza kutuma ombi la malipo kwenye simu yako. Hakikisha nambari ni sahihi, una salio, na mtandao wa pesa unafanya kazi, kisha jaribu tena.';
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

  Future<_ConfirmProbeOutcome> _probeConfirmWhilePending(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final planId = prefs.getString('pendingPaymentPlanId')?.trim();
    final phone = prefs.getString('pendingPaymentPhone')?.trim();
    if (planId == null || planId.isEmpty) return _ConfirmProbeOutcome.pending();

    final publicId = await UserIdentity.getOrCreatePublicId();
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return _ConfirmProbeOutcome.pending();
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final versionHeaders = await appVersionHeaders();
    final uris = [
      Uri.parse('$origin/api/v1/public/confirm-premium'),
    ];

    http.Response? res;
    for (final uri in uris) {
      try {
        res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            ...versionHeaders,
          },
          body: jsonEncode({
            'orderId': orderId,
            'publicId': publicId,
            'planId': planId,
            'phone': phone ?? '',
          }),
        )
        .timeout(const Duration(seconds: 18));
        if (res.statusCode != 404) break;
      } catch (_) {
        continue;
      }
    }
    if (res == null) return _ConfirmProbeOutcome.pending();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (j['ok'] == true) {
          final raw = j['premiumUntilMs'];
          const skewGraceMs = 5 * 60 * 1000;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (raw is int && raw > nowMs - skewGraceMs) {
            return _ConfirmProbeOutcome.completed(premiumUntilMs: raw);
          }
          if (raw is num && raw.toInt() > nowMs - skewGraceMs) {
            return _ConfirmProbeOutcome.completed(premiumUntilMs: raw.toInt());
          }
        }
      } catch (_) {}
      return _ConfirmProbeOutcome.pending();
    }

    if (res.statusCode == 409) {
      return _ConfirmProbeOutcome.pending();
    }
    return _ConfirmProbeOutcome.pending();
  }

  /// Payment completed — unlock premium locally, then sync with server (idempotent).
  Future<void> _markPaymentCompleted({int? serverPremiumUntilMs}) async {
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

      if (phone != null && phone.isNotEmpty) {
        await UserIdentity.savePhoneNumber(phone);
      }
      final reg = await UserIdentity.registerWithBackend(phone: phone);
      final publicId = reg.publicId;

      int? serverUntilMs = serverPremiumUntilMs;
      if (serverUntilMs == null && orderId.isNotEmpty && planId != null && planId.isNotEmpty) {
        for (var attempt = 0; attempt < 8 && serverUntilMs == null; attempt++) {
          serverUntilMs = await PremiumRecovery.confirmPremiumOnBackend(
            orderId: orderId,
            publicId: publicId,
            planId: planId,
            phone: phone ?? '',
          );
          if (serverUntilMs == null) {
            final rec = await PremiumRecovery.fetchUserPremiumRecord(publicId);
            if (rec.premiumUntilMs != null) {
              final end = DateTime.fromMillisecondsSinceEpoch(rec.premiumUntilMs!);
              if (end.isAfter(DateTime.now())) {
                serverUntilMs = rec.premiumUntilMs;
              }
            }
          }
          if (serverUntilMs == null && attempt < 7) {
            await Future<void>.delayed(Duration(milliseconds: 700 + (attempt * 500)));
          }
        }
      }

      if (serverUntilMs == null && orderId.isNotEmpty) {
        final rec = await PremiumRecovery.fetchUserPremiumRecord(publicId);
        if (rec.premiumUntilMs != null) {
          final end = DateTime.fromMillisecondsSinceEpoch(rec.premiumUntilMs!);
          if (end.isAfter(DateTime.now())) {
            serverUntilMs = rec.premiumUntilMs;
          }
        }
      }

      if (serverUntilMs != null) {
        await SubscriptionStore.setPremiumUntilMs(serverUntilMs);
      }
      await SubscriptionStore.syncPremiumFromBackend(force: true);
      await SubscriptionStore.refreshNotifierFromPrefs();
      final isActive = SubscriptionStore.isPremiumActiveLocal();

      if (isActive) {
        await _clearPendingOrderPrefs();
      }

      if (mounted) {
        if (isActive) {
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
        } else if (orderId.isNotEmpty) {
          setState(() {
            _pollingOrderId = orderId;
            _paymentUiPhase = _PaymentUiPhase.waiting;
            _waitingSeconds = _kPaymentWaitSeconds;
          });
          _showStatus(
            'Inathibitisha malipo',
            'Malipo yamepokelewa. Tunafungua akaunti yako — subiri kidogo.',
            _PayDialogTone.info,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
        } else {
          _showStatus(
            'Malipo yanasubiri uthibitisho',
            'Malipo yamepokelewa lakini bado hayajathibitishwa kwenye seva. Jaribu tena baada ya dakika chache.',
            _PayDialogTone.info,
          );
        }
      }
    } finally {
      _paymentCompletionInProgress = false;
    }
  }

  void _beginSubmitProgress() {
    _submitStageTimer?.cancel();
    setState(() {
      _submitting = true;
      _submitStatus = 'Inathibitisha taarifa zako…';
    });
    var step = 0;
    _submitStageTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!mounted || !_submitting) return;
      step++;
      setState(() {
        _submitStatus = switch (step % 3) {
          0 => 'Inathibitisha taarifa zako…',
          1 => 'Inaunganisha na huduma ya malipo…',
          _ => 'Inatumia ombi la malipo…',
        };
      });
    });
  }

  void _endSubmitProgress() {
    _submitStageTimer?.cancel();
    _submitStageTimer = null;
    if (mounted) {
      setState(() {
        _submitting = false;
        _submitStatus = '';
      });
    }
  }

  Future<void> _send() async {
    if (_submitting || _paymentPollArmed || _paymentCompletionInProgress) return;

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
    if (clean.isEmpty || !_phoneValid(_phoneCtrl.text)) {
      _showStatus(
        'Nambari ya simu',
        'Andika namba ya simu ukianza na 0.',
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

    await _prepareForNewPaymentAttempt();
    _beginSubmitProgress();
    try {
      if (_userId == null || _userId!.isEmpty) {
        setState(() => _submitStatus = 'Inaandaa akaunti yako…');
        _userId = await getOrCreateUserId();
        if (_userId == null || _userId!.isEmpty) {
          _showStatus(
            'Tatizo la akaunti',
            'Hatukuweza kutambua akaunti yako. Fungua tena sehemu ya wasifu (Profile) kisha ujaribu tena.',
            _PayDialogTone.error,
          );
          return;
        }
      }

      setState(() => _submitStatus = 'Inathibitisha nambari ya simu…');
      final reg = await UserIdentity.registerWithBackend(phone: clean);
      _userId = reg.publicId;
      if (reg.premiumUntilMs != null &&
          reg.premiumUntilMs! > DateTime.now().millisecondsSinceEpoch) {
        await SubscriptionStore.setPremiumUntilMs(reg.premiumUntilMs!);
        await SubscriptionStore.refreshNotifierFromPrefs();
        if (mounted) {
          _showStatus(
            'Tayari una premium',
            'Akaunti yako ya awali imepatikana. Unaweza kutazama bila kulipa tena.',
            _PayDialogTone.success,
          );
        }
        return;
      }

      setState(() => _submitStatus = 'Inatumia ombi la malipo…');
      final result = await paymentsApi.startPayment(
        externalId: _userId!,
        bundle: plan.id,
        amount: plan.value,
        phone: clean,
        email: '$_userId@supasoka.app',
        name: _userId!,
        onAttempt: (attempt, maxAttempts) {
          if (!mounted || attempt <= 1) return;
          setState(() => _submitStatus = 'Inajaribu tena ($attempt/$maxAttempts)…');
        },
      );
      final orderId = (result['orderId']?.toString() ?? '').trim();
      final serverMsg = (result['message']?.toString() ?? '').trim();
      final provider = (result['provider']?.toString() ?? '').trim().toLowerCase();

      if (orderId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pendingPaymentOrderId', orderId);
        await prefs.setString('pendingPaymentPlanId', plan.id);
        await prefs.setString('pendingPaymentPhone', TanzaniaPhone.normalize(clean) ?? clean);
        await PremiumRecovery.markPendingPaymentCreatedNow();
        if (provider.isNotEmpty) {
          await prefs.setString('pendingPaymentProvider', provider);
        }
        if (!mounted) return;
        _submitStageTimer?.cancel();
        setState(() {
          _submitStatus = 'Ombi limetumwa! Angalia simu yako…';
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        setState(() {
          _pollingOrderId = orderId;
          _notFoundStreak = 0;
          _pendingBundleLabel = plan.name;
          _paymentUiPhase = _PaymentUiPhase.waiting;
          _submitting = false;
          _submitStatus = '';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
      } else {
        final msg = serverMsg.isNotEmpty
            ? serverMsg
            : 'Ombi la malipo la Tsh.${plan.price} (${plan.name}) limepokelewa kwa $clean. Ikiwa hutooni ujumbe kwenye simu, jaribu tena au wasiliana na msaada.';
        _showStatus('Tumepokea ombi', msg, _PayDialogTone.info);
      }
    } catch (e) {
      final detail = _mapPaymentError(e);
      final isCooldown = _isPaymentCooldownDetail(detail.toLowerCase());
      _showStatus(
        isCooldown ? 'Angalia simu yako' : 'Malipo hayajakamilika',
        detail,
        isCooldown ? _PayDialogTone.info : _PayDialogTone.error,
      );
    } finally {
      if (_submitting) _endSubmitProgress();
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
    final showPayCta = _phoneOk && _selectedBundle != null;
    final payEnabled = showPayCta && !_submitting;

    return Material(
      color: _scaffold,
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.desktopLayout
                ? _DesktopPayAmbient(accent: ac)
                : _PayAmbientLayer(accent: ac),
          ),
          SafeArea(
            top: true,
            bottom: false,
            child: widget.desktopLayout
                ? _buildDesktopBody(
                    ac: ac,
                    content: content,
                    bundles: bundles,
                    showPayCta: showPayCta,
                    payEnabled: payEnabled,
                  )
                : RefreshIndicator(
                    color: _accentCta,
                    onRefresh: () => context.read<ContentStore>().refresh(),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(22, 8, 22, bottom),
                      child: _buildMobileCheckoutColumn(
                        ac: ac,
                        content: content,
                        bundles: bundles,
                        showPayCta: showPayCta,
                        payEnabled: payEnabled,
                      ),
                    ),
                  ),
          ),
          ..._buildPaymentOverlays(),
        ],
      ),
    );
  }

  List<Widget> _buildPaymentOverlays() {
    return [
          if (_submitting && _submitStatus.isNotEmpty)
            Positioned.fill(
              child: _PaymentProcessingOverlay(status: _submitStatus),
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
                remainingSeconds: _waitingSeconds.clamp(0, _kPaymentWaitSeconds),
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
                      constraints: BoxConstraints(maxWidth: widget.desktopLayout ? 440 : 340),
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            switch (_statusTone) {
                              _PayDialogTone.success => Icons.check_circle_rounded,
                              _PayDialogTone.error => Icons.error_outline_rounded,
                              _PayDialogTone.info => Icons.info_outline_rounded,
                            },
                            size: 44,
                            color: switch (_statusTone) {
                              _PayDialogTone.success => const Color(0xFF4ADE80),
                              _PayDialogTone.error => const Color(0xFFF87171),
                              _PayDialogTone.info => _accentBlue,
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _statusTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _statusMsg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => setState(() => _statusOpen = false),
                              child: const Text('Sawa'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ];
  }

  Widget _buildDesktopBody({
    required Color ac,
    required ContentStore content,
    required List<_Bundle> bundles,
    required bool showPayCta,
    required bool payEnabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopPayTopBar(
          onClose: widget.onClose,
          contextTitle: widget.contextTitle,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final checkout = _DesktopCheckoutCard(
                ac: ac,
                content: content,
                bundles: bundles,
                showPayCta: showPayCta,
                payEnabled: payEnabled,
                horizontalPlans: wide,
                phoneOk: _phoneOk,
                phoneCtrl: _phoneCtrl,
                selectedBundle: _selectedBundle,
                submitting: _submitting,
                onPhoneChanged: (value) {
                  final normalized = TanzaniaPhone.normalize(value);
                  if (normalized != null && normalized != value) {
                    _phoneCtrl.value = TextEditingValue(
                      text: normalized,
                      selection: TextSelection.collapsed(offset: normalized.length),
                    );
                  }
                  setState(() {
                    if (!_phoneOk) _selectedBundle = null;
                  });
                },
                onSelectBundle: (id) => setState(() => _selectedBundle = id),
                onPay: payEnabled ? _send : null,
                onRefreshPlans: () => context.read<ContentStore>().refresh(),
              );

              if (!wide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DesktopPayHero(
                        accent: ac,
                        contextTitle: widget.contextTitle,
                        autoPlayGuide: widget.autoPlayGuide,
                        audioAssetPackage: widget.audioAssetPackage,
                      ),
                      const SizedBox(height: 20),
                      checkout,
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(32, 12, 32, 28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 42,
                      child: SingleChildScrollView(
                        child: _DesktopPayHero(
                          accent: ac,
                          contextTitle: widget.contextTitle,
                          autoPlayGuide: widget.autoPlayGuide,
                          audioAssetPackage: widget.audioAssetPackage,
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(flex: 58, child: SingleChildScrollView(child: checkout)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCheckoutColumn({
    required Color ac,
    required ContentStore content,
    required List<_Bundle> bundles,
    required bool showPayCta,
    required bool payEnabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Reveal(
          controller: _entryCtrlSafe,
          delay: 0.00,
          child: AudioGuideCard(
            assetPath: 'audio/fungua_zote_guide.mp3',
            title: 'Jinsi ya kufungua channel zote',
            subtitle: 'Mwongozo mfupi wa hatua zote',
            autoPlay: widget.autoPlayGuide,
          ),
        ),
        const SizedBox(height: 18),
        _Reveal(
          controller: _entryCtrlSafe,
          delay: 0.04,
          child: _PayPremiumHero(accent: ac),
        ),
        const SizedBox(height: 26),
        _Reveal(
          controller: _entryCtrlSafe,
          delay: 0.16,
          child: _PayGlassPanel(child: _buildPhoneStep(ac)),
        ),
        if (_phoneOk) ...[
          const SizedBox(height: 18),
          _Reveal(
            controller: _entryCtrlSafe,
            delay: 0.26,
            child: _PayGlassPanel(
              child: _buildPlansStep(ac: ac, content: content, bundles: bundles),
            ),
          ),
        ],
        _buildAnimatedPayCta(showPayCta: showPayCta, payEnabled: payEnabled),
      ],
    );
  }

  Widget _buildPhoneStep(Color ac) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PayStepTitle(number: '01', title: 'Nambari ya simu', accent: ac),
        const SizedBox(height: 6),
        const Text(
          'Andika namba ya simu ukianza na 0.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: _payMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        _buildPhoneField(ac),
        const SizedBox(height: 10),
        _buildWalletHint(),
      ],
    );
  }

  Widget _buildPlansStep({
    required Color ac,
    required ContentStore content,
    required List<_Bundle> bundles,
    bool horizontal = false,
  }) {
    return Column(
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
        else if (horizontal)
          LayoutBuilder(
            builder: (context, c) {
              final cols = bundles.length.clamp(1, 3);
              final gap = 12.0;
              final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final b in bundles)
                    SizedBox(
                      width: itemW,
                      child: _DesktopPlanCard(
                        bundle: b,
                        accent: ac,
                        selected: _selectedBundle == b.id,
                        onTap: () => setState(() => _selectedBundle = b.id),
                      ),
                    ),
                ],
              );
            },
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
    );
  }

  Widget _buildPhoneField(Color ac) {
    return AnimatedContainer(
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
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(13),
              ],
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.desktopLayout ? 22 : 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0712345678',
                hintStyle: TextStyle(
                  color: _payMuted.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w500,
                ),
                counterText: '',
                contentPadding: EdgeInsets.fromLTRB(20, widget.desktopLayout ? 22 : 20, 12, widget.desktopLayout ? 22 : 20),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.phone_iphone_rounded,
                    color: _phoneOk ? _accentCta : _payMuted,
                    size: widget.desktopLayout ? 26 : 22,
                  ),
                ),
              ),
              onChanged: (value) {
                final normalized = TanzaniaPhone.normalize(value);
                if (normalized != null && normalized != value) {
                  _phoneCtrl.value = TextEditingValue(
                    text: normalized,
                    selection: TextSelection.collapsed(offset: normalized.length),
                  );
                }
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
                child: const Icon(Icons.check_rounded, color: _accentCta, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWalletHint() {
    if (!_phoneOk) return const SizedBox.shrink();

    return Builder(
      builder: (_) {
        final wallet = TanzaniaPhone.walletLabel(_phoneCtrl.text);
        final supported = TanzaniaPhone.supportsPushUssd(_phoneCtrl.text);
        if (wallet == null) return const SizedBox.shrink();

        return Text(
          supported
              ? 'Ombi litatumwa kwa $wallet.'
              : 'Nambari hii ($wallet) huenda isipokee Push USSD.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: supported ? _accentCta.withValues(alpha: 0.95) : const Color(0xFFFFB74D),
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }

  Widget _buildAnimatedPayCta({required bool showPayCta, required bool payEnabled}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: showPayCta
          ? Padding(
              key: const ValueKey('pay-button'),
              padding: const EdgeInsets.only(top: 16),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.98, end: 1.0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                child: _PremiumPayCta(
                  submitting: _submitting,
                  onPressed: payEnabled ? _send : null,
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('no-pay-button')),
    );
  }
}

/// Full-screen feedback while the payment request is being created (no silent gap).
class _PaymentProcessingOverlay extends StatelessWidget {
  const _PaymentProcessingOverlay({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF151B2E), Color(0xFF0A0F18)],
                ),
                border: Border.all(color: const Color(0x28FFFFFF)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    blurRadius: 32,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.2,
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Text(
                      status,
                      key: ValueKey<String>(status),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: Color(0x18FFFFFF),
                      color: Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Usifunge programu — hatua hii inachukua sekunde chache',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.62),
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

/// Full-width premium CTA — gradient, glow, clear hierarchy (Fungua zote tab only; no WhatsApp FAB here).
class _PremiumPayCta extends StatelessWidget {
  const _PremiumPayCta({required this.submitting, required this.onPressed});

  final bool submitting;
  final VoidCallback? onPressed;

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
    required this.remainingSeconds,
    required this.maxWaitSeconds,
  });

  final int remainingSeconds;
  final int maxWaitSeconds;

  @override
  Widget build(BuildContext context) {
    final max = maxWaitSeconds <= 0 ? 1 : maxWaitSeconds;
    final elapsed = (max - remainingSeconds).clamp(0, max);
    final progress = (elapsed / max).clamp(0.0, 1.0);
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
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF4ADE80),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Subiri uthibitisho kwenye simu',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Thibitisha PIN kwenye simu yako',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress > 0.01 ? progress : null,
                  minHeight: 5,
                  backgroundColor: Colors.white10,
                  color: const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                remainingSeconds <= 0
                    ? 'Tunahakiki malipo mara kwa mara…'
                    : 'Baki sekunde $remainingSeconds · thibitisha PIN kwenye simu',
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

class _DesktopPayAmbient extends StatelessWidget {
  const _DesktopPayAmbient({required this.accent});

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
              colors: [Color(0xFF030508), Color(0xFF0A1018), Color(0xFF050A12)],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -80,
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [accent.withValues(alpha: 0.18), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          right: -60,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [const Color(0xFF22C55E).withValues(alpha: 0.12), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopPayTopBar extends StatelessWidget {
  const _DesktopPayTopBar({this.onClose, this.contextTitle});

  final VoidCallback? onClose;
  final String? contextTitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
      child: Row(
        children: [
          if (onClose != null)
            IconButton(
              tooltip: 'Rudi',
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            )
          else
            const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.live_tv_rounded, size: 16, color: _accentCta),
                SizedBox(width: 8),
                Text(
                  'SupaTV Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          if (contextTitle != null && contextTitle!.trim().isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                contextTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

class _DesktopPayHero extends StatelessWidget {
  const _DesktopPayHero({
    required this.accent,
    this.contextTitle,
    this.autoPlayGuide = false,
    this.audioAssetPackage,
  });

  final Color accent;
  final String? contextTitle;
  final bool autoPlayGuide;
  final String? audioAssetPackage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.22),
                const Color(0xFF22C55E).withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: [accent, const Color(0xFF22C55E)]),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contextTitle != null && contextTitle!.trim().isNotEmpty
                          ? 'Fungua ${contextTitle!.trim()}'
                          : 'Fungua channel zote',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Malipo salama kupitia M-Pesa, Tigo, Airtel na Halopesa.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final item in const [
          (Icons.sports_soccer_rounded, 'Vituo vyote vya michezo na sinema'),
          (Icons.hd_rounded, 'Ubora wa video hadi 1080p kwenye SupaTV'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.$1, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      item.$2,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        AudioGuideCard(
          assetPath: 'audio/fungua_zote_guide.mp3',
          assetPackage: audioAssetPackage,
          title: 'Jinsi ya kufungua channel zote',
          subtitle: 'Sikiliza mwongozo wa hatua 3',
          autoPlay: autoPlayGuide,
        ),
      ],
    );
  }
}

class _DesktopCheckoutCard extends StatelessWidget {
  const _DesktopCheckoutCard({
    required this.ac,
    required this.content,
    required this.bundles,
    required this.showPayCta,
    required this.payEnabled,
    required this.horizontalPlans,
    required this.phoneOk,
    required this.phoneCtrl,
    required this.selectedBundle,
    required this.submitting,
    required this.onPhoneChanged,
    required this.onSelectBundle,
    required this.onPay,
    required this.onRefreshPlans,
  });

  final Color ac;
  final ContentStore content;
  final List<_Bundle> bundles;
  final bool showPayCta;
  final bool payEnabled;
  final bool horizontalPlans;
  final bool phoneOk;
  final TextEditingController phoneCtrl;
  final String? selectedBundle;
  final bool submitting;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onSelectBundle;
  final VoidCallback? onPay;
  final Future<void> Function() onRefreshPlans;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
            children: [
              _DesktopStepChip(number: '1', active: true, accent: ac),
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: phoneOk ? ac.withValues(alpha: 0.45) : Colors.white12,
                ),
              ),
              _DesktopStepChip(number: '2', active: phoneOk, accent: ac),
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: showPayCta ? ac.withValues(alpha: 0.45) : Colors.white12,
                ),
              ),
              _DesktopStepChip(number: '3', active: showPayCta, accent: ac),
            ],
          ),
          const SizedBox(height: 24),
          _PayStepTitle(number: '01', title: 'Nambari ya simu', accent: ac),
          const SizedBox(height: 8),
          const Text(
            'Andika namba ya simu ukianza na 0.',
            style: TextStyle(fontSize: 13.5, color: _payMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: _paySurface,
              border: Border.all(
                color: phoneOk ? _accentCta.withValues(alpha: 0.55) : _payLine,
                width: phoneOk ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(13),
                    ],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '0712345678',
                      hintStyle: TextStyle(color: _payMuted.withValues(alpha: 0.65)),
                      counterText: '',
                      contentPadding: const EdgeInsets.fromLTRB(20, 22, 12, 22),
                      prefixIcon: Icon(
                        Icons.phone_iphone_rounded,
                        color: phoneOk ? _accentCta : _payMuted,
                        size: 26,
                      ),
                    ),
                    onChanged: onPhoneChanged,
                  ),
                ),
                if (phoneOk)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Icon(Icons.check_circle_rounded, color: _accentCta, size: 24),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (_) {
              if (!phoneOk) return const SizedBox.shrink();

              final wallet = TanzaniaPhone.walletLabel(phoneCtrl.text);
              final supported = TanzaniaPhone.supportsPushUssd(phoneCtrl.text);
              if (wallet == null) return const SizedBox.shrink();

              return Text(
                supported
                    ? 'Ombi litatumwa kwa $wallet.'
                    : 'Nambari hii ($wallet) huenda isipokee Push USSD.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: supported ? _accentCta.withValues(alpha: 0.95) : const Color(0xFFFFB74D),
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
          if (phoneOk) ...[
            const SizedBox(height: 24),
            _PayStepTitle(number: '02', title: 'Chagua muda', accent: ac),
            const SizedBox(height: 14),
            if (bundles.isEmpty)
              _MalipoPlansEmptyPanel(
                accent: ac,
                refreshing: content.refreshing,
                onRefresh: onRefreshPlans,
              )
            else if (horizontalPlans)
              LayoutBuilder(
                builder: (context, c) {
                  final cols = bundles.length <= 3 ? bundles.length.clamp(1, 3) : 2;
                  final gap = 12.0;
                  final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final b in bundles)
                        SizedBox(
                          width: itemW,
                          child: _DesktopPlanCard(
                            bundle: b,
                            accent: ac,
                            selected: selectedBundle == b.id,
                            onTap: () => onSelectBundle(b.id),
                          ),
                        ),
                    ],
                  );
                },
              )
            else
              ...bundles.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PriceOptionTile(
                    bundle: b,
                    accent: ac,
                    selected: selectedBundle == b.id,
                    onTap: () => onSelectBundle(b.id),
                  ),
                ),
              ),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: showPayCta
                ? Padding(
                    key: const ValueKey('desktop-pay'),
                    padding: const EdgeInsets.only(top: 22),
                    child: _PremiumPayCta(submitting: submitting, onPressed: onPay),
                  )
                : const SizedBox.shrink(key: ValueKey('desktop-no-pay')),
          ),
        ],
        ),
      ),
    );
  }
}

class _DesktopStepChip extends StatelessWidget {
  const _DesktopStepChip({required this.number, required this.active, required this.accent});

  final String number;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: active ? accent.withValues(alpha: 0.7) : Colors.white24),
      ),
      child: Text(
        number,
        style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _DesktopPlanCard extends StatelessWidget {
  const _DesktopPlanCard({
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
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected ? accent.withValues(alpha: 0.12) : _paySurface,
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.65) : _payLine,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bundle.badge.trim().isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: bundle.accent1.withValues(alpha: 0.16),
                  ),
                  child: Text(
                    bundle.badge.trim(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: bundle.accent1,
                    ),
                  ),
                ),
              Text(
                bundle.priceLine,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${bundle.name} · ${bundle.duration}',
                style: const TextStyle(color: _payMuted, fontSize: 12, height: 1.3),
              ),
              if (selected) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Imechaguliwa',
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.95),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}