String normalizedPaymentStatus(Object? status) =>
    (status?.toString() ?? '').trim().toUpperCase();

bool isPaymentCompleted(Object? status) {
  final s = normalizedPaymentStatus(status);
  return s == 'COMPLETED' || s == 'SUCCESS' || s == 'PAID';
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
