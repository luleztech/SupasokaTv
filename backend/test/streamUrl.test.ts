import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  firstStreamUrl,
  isPlayableChannelId,
  normalizeStreamUrl,
  resolveStoredStreamUrl,
} from '../src/lib/streamUrl.ts';

const saved = 'https://cdn.example.com/saved.m3u8';

describe('normalizeStreamUrl', () => {
  it('joins a line-wrapped link and drops invisible characters', () => {
    assert.equal(
      normalizeStreamUrl(' \u200Bhttps://cdn.example.com/live/\nchannel.m3u8\uFEFF '),
      'https://cdn.example.com/live/channel.m3u8',
    );
  });

  it('unwraps quotes', () => {
    assert.equal(
      normalizeStreamUrl('"https://cdn.example.com/a.m3u8"'),
      'https://cdn.example.com/a.m3u8',
    );
  });

  it('keeps the http link when extra words were pasted with it', () => {
    assert.equal(
      normalizeStreamUrl('link: https://cdn.example.com/a.m3u8'),
      'https://cdn.example.com/a.m3u8',
    );
  });

  it('treats whitespace and invisible-only values as no link', () => {
    assert.equal(normalizeStreamUrl(' \n\t'), '');
    assert.equal(normalizeStreamUrl('\u200B'), '');
    assert.equal(normalizeStreamUrl(null), '');
  });
});

describe('firstStreamUrl', () => {
  it('does not let an empty streamUrl hide url', () => {
    assert.equal(
      firstStreamUrl(['', 'https://cdn.example.com/a.m3u8', null]),
      'https://cdn.example.com/a.m3u8',
    );
  });

  it('returns empty when every alias is blank', () => {
    assert.equal(firstStreamUrl(['\n', '   ', null]), '');
  });
});

describe('resolveStoredStreamUrl', () => {
  it('stores a cleaned replacement link', () => {
    assert.equal(
      resolveStoredStreamUrl([' \nhttps://cdn.example.com/new.m3u8 '], saved, false),
      'https://cdn.example.com/new.m3u8',
    );
  });

  it('keeps the saved link when a later edit omits it', () => {
    assert.equal(resolveStoredStreamUrl(['', null], saved, false), saved);
  });

  it('keeps the saved link when the incoming value is only paste noise', () => {
    assert.equal(resolveStoredStreamUrl(['\n\u200B'], ` ${saved}\n`, false), saved);
  });

  it('deletes the link only when clear was requested', () => {
    assert.equal(resolveStoredStreamUrl([''], saved, true), '');
  });

  it('a new link wins over a clear flag', () => {
    assert.equal(
      resolveStoredStreamUrl(['https://cdn.example.com/new.m3u8'], saved, true),
      'https://cdn.example.com/new.m3u8',
    );
  });
});

describe('isPlayableChannelId', () => {
  it('allows channel id 0 and rejects negatives', () => {
    assert.equal(isPlayableChannelId(0), true);
    assert.equal(isPlayableChannelId(4), true);
    assert.equal(isPlayableChannelId(-1), false);
    assert.equal(isPlayableChannelId(1.5), false);
  });
});
