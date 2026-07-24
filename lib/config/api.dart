import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/app_update_service.dart';
import 'package:supasoka/services/tanzania_phone.dart';
import 'package:supasoka/services/user_identity.dart';
class _SettingsApi {
  Future<Map<String, dynamic>> getWhatsAppNumber() async {
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/config');
    final res = await http.get(uri, headers: const {'Accept': 'application/json'});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return {'number': (j['customerCareWhatsapp'] ?? '').toString()};
  }

  Future<String> getActivePaymentProvider() async {
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/settings/payment-provider');
    final res = await http.get(uri, headers: const {'Accept': 'application/json'});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return 'sonicpesa';
    }
    return 'sonicpesa';
  }
}

class _PaymentsApi {
  static const _startPaymentTimeout = Duration(seconds: 95);

  /// Only retry true transport/server blips. Do not re-hit Sonic on wallet/STK failures —
  /// especially Airtel — or the per-number rate limit shows "Subiri dakika 2–5".
  static const _maxStartRounds = 2;

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
      // Prefer backend Swahili. Only invent Subiri 2–5 for true per-number rate limits.
      final lower = msg.toLowerCase();
      final isWalletRateLimit = lower.contains('too many') ||
          lower.contains('many attempt') ||
          lower.contains('majaribio mengi') ||
          lower.contains('rate limit') ||
          lower.contains('limit reached');
      if (isWalletRateLimit ||
          (res.statusCode == 429 &&
              (lower.contains('attempt') ||
                  lower.contains('limit') ||
                  lower.contains('mara') ||
                  lower.contains('majaribio')))) {
        msg =
            'Umefanya majaribio mengi kwa nambari hii. Subiri dakika 2–5 bila kubonyeza tena, kisha jaribu.';
      } else if (res.statusCode == 429) {
        msg = 'Huduma ina shughuli nyingi sasa. Subiri sekunde chache, kisha jaribu tena.';
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
    await Future.wait<void>([
      UserIdentity.registerWithBackend(phone: normalizedPhone),
      settingsApi.getActivePaymentProvider(),
    ]);
    const expectedProvider = 'sonicpesa';
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
        final provider = (out['provider'] ?? 'sonicpesa').toString().toLowerCase();
        if (expectedProvider == 'sonicpesa' && provider != 'sonicpesa') {
          throw Exception(
            'Seva imerudisha $provider lakini SonicPesa imewashwa. Hakikisha backend imedeploy na jaribu tena.',
          );
        }
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
    for (final uri in uris) {
      try {
        res = await http
            .get(uri, headers: {
              'Accept': 'application/json',
              ...versionHeaders,
            })
            .timeout(const Duration(seconds: 22));
        if (res.statusCode != 404) break;
      } catch (_) {
        continue;
      }
    }
    if (res == null) {
      throw Exception('Haikuweza kupata hali ya malipo.');
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

final settingsApi = _SettingsApi();
final paymentsApi = _PaymentsApi();
