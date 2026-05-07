/// ZenoPay Tanzania Mobile Money — [official API](https://zenoapi.com).
///
/// **API key (required)**  
/// `--dart-define=ZENO_API_KEY=your_key`  
/// Never commit real keys; `ZENO_API_KEY` defaults to empty in source.
///
/// **Optional webhook**  
/// `--dart-define=ZENO_WEBHOOK_URL=https://your-server/zeno-webhook`
///
/// **Local / proxy base (recommended for Flutter Web)**  
/// Browsers block cross-origin calls to `zenoapi.com` unless their CORS allows your origin.  
/// Point to your own backend (or dev proxy) that forwards to Zeno with the same paths:  
/// `--dart-define=ZENO_API_BASE=http://localhost:8080`  
/// That server should POST to `https://zenoapi.com/api/payments/mobile_money_tanzania` and forward responses.
const String kZenoWebhookUrl = String.fromEnvironment('ZENO_WEBHOOK_URL');

const String kZenoApiKey = String.fromEnvironment(
  'ZENO_API_KEY',
  defaultValue: '',
);

/// No trailing slash. Production default matches ZenoPay docs.
const String kZenoApiBase = String.fromEnvironment(
  'ZENO_API_BASE',
  defaultValue: 'https://zenoapi.com',
);

String get kZenoCreateUrl {
  final b = kZenoApiBase.replaceAll(RegExp(r'/$'), '');
  return '$b/api/payments/mobile_money_tanzania';
}

String zenoOrderStatusUrl(String orderId) {
  final b = kZenoApiBase.replaceAll(RegExp(r'/$'), '');
  final q = Uri.encodeQueryComponent(orderId);
  return '$b/api/payments/order-status?order_id=$q';
}
