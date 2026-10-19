import 'package:flutter_test/flutter_test.dart';
import 'package:supaadmin/models/app_config.dart';

void main() {
  test('a dirty saved link is cleaned when admin loads it', () {
    final channel = ChannelDto.fromJson({
      'id': 3,
      'name': 'Azam',
      'cat': 'movies',
      'img': '',
      'free': true,
      'viewers': '1',
      'streamUrl': '',
      'url': ' \u200Bhttps://cdn.example.com/live/\nchannel.m3u8 ',
    });

    expect(channel.url, 'https://cdn.example.com/live/channel.m3u8');
  });

  test('an empty streamUrl does not hide url or stream_url', () {
    final fromUrl = ChannelDto.fromJson({
      'id': 1,
      'name': 'A',
      'cat': 'movies',
      'img': '',
      'free': 'true',
      'viewers': 12,
      'streamUrl': '',
      'url': 'https://cdn.example.com/a.m3u8',
    });
    final fromSnake = ChannelDto.fromJson({
      'id': 2,
      'name': 'B',
      'cat': 'movies',
      'img': '',
      'free': true,
      'viewers': '',
      'streamUrl': '',
      'url': '',
      'stream_url': 'https://cdn.example.com/b.m3u8',
    });

    expect(fromUrl.url, 'https://cdn.example.com/a.m3u8');
    expect(fromSnake.url, 'https://cdn.example.com/b.m3u8');
  });

  test('one channel without an id does not drop the channels that have links', () {
    final config = AppConfig.fromJson({
      'channels': [
        {'name': 'broken'},
        {
          'id': 7,
          'name': 'Ok',
          'cat': 'mpira',
          'img': '',
          'free': true,
          'viewers': '',
          'stream_url': 'https://cdn.example.com/ok.m3u8',
        },
      ],
    });

    expect(config.channels, hasLength(1));
    expect(config.channels.single.url, 'https://cdn.example.com/ok.m3u8');
  });

  test('saving a channel sends every link alias', () {
    final json = ChannelDto(
      id: 1,
      name: 'A',
      cat: 'movies',
      img: '',
      free: true,
      viewers: '0',
      url: 'https://cdn.example.com/a.m3u8',
    ).toJson();

    expect(json['url'], 'https://cdn.example.com/a.m3u8');
    expect(json['streamUrl'], json['url']);
    expect(json['stream_url'], json['url']);
    expect(json['clearStreamUrl'], isFalse);
  });
}
