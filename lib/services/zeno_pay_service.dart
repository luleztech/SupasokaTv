import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/config/zeno_config.dart';
import 'package:uuid/uuid.dart';

/// ZenoPay Mobile Money Tanzania — matches official JSON:
/// POST `/api/payments/mobile_money_tanzania`, GET `/api/payments/order-status?order_id=…`
///
/// **[buyer_phone]** must be national `07XXXXXXXX` / `06XXXXXXXX` (Vodacom, Airtel, Tigo, Halotel, Yas, etc.).
/// Use [TanzaniaPhone.normalize] before [createOrder].
///
/// **Flutter Web:** browsers may block direct calls to `zenoapi.com` (CORS). Set  
/// `--dart-define=ZENO_API_BASE=https://your-backend.example`  
/// so your server proxies the same paths to ZenoPay.
class ZenoPayService {
  ZenoPayService._();

  static const _headersBase = {'Content-Type': 'application/json; charset=utf-8'};
  static const _uuid = Uuid();

  static const _createAttempts = 3;
  static const _statusAttempts = 2;
  static const _createTimeout = Duration(seconds: 40);
  static const _statusTimeout = Duration(seconds: 22);

  static bool get _useBackendProxy => kZenoApiKey.trim().isEmpty;

  static List<Uri> _backendCreateUris() {
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    return <Uri>[
      Uri.parse('$origin/api/v1/public/zeno/create-order'),
      // Backward-compat fallbacks for older backend deployments.
      Uri.parse('$origin/api/v1/public/create-order'),
      Uri.parse('$origin/api/v1/public/payments/mobile_money_tanzania'),
    ];
  }

  static List<Uri> _backendStatusUris(String orderId) {
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    return <Uri>[
      Uri.parse('$origin/api/v1/public/zeno/order-status').replace(
        queryParameters: {'order_id': orderId},
      ),
      // Backward-compat fallbacks for older backend deployments.
      Uri.parse('$origin/api/v1/public/order-status').replace(
        queryParameters: {'order_id': orderId},
      ),
      Uri.parse('$origin/api/v1/public/payments/order-status').replace(
        queryParameters: {'order_id': orderId},
      ),
    ];
  }

  /// Pull digits from admin `amount` display string → integer TZS.
  static int? parseAmountTzs(String amountDisplay) {
    final digits = amountDisplay.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  static Map<String, String> _authHeaders() => {
        ..._headersBase,
        'Accept': 'application/json',
        if (!_useBackendProxy) 'x-api-key': kZenoApiKey,
      };

  static bool _isTransientHttp(int code) =>
      code == 408 || code == 429 || code == 502 || code == 503 || code == 504;

  static Future<void> _backoff(int attempt) async {
    final ms = 350 * (1 << attempt);
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  static void _logDebug(String msg) {
    assert(() {
      if (kDebugMode) debugPrint('ZenoPay: $msg');
      return true;
    }());
  }

  static bool _retryableNetworkError(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('connection') ||
        s.contains('failed host lookup') ||
        s.contains('network') ||
        s.contains('clientexception');
  }

  static bool _resultCodeAcceptsData(String? rc) {
    if (rc == null || rc.trim().isEmpty) return true;
    final v = rc.trim();
    return v == '000' || v == '0' || v == '200' || v == '201';
  }

  static bool _looksLikePendingLookupFailure(String msg) {
    final s = msg.toLowerCase();
    return s.contains('not found') ||
        s.contains('no order') ||
        s.contains('pending') ||
        s.contains('processing') ||
        s.contains('in progress') ||
        s.contains('haijapatikana') ||
        s.contains('haikuweza kupata');
  }

  static ZenoCreateResult _parseCreateResponse(http.Response res, String requestedOrderId) {
    final text = utf8.decode(res.bodyBytes);
    Map<String, dynamic>? j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      if (_isTransientHttp(res.statusCode)) {
        return ZenoCreateResult.transient('HTTP ${res.statusCode}');
      }
      return ZenoCreateResult.failure('Jibu la seva halisomeki (${res.statusCode}).');
    }

    // Our backend `notFound` middleware returns `{ ok: false, error: { message, code } }`.
    // When the app is pointing at an older backend deployment that doesn't include Zeno proxy routes,
    // we want a clear user-facing message instead of raw "HTTP 404".
    if (j['ok'] == false) {
      final err = j['error'];
      String? code;
      String? message;
      if (err is Map) {
        final em = err['message'];
        final ec = err['code'];
        if (em != null) message = em.toString();
        if (ec != null) code = ec.toString();
      }
      if (res.statusCode == 404 || code == 'NOT_FOUND') {
        return ZenoCreateResult.failure(
          'Huduma ya malipo haipatikani kwa sasa. Tafadhali jaribu tena baada ya muda mfupi.',
        );
      }
      if (message != null && message.trim().isNotEmpty) {
        return ZenoCreateResult.failure(message.trim());
      }
    }

    final status = j['status']?.toString().toLowerCase();
    final msg = j['message']?.toString();

    if (status == 'error') {
      return ZenoCreateResult.failure(msg?.isNotEmpty == true ? msg! : 'Ombi halijakubaliwa.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (_isTransientHttp(res.statusCode)) {
        return ZenoCreateResult.transient('HTTP ${res.statusCode}');
      }
      // Prefer any backend-provided message; otherwise, keep a generic failure string.
      return ZenoCreateResult.failure(
        msg?.isNotEmpty == true ? msg! : 'Hitilafu ya malipo (HTTP ${res.statusCode}).',
      );
    }

    final code = j['resultcode']?.toString();
    final codeOk = code == '000' || code == '0';
    final success = codeOk || status == 'success';

    if (!success) {
      return ZenoCreateResult.failure(msg ?? 'Ombi halijakubaliwa (${code ?? '—'}).');
    }

    final oid = j['order_id']?.toString();
    return ZenoCreateResult.ok(
      pollOrderId: (oid != null && oid.isNotEmpty) ? oid : requestedOrderId,
      message: msg,
    );
  }

  static bool _isRouteMissingResponse(http.Response res) {
    if (res.statusCode != 404) return false;
    try {
      final text = utf8.decode(res.bodyBytes);
      final j = jsonDecode(text);
      if (j is Map) {
        final code = j['error'] is Map ? (j['error'] as Map)['code']?.toString() : null;
        if (code == 'NOT_FOUND') return true;
      }
    } catch (_) {
      // ignore parse issues; 404 still likely indicates missing route.
    }
    return true;
  }

  /// Zeno doc: `07XXXXXXXX` Tanzanian mobile (all networks using national format).
  static bool isValidZenoBuyerPhone(String national0xx) =>
      RegExp(r'^0[1-9]\d{8}$').hasMatch(national0xx.trim());

  /// Starts USSD push. Retries on transient network / 5xx. Returns [order_id] to poll.
  static Future<ZenoCreateResult> createOrder({
    required String requestedOrderId,
    required String buyerPhoneLocal0xx,
    required int amountTzs,
    required String buyerName,
    String buyerEmail = 'mteja@supasoka.app',
    Map<String, String>? metadata,
  }) async {
    if (amountTzs < 1) {
      return ZenoCreateResult.failure('Kiasi si halali.');
    }
    if (!isValidZenoBuyerPhone(buyerPhoneLocal0xx)) {
      return ZenoCreateResult.failure(
        'Nambari lazima iwe ya Tanzania: 07XXXXXXXX au 06XXXXXXXX (mitandao yote).',
      );
    }

    final body = <String, dynamic>{
      'order_id': requestedOrderId,
      'buyer_email': buyerEmail.trim().isNotEmpty ? buyerEmail.trim() : 'mteja@supasoka.app',
      'buyer_name': buyerName.trim().isNotEmpty ? buyerName.trim() : 'Mteja',
      'buyer_phone': buyerPhoneLocal0xx.trim(),
      'amount': amountTzs,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };
    if (kZenoWebhookUrl.isNotEmpty) {
      body['webhook_url'] = kZenoWebhookUrl.trim();
    }

    Object? transientErr;

    for (var attempt = 0; attempt < _createAttempts; attempt++) {
      try {
        if (attempt > 0) _logDebug('createOrder retry #$attempt');

        ZenoCreateResult parsed;
        if (_useBackendProxy) {
          parsed = ZenoCreateResult.failure('Huduma ya malipo haipatikani kwa sasa.');
          final uris = _backendCreateUris();
          for (var i = 0; i < uris.length; i++) {
            final uri = uris[i];
            final res = await http
                .post(
                  uri,
                  headers: _authHeaders(),
                  body: jsonEncode(body),
                )
                .timeout(_createTimeout);
            parsed = _parseCreateResponse(res, requestedOrderId);
            final routeMissing = _isRouteMissingResponse(res);
            if (routeMissing && i < uris.length - 1) {
              _logDebug('createOrder fallback route: ${uri.path} (404)');
              continue;
            }
            break;
          }
        } else {
          final res = await http
              .post(
                Uri.parse(kZenoCreateUrl),
                headers: _authHeaders(),
                body: jsonEncode(body),
              )
              .timeout(_createTimeout);
          parsed = _parseCreateResponse(res, requestedOrderId);
        }

        final lastAttempt = attempt >= _createAttempts - 1;
        if (!parsed.isTransientFailure || lastAttempt) {
          return parsed.asFinalResult();
        }
        transientErr = parsed.errorMessage ?? 'Mtandao ume kata';
      } on TimeoutException catch (e) {
        transientErr = e;
      } catch (e) {
        final lastAttempt = attempt >= _createAttempts - 1;
        if (!_retryableNetworkError(e) || lastAttempt) {
          return ZenoCreateResult.failure(e.toString());
        }
        transientErr = e;
      }
      await _backoff(attempt);
    }

    return ZenoCreateResult.failure(
      transientErr?.toString() ?? 'Haikuweza kuunganisha na ZenoPay. Jaribu tena.',
    );
  }

  static Future<ZenoStatusResult> fetchOrderStatus(String orderId) async {
    Object? lastErr;

    for (var attempt = 0; attempt < _statusAttempts; attempt++) {
      try {
        if (attempt > 0) await _backoff(attempt - 1);

        http.Response? activeRes;
        if (_useBackendProxy) {
          final uris = _backendStatusUris(orderId);
          for (var i = 0; i < uris.length; i++) {
            final uri = uris[i];
            final res = await http
                .get(
                  uri,
                  headers: _authHeaders(),
                )
                .timeout(_statusTimeout);
            activeRes = res;
            if (_isRouteMissingResponse(res) && i < uris.length - 1) {
              _logDebug('orderStatus fallback route: ${uri.path} (404)');
              continue;
            }
            break;
          }
        } else {
          activeRes = await http
              .get(
                Uri.parse(zenoOrderStatusUrl(orderId)),
                headers: _authHeaders(),
              )
              .timeout(_statusTimeout);
        }
        final res = activeRes!;

        final text = utf8.decode(res.bodyBytes);
        Map<String, dynamic> j;
        try {
          j = jsonDecode(text) as Map<String, dynamic>;
        } catch (_) {
          lastErr = 'Jibu la hali halisomeki';
          continue;
        }

        final rc = j['resultcode']?.toString();
        final rcAcceptsData = _resultCodeAcceptsData(rc);

        final list = j['data'];
        if (list is! List || list.isEmpty) {
          if (!rcAcceptsData) {
            final msg = j['message']?.toString() ?? 'Haikuweza kupata hali ya malipo';
            if (_looksLikePendingLookupFailure(msg)) {
              return ZenoStatusResult.pending('PENDING');
            }
            return ZenoStatusResult.error(msg);
          }
          return ZenoStatusResult.pending(null);
        }
        final row = Map<String, dynamic>.from(list.first as Map);
        final rawPs = row['payment_status'] ??
            row['PaymentStatus'] ??
            row['paymentStatus'] ??
            row['status'] ??
            row['order_status'] ??
            row['OrderStatus'] ??
            row['transaction_status'] ??
            row['TransactionStatus'];
        final ps = rawPs?.toString().trim().toUpperCase() ?? '';
        return ZenoStatusResult(paymentStatus: ps.isEmpty ? null : ps, raw: row);
      } on TimeoutException catch (e) {
        lastErr = e;
      } catch (e) {
        lastErr = e;
      }
    }

    return ZenoStatusResult.error(lastErr?.toString() ?? 'Hitilafu ya mtandao');
  }

  /// Poll until COMPLETED — short early intervals, then ~3s (faster than fixed 3s).
  static Future<ZenoPollOutcome> waitForCompleted(
    String orderId, {
    Duration timeout = const Duration(minutes: 5),
    bool Function()? cancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
    const delays = <Duration>[
      Duration(milliseconds: 700),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 1800),
      Duration(milliseconds: 2200),
      Duration(milliseconds: 2800),
      Duration(milliseconds: 3200),
    ];
    var i = 0;

    while (DateTime.now().isBefore(deadline)) {
      if (cancelled != null && cancelled()) {
        return ZenoPollOutcome.cancelled();
      }

      final st = await fetchOrderStatus(orderId);
      if (st.errorMessage != null) {
        return ZenoPollOutcome.error(st.errorMessage!);
      }

      final ps = st.paymentStatus ?? '';
      if (ps == 'COMPLETED') {
        return ZenoPollOutcome.completed();
      }
      if (ps == 'FAILED' ||
          ps == 'CANCELLED' ||
          ps == 'CANCELED' ||
          ps == 'REJECTED' ||
          ps == 'EXPIRED') {
        return ZenoPollOutcome.failed(ps);
      }

      final wait = i < delays.length ? delays[i] : const Duration(seconds: 3);
      i++;
      await Future<void>.delayed(wait);
    }
    return ZenoPollOutcome.timeout();
  }

  static String newOrderId() => _uuid.v4();
}

class ZenoCreateResult {
  ZenoCreateResult._({
    this.pollOrderId,
    this.message,
    this.errorMessage,
    bool transientFailure = false,
  }) : _transientFailure = transientFailure;

  factory ZenoCreateResult.ok({required String pollOrderId, String? message}) =>
      ZenoCreateResult._(pollOrderId: pollOrderId, message: message);

  factory ZenoCreateResult.failure(String msg) => ZenoCreateResult._(errorMessage: msg);

  factory ZenoCreateResult.transient(String reason) =>
      ZenoCreateResult._(errorMessage: reason, transientFailure: true);

  final String? pollOrderId;
  final String? message;
  final String? errorMessage;
  final bool _transientFailure;

  bool get isSuccess => errorMessage == null && pollOrderId != null;
  bool get isTransientFailure => _transientFailure;

  /// Success or non-retryable failure; turns last transient into a user-facing failure.
  ZenoCreateResult asFinalResult() {
    if (isSuccess) return this;
    if (_transientFailure) {
      return ZenoCreateResult.failure(errorMessage ?? 'Jaribu tena baada ya muda mfupi.');
    }
    return this;
  }
}

class ZenoStatusResult {
  ZenoStatusResult({required this.paymentStatus, this.raw, this.errorMessage});

  factory ZenoStatusResult.pending(String? paymentStatus) =>
      ZenoStatusResult(paymentStatus: paymentStatus);

  factory ZenoStatusResult.error(String msg) =>
      ZenoStatusResult(paymentStatus: null, errorMessage: msg);

  final String? paymentStatus;
  final Map<String, dynamic>? raw;
  final String? errorMessage;
}

class ZenoPollOutcome {
  ZenoPollOutcome._(this.kind, {this.detail});

  factory ZenoPollOutcome.completed() => ZenoPollOutcome._(ZenoPollKind.completed);

  factory ZenoPollOutcome.failed(String status) => ZenoPollOutcome._(ZenoPollKind.failed, detail: status);

  factory ZenoPollOutcome.timeout() => ZenoPollOutcome._(ZenoPollKind.timeout);

  factory ZenoPollOutcome.cancelled() => ZenoPollOutcome._(ZenoPollKind.cancelled);

  factory ZenoPollOutcome.error(String msg) => ZenoPollOutcome._(ZenoPollKind.error, detail: msg);

  final ZenoPollKind kind;
  final String? detail;

  bool get isCompleted => kind == ZenoPollKind.completed;
}

enum ZenoPollKind { completed, failed, timeout, cancelled, error }
