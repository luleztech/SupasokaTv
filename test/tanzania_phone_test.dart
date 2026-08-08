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

    test('normalizes Vodacom M-Pesa 075 and 079', () {
      for (final raw in [
        '0752345678',
        '0792345678',
        '792345678',
        '255792345678',
        '+255792345678',
        '255752345678',
      ]) {
        final local = TanzaniaPhone.normalize(raw)!;
        expect(local.startsWith('075') || local.startsWith('079'), isTrue);
        expect(TanzaniaPhone.isVodacomMpesa(raw), isTrue);
        expect(TanzaniaPhone.supportsPushUssd(raw), isTrue);
        expect(TanzaniaPhone.walletLabel(raw), 'M-Pesa');
      }
    });

    test('normalizes Airtel Money 066/068/069/078', () {
      for (final raw in [
        '0662345678',
        '0682345678',
        '0692345678',
        '0782345678',
        '255662345678',
        '+255782345678',
      ]) {
        expect(TanzaniaPhone.normalize(raw), isNotNull);
        expect(TanzaniaPhone.supportsPushUssd(raw), isTrue);
        expect(TanzaniaPhone.walletLabel(raw), 'Airtel Money');
      }
    });

    test('normalizes Tigo/Yas 065/067/071/077', () {
      for (final raw in [
        '0652345678',
        '0672345678',
        '0712345678',
        '0772345678',
        '255712345678',
      ]) {
        expect(TanzaniaPhone.normalize(raw), isNotNull);
        expect(TanzaniaPhone.supportsPushUssd(raw), isTrue);
        expect(TanzaniaPhone.walletLabel(raw), 'TigoPesa / Mixx');
      }
    });
  });
}
