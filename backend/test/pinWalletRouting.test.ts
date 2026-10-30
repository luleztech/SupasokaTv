import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  isSupportedSonicPushWallet,
  phoneCandidatesForSonicPesaApi,
  sonicDispatchChannel,
} from '../src/lib/tzPhone.ts';

describe('PIN wallet routing', () => {
  it('names the wallet channel for every push network', () => {
    assert.equal(sonicDispatchChannel('0744111222'), 'MPESA');
    assert.equal(sonicDispatchChannel('0754111222'), 'MPESA');
    assert.equal(sonicDispatchChannel('0764111222'), 'MPESA');
    assert.equal(sonicDispatchChannel('0794111222'), 'MPESA');
    assert.equal(sonicDispatchChannel('0784111222'), 'AIRTELMONEY');
    assert.equal(sonicDispatchChannel('0684111222'), 'AIRTELMONEY');
    assert.equal(sonicDispatchChannel('0714111222'), 'TIGOPESATZ');
    assert.equal(sonicDispatchChannel('0654111222'), 'TIGOPESATZ');
    assert.equal(sonicDispatchChannel('0614111222'), 'HALOPESA');
    assert.equal(sonicDispatchChannel('0624111222'), 'HALOPESA');
    assert.equal(sonicDispatchChannel('0664111222'), 'AIRTELMONEY');
    assert.equal(sonicDispatchChannel('0694111222'), 'AIRTELMONEY');
    assert.equal(sonicDispatchChannel('0704111222'), 'TIGOPESATZ');
    assert.equal(sonicDispatchChannel('0774111222'), 'TIGOPESATZ');
    assert.equal(sonicDispatchChannel('0634111222'), 'HALOPESA');
    assert.equal(sonicDispatchChannel('0724111222'), 'MPESA');
    assert.equal(isSupportedSonicPushWallet('0644111222'), true);
    assert.equal(isSupportedSonicPushWallet('0734111222'), true);
  });

  it('uses national numbers for Halo and Yas, international for M-Pesa and Airtel', () => {
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0614111222'), ['0614111222']);
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0654111222'), ['0654111222']);
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0744111222'), ['255744111222']);
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0684111222'), ['255684111222']);
  });
});
