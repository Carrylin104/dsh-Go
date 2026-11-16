import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../state/engine_settings_state.dart';
import '../../../state/media_generation.dart' show mediaCatalogProvider;
import '../../../state/media_catalog.dart';
import '../../../state/media_settings.dart';
import '../../../state/muse_setup.dart';
import '../../common/app_sheet.dart';
import '../../engine_settings/field_sheets.dart';

Future<void> showMuseSetup(BuildContext context, String ns, EngineSettings settings) => showAppSheet<void>(
  context,
  builder: (_) => MuseSetupSheet(ns: ns, settings: settings),
);

/// Keys remain in the form only until submitted to the existing host credential
/// API. They never enter preferences, service rows, messages or diagnostics.
class MuseSetupSheet extends ConsumerStatefulWidget {
  const MuseSetupSheet({super.key, required this.ns, required this.settings});
  final String ns;
  final EngineSettings settings;

  @override
  ConsumerState<MuseSetupSheet> createState() => _MuseSetupSheetState();
}

class _MuseSetupSheetState extends ConsumerState<MuseSetupSheet> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  late final _editor = ref.read(engineSettingsProvider.notifier).edit(widget.settings);
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = mediaServicesOf(widget.settings.valueOf(FieldRef(widget.ns, const ['services'])));
    _url.text = services.where((s) => s.profile == 'muse-image').firstOrNull?.baseUrl ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final root = museSetupRoot(_url.text);
    if (_busy || root == null || _key.text.trim().isEmpty) return;
    final l10n = context.l10n;
    if (!_editor.active) {
      setState(() => _error = l10n.engineSettingsHostChanged);
      return;
    }
    final settings = ref.read(engineSettingsProvider).value;
    final view = settings?[widget.ns];
    if (settings == null || view == null || !settings.canWrite(widget.ns)) {
      setState(() => _error = l10n.museSetupUnavailable);
      return;
    }
    final apiKey = _key.text.trim();
    final ns = widget.ns;
    final servicesField = FieldRef(ns, const ['services']);
    final defaultsField = FieldRef(ns, const ['defaults']);
    final plan = museSetupPlan(
      root: root,
      presets: mediaPresetsOf(view),
      catalog: ref.read(mediaCatalogProvider),
      existing: mediaServicesOf(settings.valueOf(servicesField)),
      defaults: settings.valueOf(defaultsField),
    );
    if (plan == null) {
      setState(() => _error = l10n.museSetupUnavailable);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _editor.write(
        ns,
        [
          SettingsOp.set(const ['services'], mediaServiceRows(plan.services)),
          SettingsOp.set(const ['defaults'], plan.defaults),
        ],
        fields: [servicesField, defaultsField],
      );
      if (saved) {
        await _editor.setCredential(plan.keyRef, apiKey);
        if (!mounted) return;
        _key.clear();
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(l10n.museSetupSaved)));
      } else {
        if (!mounted) return;
        setState(
          () => _error = ref.read(engineSettingsProvider).value?.errorOf(servicesField) ?? l10n.commonSaveFailed,
        );
      }
    } on EngineSettingsFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final valid = museSetupRoot(_url.text) != null && _key.text.trim().isNotEmpty;
    return PopScope(
      canPop: !_busy,
      child: FieldSheetFrame(
        title: l10n.museSetupTitle,
        actions: SheetActions(
          primary: FilledButton(
            onPressed: _busy || !valid ? null : _save,
            child: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.museSetupAction),
          ),
        ),
        children: [
          Text(l10n.museSetupBody),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('muse-setup-url'),
            controller: _url,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(labelText: l10n.mediaSettingsBaseUrl, hintText: 'https://muse.example/v1'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('muse-setup-key'),
            controller: _key,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(labelText: l10n.mediaSettingsApiKey),
          ),
          SheetHelper(helper: l10n.museSetupHint, error: _error),
        ],
      ),
    );
  }
}
