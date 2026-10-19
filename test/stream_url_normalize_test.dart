import 'package:flutter_test/flutter_test.dart';
import 'package:supasoka/player/stream_url_utils.dart';

void main() {
  test('joins a line-wrapped link and drops invisible characters', () {
    const raw = ' \u200Bhttps://cdn.example.com/live/\nchannel.m3u8\uFEFF ';
    expect(
      normalizeStreamUrl(raw),
      'https://cdn.example.com/live/channel.m3u8',
    );
  });

  test('empty streamUrl does not hide a real url alias', () {
    expect(
      firstStreamUrl(['', 'https://cdn.example.com/a.m3u8', null]),
      'https://cdn.example.com/a.m3u8',
    );
  });

  test('whitespace-only values are not links', () {
    expect(normalizeStreamUrl(' \n\t'), '');
    expect(normalizeStreamUrl('\u200B'), '');
    expect(firstStreamUrl(['\n', '   ', null]), '');
  });

  test('unwraps quotes around a pasted link', () {
    expect(
      normalizeStreamUrl('"https://cdn.example.com/a.m3u8"'),
      'https://cdn.example.com/a.m3u8',
    );
  });

  test('keeps the http link when extra words were pasted with it', () {
    expect(
      normalizeStreamUrl('link: https://cdn.example.com/a.m3u8'),
      'https://cdn.example.com/a.m3u8',
    );
  });
}
