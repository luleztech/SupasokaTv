import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
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
  });

  it('uses national numbers for Halo and Yas, international for M-Pesa and Airtel', () => {
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0614111222'), ['0614111222']);
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0654111222'), ['0654111222']);
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0744111222'), ['255744111222']);
    assert.deepEqual(phoneCandidatesForSonicPesaApi('0684111222'), ['255684111222']);
  });
});
