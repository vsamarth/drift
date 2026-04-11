import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/drift_theme.dart';
import '../../../platform/platform_features.dart';
import '../../../state/drift_providers.dart';
import '../settings_providers.dart';

class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key, required this.availableHeight});

  final double availableHeight;

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  late final TextEditingController _deviceNameController;
  late final TextEditingController _downloadRootController;
  late final TextEditingController _serverUrlController;
  late String _initialDeviceName;
  late String _initialDownloadRoot;
  late String _initialServerUrl;
  bool _discoverable = true;
  bool _initialDiscoverable = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(settingsControllerProvider);
    _initialDeviceName = state.identity.deviceName;
    _initialDownloadRoot = state.identity.downloadRoot;
    _initialServerUrl = state.identity.serverUrl ?? '';
    _initialDiscoverable = state.identity.discoverableByDefault;
    _deviceNameController = TextEditingController(text: _initialDeviceName);
    _downloadRootController = TextEditingController(text: _initialDownloadRoot);
    _serverUrlController = TextEditingController(text: _initialServerUrl);
    _discoverable = _initialDiscoverable;
    _deviceNameController.addListener(_onFieldChanged);
    _downloadRootController.addListener(_onFieldChanged);
    _serverUrlController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _deviceNameController.removeListener(_onFieldChanged);
    _downloadRootController.removeListener(_onFieldChanged);
    _serverUrlController.removeListener(_onFieldChanged);
    _deviceNameController.dispose();
    _downloadRootController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _deviceNameController.text.trim() != _initialDeviceName.trim() ||
      _downloadRootController.text.trim() != _initialDownloadRoot.trim() ||
      _serverUrlController.text.trim() != _initialServerUrl.trim() ||
      _discoverable != _initialDiscoverable;

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveSettings() async {
    if (_saving || !_isDirty) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .saveSettings(
            deviceName: _deviceNameController.text,
            downloadRoot: _downloadRootController.text,
            serverUrl: _serverUrlController.text,
            discoverableByDefault: _discoverable,
          );
      _initialDeviceName = _deviceNameController.text.trim();
      _initialDownloadRoot = _downloadRootController.text.trim();
      _initialServerUrl = _serverUrlController.text.trim();
      _initialDiscoverable = _discoverable;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickDownloadRoot() async {
    final selected = await ref
        .read(storageAccessSourceProvider)
        .pickDirectory(
          initialDirectory: _downloadRootController.text.trim().isEmpty
              ? null
              : _downloadRootController.text.trim(),
        );

    if (selected == null || selected.trim().isEmpty) {
      return;
    }

    _downloadRootController.text = selected.trim();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsControllerProvider);
    final saving = _saving || state.isSaving;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.errorMessage != null) ...[
                  _SettingsErrorBanner(message: state.errorMessage!),
                  const SizedBox(height: 16),
                ],
                _SettingFieldBlock(
                  label: 'Device name',
                  child: TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(
                      hintText: 'Alex\'s MacBook',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _SettingFieldBlock(
                  label: 'Save received files to',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _downloadRootController,
                        readOnly: isMobilePlatform,
                        enabled: true,
                        onTap: isMobilePlatform ? _pickDownloadRoot : null,
                        decoration: InputDecoration(
                          hintText: '/Users/you/Downloads',
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TextButton(
                              onPressed: _pickDownloadRoot,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: kInk,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: kBorder),
                                ),
                              ),
                              child: Text(
                                'Choose',
                                style: driftSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _FlatToggleRow(
                  title: 'Nearby discoverability',
                  subtitle:
                      'Make this device visible to others on your network.',
                  value: _discoverable,
                  onChanged: (value) => setState(() => _discoverable = value),
                ),
                const SizedBox(height: 30),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      'Advanced',
                      style: driftSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kInk,
                        letterSpacing: -0.35,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Only needed for self-hosted setups.',
                  style: driftSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: kMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                _SettingFieldBlock(
                  label: 'Discovery Server',
                  child: TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://drift.samarthv.com',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
          decoration: BoxDecoration(
            color: kBg,
            border: Border(
              top: BorderSide(color: kBorder.withValues(alpha: 0.9)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Changes apply after you save.',
                  style: driftSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: kMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _isDirty && !saving ? _saveSettings : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A8E9E),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(saving ? 'Saving...' : 'Save Changes'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingFieldBlock extends StatelessWidget {
  const _SettingFieldBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: driftSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: kInk,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _FlatToggleRow extends StatelessWidget {
  const _FlatToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: driftSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: driftSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  color: kMuted,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return Colors.white;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return kAccentCyanStrong;
              }
              return kBorder;
            }),
          ),
        ),
      ],
    );
  }
}

class _SettingsErrorBanner extends StatelessWidget {
  const _SettingsErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFCC3333).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFCC3333).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Color(0xFFCC3333),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: driftSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: kInk,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
