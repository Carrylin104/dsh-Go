import 'package:dsh_app/state/media_catalog.dart';
import 'package:dsh_app/state/media_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart' show testMediaNamespace;

void main() {
  const root = 'http://192.168.1.10:18610';
  const catalog = {
    'profiles': {
      'muse-image': {'path': '/images/tasks'},
      'muse-video': {'path': '/videos'},
    },
  };

  test('self-hosted Muse HTTP roots work while other providers require HTTPS', () {
    for (final profile in ['muse-image', 'muse-video']) {
      expect(mediaBaseUrlIssue(root, profile), isNull);
      expect(mediaBaseUrlIssue('$root/v1/', profile), isNull);
      expect(mediaBaseUrlIssue('$root/admin', profile), MediaUrlIssue.endpoint);
      expect(mediaBaseUrlIssue('$root/v1/images/tasks', profile), MediaUrlIssue.endpoint);
      expect(mediaBaseUrlIssue('$root/v1/videos', profile), MediaUrlIssue.endpoint);
      expect(mediaBaseUrlIssue('$root/v1?key=secret', profile), MediaUrlIssue.invalid);
    }
    expect(mediaBaseUrlIssue(root, 'openai-compatible'), MediaUrlIssue.invalid);
    expect(mediaBaseUrlIssue(root, 'ark-video'), MediaUrlIssue.invalid);
  });

  test('request preview includes /v1 exactly once and preserves a reverse proxy prefix', () {
    expect(mediaRequestPreview(root, 'muse-image', catalog), '$root/v1/images/tasks');
    expect(mediaRequestPreview('$root/v1/', 'muse-video', catalog), '$root/v1/videos');
    expect(
      mediaRequestPreview('https://gateway.example/muse/v1', 'muse-image', catalog),
      'https://gateway.example/muse/v1/images/tasks',
    );
    expect(mediaRequestPreview('$root/admin', 'muse-image', catalog), isNull);
  });

  test('the host Muse HTTP presets reach the service picker with shared credentials', () {
    Map<String, Object?> preset(String kind) => {
      'id': 'muse2api-$kind',
      'label': 'Muse $kind',
      'provider': 'muse2api',
      'profile': 'muse-$kind',
      'baseUrl': '$root/v1',
      'models': ['muse-$kind'],
      'kind': kind,
      'keyGroup': 'muse2api',
    };
    final view = testMediaNamespace(
      catalog: {
        'presets': [
          preset('image'),
          preset('video'),
          {...preset('image'), 'id': 'other', 'profile': 'openai-compatible'},
        ],
      },
    );
    final presets = mediaPresetsOf(view);
    expect(presets.map((item) => item.id), ['muse2api-image', 'muse2api-video']);
    expect(presets.map((item) => item.keyGroup), ['muse2api', 'muse2api']);
  });
}
