import 'package:dsh_app/state/media_catalog.dart';
import 'package:dsh_app/state/media_generation.dart' show GenerateKind;
import 'package:dsh_app/state/media_settings.dart';
import 'package:dsh_app/state/muse_setup.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = 'http://192.168.1.10:18610/v1';
final _presets = [
  for (final kind in GenerateKind.values)
    MediaPreset(
      id: 'muse2api-${kind.name}',
      label: 'Muse',
      provider: 'muse2api',
      profile: 'muse-${kind.name}',
      baseUrl: 'http://127.0.0.1:18610/v1',
      models: ['muse-${kind.name}'],
      kind: kind,
      keyGroup: 'muse2api',
    ),
];
final _catalog = MediaCatalog(
  models: {
    for (final kind in GenerateKind.values)
      'muse-${kind.name}': MediaModel(
        id: 'muse-${kind.name}',
        label: 'Muse ${kind.name}',
        kind: kind,
        profile: 'muse-${kind.name}',
      ),
  },
);

MuseSetupPlan? _plan([List<MediaServiceConfig> existing = const [], String root = _root]) => museSetupPlan(
  root: root,
  presets: _presets,
  catalog: _catalog,
  existing: existing,
  defaults: const {'serviceId': 'legacy', 'modelId': 'legacy', 'unrelated': true},
);

void main() {
  test('management-page links become API roots; secrets and request paths are refused', () {
    expect(museSetupRoot('  http://192.168.1.10:18610/admin/ '), _root);
    expect(museSetupRoot('$_root/'), _root);
    expect(museSetupRoot('https://gateway.example/muse/admin'), 'https://gateway.example/muse/v1');
    for (final url in ['$_root/videos', '$_root?key=secret', 'http://user:pass@host/admin', 'ftp://host', '']) {
      expect(museSetupRoot(url), isNull);
    }
  });

  test('one setup shares a key and selects both defaults; configuring again is idempotent', () {
    final plan = _plan()!;
    expect(plan.services, hasLength(2));
    expect(plan.services.every((s) => s.enabled && s.baseUrl == _root && s.keyRef == plan.keyRef), isTrue);
    expect(plan.defaults['imageServiceId'], plan.services[0].id);
    expect(plan.defaults['videoServiceId'], plan.services[1].id);
    expect(plan.defaults['serviceId'], '');
    expect(plan.defaults['unrelated'], isTrue);
    final again = _plan(plan.services)!;
    expect(mediaServiceRows(again.services), mediaServiceRows(plan.services));
    expect(again.keyRef, plan.keyRef);
  });

  test('another server gets its own key and existing services retain theirs', () {
    final first = _plan()!;
    final second = _plan(first.services, 'https://other.example/v1')!;
    expect(second.services, hasLength(4));
    expect(second.keyRef, isNot(first.keyRef));
    expect(mediaServiceRows(second.services.take(2)), mediaServiceRows(first.services));
  });

  test('a key shared outside the pair is never overwritten by quick setup', () {
    final first = _plan()!;
    final donor = first.services.first.copyWith(id: 'other', baseUrl: 'https://other.example/v1');
    final next = _plan([...first.services, donor])!;
    expect(next.services, hasLength(5));
    expect(next.keyRef, isNot(first.keyRef));
  });

  test('service limit refuses the entire pair and leaves the input intact', () {
    final first = _plan()!;
    final existing = [
      for (var n = 0; n < 7; n++) first.services.first.copyWith(id: 'service_$n', baseUrl: 'https://other.example/v1'),
    ];
    expect(_plan(existing), isNull);
    expect(existing, hasLength(7));
  });
}
