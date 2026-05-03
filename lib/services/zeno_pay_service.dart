import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supasoka/config/zeno_config.dart';
import 'package:uuid/uuid.dart';

/// Tanzania ZenoPay USSD push + order status (no international rails — TZ MSISDN + zenoapi.com).
class ZenoPayService {
  ZenoPayService._();

  static const _headersBase = {'Content-Type': 'application/json; charset=utf-8'};
  static const _uuid = Uuid();

  /// Pull digits from admin `amount` display string → integer TZS.
  static int? parseAmountTzs(String amountDisplay) {
    final digits = amountDisplay.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  static Map<String, String> _authHeaders() => {
        ..._headersBase,
        'x-api-key': kZenoApiKey,
      };

  /// Starts USSD push. Returns server [orderId] to poll (may differ from [requestedOrderId]).
  static Future<ZenoCreateResult> createOrder({
    required String requestedOrderId,
    required String buyerPhoneLocal0xx,
    required int amountTzs,
    required String buyerName,
    String buyerEmail = 'mteja@supasoka.app',
    Map<String, String>? metadata,
  }) async {
    if (kZenoApiKey.isEmpty) {
      return ZenoCreateResult.failure('ZENO_API_KEY haijawekwa (tumia dart-define).');
    }
    if (amountTzs < 1) {
      return ZenoCreateResult.failure('Kiasi si halali.');
    }

    final body = <String, dynamic>{
      'order_id': requestedOrderId,
      'buyer_email': buyerEmail,
      'buyer_name': buyerName,
      'buyer_phone': buyerPhoneLocal0xx,
      'amount': amountTzs,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };
    if (kZenoWebhookUrl.isNotEmpty) {
      body['webhook_url'] = kZenoWebhookUrl;
    }

    try {
      final res = await http
          .post(
            Uri.parse(kZenoCreateUrl),
            headers: _authHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));

      final text = utf8.decode(res.bodyBytes);
      Map<String, dynamic> j;
      try {
        j = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return ZenoCreateResult.failure('Jibu la seva halisomeki: ${res.statusCode}');
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = j['message']?.toString() ?? 'HTTP ${res.statusCode}';
        return ZenoCreateResult.failure(msg.isNotEmpty ? msg : 'Hitilafu ${res.statusCode}');
      }

      final code = j['resultcode']?.toString();
      final ok = code == '000' || code == '0';
      if (!ok) {
        final msg = j['message']?.toString() ?? 'Ombi halijakubaliwa';
        return ZenoCreateResult.failure(msg);
      }

      final oid = j['order_id']?.toString();
      return ZenoCreateResult.ok(
        pollOrderId: (oid != null && oid.isNotEmpty) ? oid : requestedOrderId,
        message: j['message']?.toString(),
      );
    } on TimeoutException {
      return ZenoCreateResult.failure('Muda wa kuunganisha umeisha. Jaribu tena.');
    } catch (e) {
      return ZenoCreateResult.failure(e.toString());
    }
  }

  /// `payment_status` from status API, e.g. `COMPLETED`.
  static Future<ZenoStatusResult> fetchOrderStatus(String orderId) async {
    try {
      final res = await http
          .get(
            Uri.parse(zenoOrderStatusUrl(orderId)),
            headers: _authHeaders(),
          )
          .timeout(const Duration(seconds: 30));

      final text = utf8.decode(res.bodyBytes);
      Map<String, dynamic> j;
      try {
        j = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return ZenoStatusResult.error('Jibu la hali halisomeki: ${res.statusCode}');
      }

      final rc = j['resultcode']?.toString();
      if (rc != '000' && rc != '0') {
        return ZenoStatusResult.error(j['message']?.toString() ?? 'Haikuweza kupata hali ya malipo');
      }

      final list = j['data'];
      if (list is! List || list.isEmpty) {
        return ZenoStatusResult.pending(null);
      }
      final row = Map<String, dynamic>.from(list.first as Map);
      final ps = row['payment_status']?.toString().toUpperCase() ?? '';
      return ZenoStatusResult(paymentStatus: ps, raw: row);
    } on TimeoutException {
      return ZenoStatusResult.error('Muda wa kuunganisha umeisha.');
    } catch (e) {
      return ZenoStatusResult.error(e.toString());
    }
  }

  /// Poll until [COMPLETED], failed/cancelled, or timeout.
  static Future<ZenoPollOutcome> waitForCompleted(
    String orderId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 4),
    bool Function()? cancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
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
      await Future<void>.delayed(interval);
    }
    return ZenoPollOutcome.timeout();
  }

  static String newOrderId() => _uuid.v4();
}

class ZenoCreateResult {
  ZenoCreateResult._({this.pollOrderId, this.message, this.errorMessage});

  factory ZenoCreateResult.ok({required String pollOrderId, String? message}) =>
      ZenoCreateResult._(pollOrderId: pollOrderId, message: message);

  factory ZenoCreateResult.failure(String msg) => ZenoCreateResult._(errorMessage: msg);

  final String? pollOrderId;
  final String? message;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null && pollOrderId != null;
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
