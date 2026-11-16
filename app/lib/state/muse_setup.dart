import 'media_catalog.dart';
import 'media_generation.dart' show GenerateKind;
import 'media_settings.dart';

/// Accept the management-page link as a convenience, but store only the API
/// root. Query strings, credentials and request endpoints are still refused.
String? museSetupRoot(String input) {
  var root = input.trim().replaceAll(RegExp(r'/+$'), '');
  if (root.endsWith('/admin')) root = root.substring(0, root.length - 6);
  if (mediaBaseUrlIssue(root, 'muse-image') != null) return null;
  return root.endsWith('/v1') ? root : '$root/v1';
}

class MuseSetupPlan {
  const MuseSetupPlan(this.services, this.defaults, this.keyRef);
  final List<MediaServiceConfig> services;
  final Map<String, Object?> defaults;
  final String keyRef;
}

/// A pair on this exact endpoint can be configured again without duplicates.
/// Other providers and other Muse servers retain their services and keys.
MuseSetupPlan? museSetupPlan({
  required String root,
  required List<MediaPreset> presets,
  required MediaCatalog catalog,
  required List<MediaServiceConfig> existing,
  required Object? defaults,
}) {
  final imagePreset = presets.where((p) => p.profile == 'muse-image').firstOrNull;
  final videoPreset = presets.where((p) => p.profile == 'muse-video').firstOrNull;
  if (imagePreset == null || videoPreset == null || museSetupRoot(root) != root) return null;
  MediaServiceConfig? matching(String profile) =>
      existing.where((s) => s.profile == profile && museSetupRoot(s.baseUrl) == root).firstOrNull;
  var image = matching('muse-image');
  var video = matching('muse-video');
  final reusable =
      image != null &&
      video != null &&
      image.keyRef == video.keyRef &&
      image.keyRef.startsWith('DSH_MEDIA_') &&
      !existing.any((s) => s.keyRef == image!.keyRef && s.id != image.id && s.id != video!.id);
  var services = [...existing];
  if (!reusable) {
    image = mediaServiceFromPreset(preset: imagePreset, catalog: catalog, existing: services, reuseKey: false);
    if (image == null) return null;
    services.add(image);
    video = mediaServiceFromPreset(preset: videoPreset, catalog: catalog, existing: services, reuseKey: false);
    if (video == null || services.length >= mediaServiceLimit) return null;
    services.add(video);
  }
  final keyRef = image.keyRef;
  image = image.copyWith(baseUrl: root, enabled: true);
  video = video.copyWith(baseUrl: root, enabled: true, keyRef: keyRef);
  services = withMediaService(withMediaService(services, image), video);
  var nextDefaults = mediaDefaultsWith(defaults, serviceId: '', modelId: '');
  nextDefaults = mediaDefaultsWith(
    nextDefaults,
    kind: GenerateKind.image,
    serviceId: image.id,
    modelId: image.models.first,
  );
  nextDefaults = mediaDefaultsWith(
    nextDefaults,
    kind: GenerateKind.video,
    serviceId: video.id,
    modelId: video.models.first,
  );
  return MuseSetupPlan(services, nextDefaults, keyRef);
}
