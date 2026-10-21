import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  adminGrantMs,
  noteWithAdminGrant,
  noteWithoutAdminGrant,
} from '../src/services/premiumGrantNote.ts';

describe('admin premium grant marker', () => {
  const week = Date.now() + 7 * 24 * 60 * 60 * 1000;
  const month = Date.now() + 30 * 24 * 60 * 60 * 1000;

  it('keeps the latest grant and drops a revoke mark', () => {
    const note = noteWithAdminGrant('mteja | premium_revoked:admin | premium_admin_grant:1700000000000', week);
    assert.equal(adminGrantMs(note), week);
    assert.equal(note.includes('premium_revoked:'), false);
    assert.equal(note.includes('1700000000000'), false);
    assert.equal(note.includes('mteja'), true);
  });

  it('a newer grant wins over an older one left in the note', () => {
    const note = `premium_admin_grant:${week} | premium_admin_grant:${month}`;
    assert.equal(adminGrantMs(note), month);
    assert.ok(adminGrantMs(note) > Date.now());
  });

  it('revoke removes the grant so a paid-period cap may apply again', () => {
    const note = noteWithoutAdminGrant(noteWithAdminGrant('mteja', week));
    assert.equal(adminGrantMs(note), 0);
    assert.equal(note.includes('premium_revoked:admin'), true);
    assert.equal(note.includes('mteja'), true);
  });

  it('an expired grant does not protect a subscription', () => {
    assert.equal(adminGrantMs('premium_admin_grant:1700000000000') > Date.now(), false);
    assert.equal(adminGrantMs('') > Date.now(), false);
    assert.equal(adminGrantMs(null) > Date.now(), false);
  });
});
