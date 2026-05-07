import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/zeno_pay_service.dart';

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
}

class _PaymentsApi {
  Future<Map<String, dynamic>> startZenoPayment({
    required String externalId,
    required String bundle,
    required int amount,
    required String phone,
    required String email,
    required String name,
  }) async {
    await UserIdentity.registerWithBackend(phone: phone);
    final created = await ZenoPayService.createOrder(
      requestedOrderId: ZenoPayService.newOrderId(),
      buyerPhoneLocal0xx: phone,
      amountTzs: amount,
      buyerName: name,
      buyerEmail: email,
      metadata: {
        'plan_id': bundle,
        'external_id': externalId,
        'buyer_phone': phone,
      },
    );
    if (!created.isSuccess) {
      throw Exception(created.errorMessage ?? 'Payment request failed');
    }
    return {
      'orderId': created.pollOrderId,
      'message': created.message ?? 'Ombi la malipo limetumwa.',
    };
  }

  Future<Map<String, dynamic>> checkZenoStatus(String orderId) async {
    final st = await ZenoPayService.fetchOrderStatus(orderId);
    if (st.errorMessage != null) {
      throw Exception(st.errorMessage);
    }
    return {
      'status': st.paymentStatus,
      'raw': {'data': [if (st.raw != null) st.raw]},
    };
  }

  Future<void> completePaymentForTesting(String _orderId) async {
    throw Exception('Test complete endpoint not configured');
  }
}

final settingsApi = _SettingsApi();
final paymentsApi = _PaymentsApi();
