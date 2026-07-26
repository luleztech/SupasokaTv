import 'package:flutter_test/flutter_test.dart';
import 'package:supasoka/services/tanzania_phone.dart';

void main() {
  group('TanzaniaPhone payment prefixes', () {
    test('normalizes Halopesa 061, 062, 063 in supported formats', () {
      for (final prefix in ['061', '062', '063']) {
        final raw = '${prefix}2345678';
        expect(TanzaniaPhone.normalize(raw), '0${prefix.substring(1)}2345678');
        expect(TanzaniaPhone.supportsPushUssd(raw), isTrue);
        expect(TanzaniaPhone.walletLabel(raw), 'Halopesa');
      }
    });

    test('normalizes Vodacom M-Pesa 079 in supported formats', () {
      for (final raw in [
        '0792345678',
        '792345678',
        '255792345678',
        '+255792345678',
      ]) {
        expect(TanzaniaPhone.normalize(raw), '0792345678');
        expect(TanzaniaPhone.isVodacomMpesa(raw), isTrue);
        expect(TanzaniaPhone.supportsPushUssd(raw), isTrue);
        expect(TanzaniaPhone.walletLabel(raw), 'M-Pesa');
      }
    });

    test('normalizes Airtel Money 066 in supported formats', () {
      for (final raw in [
        '0662345678',
        '662345678',
        '255662345678',
        '+255662345678',
      ]) {
        expect(TanzaniaPhone.normalize(raw), '0662345678');
        expect(TanzaniaPhone.supportsPushUssd(raw), isTrue);
        expect(TanzaniaPhone.walletLabel(raw), 'Airtel Money');
      }
    });
  });
}
