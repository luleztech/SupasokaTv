import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/app_update_service.dart';
import 'package:supasoka/services/tanzania_phone.dart';

class _PaymentsApi {
  static const _startPaymentTimeout = Duration(seconds: 95);

  /// Only retry true transport/server blips. Do not re-hit Sonic on wallet/STK failures —
  /// especially Airtel — or the per-number rate limit shows "Subiri dakika 2–5".
  /// One POST per tap — backend owns Sonic retries; client must not double-hit checkout.
  static const _maxStartRounds = 1;

  static bool _isRetryableStartPaymentError(Object e, int round) {
    if (round >= _maxStartRounds) return false;
    return _isTransientStartPaymentError(e);
  }

  static bool _isTransientStartPaymentError(Object e) {
    final lower = e.toString().toLowerCase();
    return lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('socketexception') ||
        lower.contains('connection') ||
        lower.contains('failed host') ||
        lower.contains('haikuweza kuunganisha') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504');
  }

  Future<Map<String, dynamic>> _postStartPayment({
    required Uri uri,
    required Map<String, String> headers,
    required String bodyJson,
  }) async {
    final res = await http
        .post(uri, headers: headers, body: bodyJson)
        .timeout(_startPaymentTimeout);
    return _parseStartPaymentResponse(res);
  }

  Map<String, dynamic> _parseStartPaymentResponse(http.Response res) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Jibu la seva halisomeki (${res.statusCode}).');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = j['error'];
      String msg = 'Ombi la malipo halijakubaliwa.';
      if (res.statusCode == 426 || j['updateRequired'] == true) {
        msg = 'Update app yako kutoka Play Store ili kukamilisha malipo, kisha jaribu tena.';
      } else if (err is Map && err['message'] != null) {
        msg = err['message'].toString();
      } else if (j['error'] is String) {
        msg = j['error'] as String;
      } else if (j['message'] != null) {
        msg = j['message'].toString();
      }
      // Prefer backend Swahili. Only invent Subiri 2–5 for true per-number quotas —
      // never for Railway/CDN "Too Many Requests" (that falsely blocks first-time 070 users).
      final lower = msg.toLowerCase();
      final isPerNumberQuota = lower.contains('majaribio mengi') ||
          lower.contains('umefanya majaribio') ||
          lower.contains('subiri sekunde') ||
          ((lower.contains('nambari') ||
                  lower.contains('number') ||
                  lower.contains('phone') ||
                  lower.contains('msisdn') ||
                  lower.contains('simu')) &&
              (lower.contains('attempt') ||
                lower.contains('majaribio') ||
                lower.contains('rate limit') ||
                lower.contains('limit reached')));
      if (isPerNumberQuota &&
          !(err is Map && (err['message']?.toString().trim().isNotEmpty ?? false))) {
        msg =
            'Umefanya majaribio mengi kwa nambari hii. Subiri dakika 2–5 bila kubonyeza tena, kisha jaribu.';
      } else if (res.statusCode == 429 ||
          lower.contains('too many requests') ||
          lower == 'rate limited' ||
          RegExp(r'too many attempts?', caseSensitive: false).hasMatch(lower)) {
        if (isPerNumberQuota || lower.contains('subiri sekunde') || lower.contains('majaribio')) {
          msg = err is Map && err['message'] != null
              ? err['message'].toString()
              : 'Umefanya majaribio mengi kwa nambari hii. Subiri dakika 2–5 bila kubonyeza tena, kisha jaribu.';
        } else {
          msg = 'Huduma ina shughuli nyingi sasa. Subiri sekunde chache, kisha jaribu tena.';
        }
      }
      throw Exception(msg);
    }

    final orderId = (j['orderId'] ?? j['order_id'] ?? '').toString().trim();
    if (orderId.isEmpty) {
      throw Exception('Seva haikurudisha order id.');
    }
    final provider = (j['provider'] ?? j['paymentProvider'] ?? 'sonicpesa').toString().toLowerCase();
    return {
      'orderId': orderId,
      'message': (j['message'] ?? 'Ombi la malipo limetumwa.').toString(),
      'provider': provider,
    };
  }

  /// Starts checkout via backend — SonicPesa mobile money (all TZ networks).
  Future<Map<String, dynamic>> startPayment({
    required String externalId,
    required String bundle,
    required int amount,
    required String phone,
    required String email,
    required String name,
    void Function(int attempt, int maxAttempts)? onAttempt,
  }) async {
    final normalizedPhone = TanzaniaPhone.normalize(phone.trim()) ?? phone.trim();
    // Caller (_send) already registered the user — avoid duplicate API hits before checkout.
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/payments/start');
    final versionHeaders = await appVersionHeaders();
    final bodyJson = jsonEncode(<String, dynamic>{
      'publicId': externalId,
      'planId': bundle,
      'amount': amount,
      'phone': normalizedPhone,
      'buyer_email': email,
      'buyer_name': name,
      'metadata': {
        'plan_id': bundle,
        'external_id': externalId,
        'buyer_phone': normalizedPhone,
      },
    });
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...versionHeaders,
    };

    Object? lastErr;
    for (var round = 0; round < _maxStartRounds; round++) {
      onAttempt?.call(round + 1, _maxStartRounds);
      try {
        final out = await _postStartPayment(uri: uri, headers: headers, bodyJson: bodyJson);
        return out;
      } catch (e) {
        lastErr = e;
        if (round < _maxStartRounds - 1 && _isRetryableStartPaymentError(e, round)) {
          await Future<void>.delayed(Duration(milliseconds: 800 * (round + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw Exception(lastErr?.toString() ?? 'Haikuweza kuunganisha na seva ya malipo.');
  }

  Future<Map<String, dynamic>> checkPaymentStatus(String orderId) async {
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    final versionParams = await appVersionQueryParams();
    final versionHeaders = await appVersionHeaders();
    final uris = <Uri>[
      Uri.parse('$origin/api/v1/public/payments/status').replace(
        queryParameters: {
          'orderId': orderId,
          ...versionParams,
        },
      ),
    ];

    http.Response? res;
    Object? lastErr;
    for (final uri in uris) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          res = await http
              .get(uri, headers: {
                'Accept': 'application/json',
                ...versionHeaders,
              })
              .timeout(const Duration(seconds: 22));
          if (res.statusCode != 404) break;
        } catch (e) {
          lastErr = e;
          if (attempt == 0 && _isTransientStartPaymentError(e)) {
            await Future<void>.delayed(const Duration(milliseconds: 600));
            continue;
          }
        }
        break;
      }
      if (res != null && res.statusCode != 404) break;
    }
    if (res == null) {
      throw Exception(lastErr?.toString() ?? 'Haikuweza kupata hali ya malipo.');
    }

    final text = utf8.decode(res.bodyBytes);
    Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Jibu la hali halisomeki');
    }

    final topStatus = j['paymentStatus']?.toString();
    final list = j['data'];
    String? ps = topStatus;
    if (list is List && list.isNotEmpty && list.first is Map) {
      final row = Map<String, dynamic>.from(list.first as Map);
      ps ??= row['payment_status']?.toString() ??
          row['PaymentStatus']?.toString() ??
          row['paymentStatus']?.toString() ??
          row['status']?.toString();
    }
    final premiumRaw = j['premiumUntilMs'];
    int? premiumUntilMs;
    if (premiumRaw is int) premiumUntilMs = premiumRaw;
    if (premiumRaw is num) premiumUntilMs = premiumRaw.toInt();

    final rawIntentPlanId = (j['intentPlanId'] ?? j['planId'])?.toString().trim();
    final intentPlanId = (rawIntentPlanId != null && rawIntentPlanId.isNotEmpty) ? rawIntentPlanId : null;

    return {
      'status': ps,
      'raw': j,
      'premiumUntilMs': ?premiumUntilMs,
      if (j['activated'] == true) 'activated': true,
      'intentPlanId': ?intentPlanId,
    };
  }

  @Deprecated('Use startPayment')
  Future<Map<String, dynamic>> startZenoPayment({
    required String externalId,
    required String bundle,
    required int amount,
    required String phone,
    required String email,
    required String name,
  }) =>
      startPayment(
        externalId: externalId,
        bundle: bundle,
        amount: amount,
        phone: phone,
        email: email,
        name: name,
      );

  @Deprecated('Use checkPaymentStatus')
  Future<Map<String, dynamic>> checkZenoStatus(String orderId) => checkPaymentStatus(orderId);
}

final paymentsApi = _PaymentsApi();
