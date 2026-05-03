/// ZenoPay Tanzania Mobile Money (USSD push).
///
/// Build with `--dart-define=ZENO_API_KEY=...` to avoid embedding a key in source.
/// Optional: `--dart-define=ZENO_WEBHOOK_URL=https://your-server/zeno-webhook`
const String kZenoWebhookUrl = String.fromEnvironment('ZENO_WEBHOOK_URL');

const String kZenoApiKey = String.fromEnvironment(
  'ZENO_API_KEY',
  defaultValue:
      'R-RjyolNZurj4oFIBnarvyKnnzXIhKVrqkjWjpoCk29V-1fhi3tgoL1C9D9IcwQpbYvytC0A2Wp-qb30OzEm0A',
);

const String kZenoCreateUrl = 'https://zenoapi.com/api/payments/mobile_money_tanzania';

String zenoOrderStatusUrl(String orderId) {
  final q = Uri.encodeQueryComponent(orderId);
  return 'https://zenoapi.com/api/payments/order-status?order_id=$q';
}
