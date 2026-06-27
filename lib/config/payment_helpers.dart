String normalizedPaymentStatus(Object? status) =>
    (status?.toString() ?? '').trim().toUpperCase();

/// Gateway / proxy responses vary; normalize so [isPaymentCompleted] sees the real status.
Object? paymentStatusFromCheckResponse(Map<String, dynamic> response) {
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

  final direct = response['status']?.toString().trim();
  if (direct != null && direct.isNotEmpty && direct != 'null') return direct;

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

bool isPaymentCompleted(Object? status) {
  final s = normalizedPaymentStatus(status);
  return s == 'COMPLETED' ||
      s == 'COMPLETE' ||
      s == 'SUCCESS' ||
      s == 'SUCCESSFUL' ||
      s == 'SUCCEEDED' ||
      s == 'PAID' ||
      s == 'APPROVED' ||
      s == 'AUTHORIZED' ||
      s == 'AUTHORISED' ||
      s == 'SETTLED' ||
      s == 'CONFIRMED';
}

bool isPaymentTerminalFailure(Object? status) {
  final s = normalizedPaymentStatus(status);
  return s == 'FAILED' ||
      s == 'ERROR' ||
      s == 'CANCELLED' ||
      s == 'CANCELED' ||
      s == 'REJECTED' ||
      s == 'DECLINED' ||
      s == 'EXPIRED';
}
