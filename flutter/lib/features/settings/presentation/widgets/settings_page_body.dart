import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/drift_theme.dart';
import '../../../../platform/rust/rendezvous_defaults.dart';
import '../../application/controller.dart';
import '../../settings_providers.dart';
import 'settings_error_banner.dart';
import 'settings_download_root_field.dart';
import 'settings_section_field.dart';
import 'settings_path_display.dart';
import 'settings_toggle_field.dart';

class SettingsPageBody extends ConsumerStatefulWidget {
  const SettingsPageBody({super.key});

  @override
  ConsumerState<SettingsPageBody> createState() => _SettingsPageBodyState();
}

class _SettingsPageBodyState extends ConsumerState<SettingsPageBody> {
  late final TextEditingController _deviceNameController;
  late final TextEditingController _downloadRootController;
  late final TextEditingController _serverUrlController;
  late String _initialDeviceName;
  late String _initialDownloadRoot;
  late String _downloadRootValue;
  late String _initialServerUrl;
  late bool _initialDiscoverable;
  bool _discoverable = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsControllerProvider).settings;
    _initialDeviceName = settings.deviceName;
    _initialDownloadRoot = settings.downloadRoot;
    _downloadRootValue = settings.downloadRoot;
    _initialServerUrl = settings.discoveryServerUrl ?? '';
    _initialDiscoverable = settings.discoverableByDefault;
    _discoverable = _initialDiscoverable;
    _deviceNameController = TextEditingController(text: _initialDeviceName);
    _downloadRootController = TextEditingController(
      text: formatSettingsDownloadRootForDisplay(_initialDownloadRoot),
    );
    _serverUrlController = TextEditingController(text: _initialServerUrl);
    _deviceNameController.addListener(_onFieldChanged);
    _serverUrlController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _deviceNameController.removeListener(_onFieldChanged);
    _serverUrlController.removeListener(_onFieldChanged);
    _deviceNameController.dispose();
    _downloadRootController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  bool get _isDirty {
    return _deviceNameController.text.trim() != _initialDeviceName.trim() ||
        _downloadRootValue.trim() != _initialDownloadRoot.trim() ||
        _serverUrlController.text.trim() != _initialServerUrl.trim() ||
        _discoverable != _initialDiscoverable;
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleBack() async {
    if (_isDirty) {
      final shouldDiscard = await _confirmDiscardChanges();
      if (!shouldDiscard || !mounted) {
        return;
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'You have unsaved changes. Leave this page without saving them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _saveSettings() async {
    if (_saving || !_isDirty) {
      return;
    }

    setState(() => _saving = true);
    await ref
        .read(settingsControllerProvider.notifier)
        .saveSettings(
          deviceName: _deviceNameController.text,
          downloadRoot: _downloadRootValue,
          serverUrl: _serverUrlController.text,
          discoverableByDefault: _discoverable,
        );

    if (!mounted) {
      return;
    }

    final state = ref.read(settingsControllerProvider);
    setState(() {
      _saving = false;
      if (state.errorMessage == null) {
        _initialDeviceName = state.settings.deviceName;
        _initialDownloadRoot = state.settings.downloadRoot;
        _downloadRootValue = state.settings.downloadRoot;
        _initialServerUrl = state.settings.discoveryServerUrl ?? '';
        _initialDiscoverable = state.settings.discoverableByDefault;
        _deviceNameController.text = _initialDeviceName;
        _downloadRootController.text = formatSettingsDownloadRootForDisplay(
          _initialDownloadRoot,
        );
        _serverUrlController.text = _initialServerUrl;
        _discoverable = _initialDiscoverable;
      }
    });

    if (state.errorMessage != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _pickDownloadRoot() async {
    final currentRoot = _downloadRootValue.trim();
    final selected = await ref
        .read(storageAccessSourceProvider)
        .pickDirectory(
          initialDirectory: currentRoot.isEmpty ? null : currentRoot,
        );

    if (selected == null || selected.trim().isEmpty) {
      return;
    }

    setState(() {
      _downloadRootValue = selected.trim();
      _downloadRootController.text = formatSettingsDownloadRootForDisplay(
        _downloadRootValue,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsControllerProvider);
    final saving = _saving || state.isSaving;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleBack());
        }
      },
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _handleBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Settings',
                      style: driftSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: kInk,
                        letterSpacing: -0.35,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.errorMessage != null) ...[
                          SettingsErrorBanner(message: state.errorMessage!),
                          const SizedBox(height: 16),
                        ],
                        SettingsSectionField(
                          label: 'Device name',
                          child: TextField(
                            controller: _deviceNameController,
                            decoration: const InputDecoration(
                              hintText: 'Alex\'s MacBook',
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        SettingsSectionField(
                          label: 'Save received files to',
                          child: SettingsDownloadRootField(
                            controller: _downloadRootController,
                            onChoose: _pickDownloadRoot,
                          ),
                        ),
                        const SizedBox(height: 22),
                        SettingsToggleField(
                          title: 'Nearby discoverability',
                          subtitle:
                              'Make this device visible to others on your network.',
                          value: _discoverable,
                          onChanged: (value) {
                            setState(() => _discoverable = value);
                          },
                        ),
                        const SizedBox(height: 28),
                        const Divider(color: kBorder, height: 1),
                        const SizedBox(height: 18),
                        Text(
                          'Advanced',
                          style: driftSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: kInk,
                            letterSpacing: -0.35,
                          ),
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
                        SettingsSectionField(
                          label: 'Discovery Server',
                          child: TextField(
                            controller: _serverUrlController,
                            decoration: const InputDecoration(
                              hintText: defaultRendezvousUrl,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
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
                      child: saving
                          ? const Text('Saving...')
                          : const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
