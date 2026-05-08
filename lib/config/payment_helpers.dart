String normalizedPaymentStatus(Object? status) =>
    (status?.toString() ?? '').trim().toUpperCase();

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
      s == 'SETTLED';
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
