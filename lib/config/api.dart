import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
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
      return 'zeno';
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final p = (j['paymentProvider'] ?? 'zeno').toString().toLowerCase();
    return p == 'sonicpesa' ? 'sonicpesa' : 'zeno';
  }
}

class _PaymentsApi {
  /// Starts checkout via backend — admin picks SonicPesa or ZenoPay on SupaAdmin.
  Future<Map<String, dynamic>> startPayment({
    required String externalId,
    required String bundle,
    required int amount,
    required String phone,
    required String email,
    required String name,
  }) async {
    await UserIdentity.registerWithBackend(phone: phone);
    final expectedProvider = await settingsApi.getActivePaymentProvider();
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/payments/start');
    final body = <String, dynamic>{
      'publicId': externalId,
      'planId': bundle,
      'amount': amount,
      'phone': phone,
      'buyer_email': email,
      'buyer_name': name,
      'metadata': {
        'plan_id': bundle,
        'external_id': externalId,
        'buyer_phone': phone,
      },
    };

    http.Response? res;
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        res = await http
            .post(
              uri,
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 45));
        break;
      } catch (e) {
        lastErr = e;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    }
    if (res == null) {
      throw Exception(lastErr?.toString() ?? 'Haikuweza kuunganisha na seva ya malipo.');
    }

    Map<String, dynamic>? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Jibu la seva halisomeki (${res.statusCode}).');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = j['error'];
      String msg = 'Ombi la malipo halijakubaliwa.';
      if (err is Map && err['message'] != null) {
        msg = err['message'].toString();
      } else if (j['error'] is String) {
        msg = j['error'] as String;
      } else if (j['message'] != null) {
        msg = j['message'].toString();
      }
      throw Exception(msg);
    }

    final orderId = (j['orderId'] ?? j['order_id'] ?? '').toString().trim();
    if (orderId.isEmpty) {
      throw Exception('Seva haikurudisha order id.');
    }
    final provider = (j['provider'] ?? j['paymentProvider'] ?? 'zeno').toString().toLowerCase();
    if (expectedProvider == 'sonicpesa' && provider != 'sonicpesa') {
      throw Exception(
        'Seva imerudisha $provider lakini SonicPesa imewashwa. Hakikisha backend imedeploy na jaribu tena.',
      );
    }
    if (expectedProvider == 'zeno' && provider == 'sonicpesa') {
      throw Exception(
        'Seva imerudisha SonicPesa lakini ZenoPay imewashwa kwenye admin. Sasisha mipangilio.',
      );
    }
    return {
      'orderId': orderId,
      'message': (j['message'] ?? 'Ombi la malipo limetumwa.').toString(),
      'provider': provider,
    };
  }

  Future<Map<String, dynamic>> checkPaymentStatus(String orderId) async {
    final origin = apiConfigUrl.replaceAll(RegExp(r'/$'), '');
    final uris = <Uri>[
      Uri.parse('$origin/api/v1/public/payments/status').replace(
        queryParameters: {'orderId': orderId},
      ),
    ];

    http.Response? res;
    for (final uri in uris) {
      try {
        res = await http
            .get(uri, headers: const {'Accept': 'application/json'})
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

    return {
      'status': ps,
      'raw': j,
      if (premiumUntilMs != null) 'premiumUntilMs': premiumUntilMs,
      if (j['activated'] == true) 'activated': true,
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
