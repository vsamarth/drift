import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_providers.dart';

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
  bool _discoverable = true;

  @override
  void initState() {
    super.initState();
    final state = ref.read(driftAppNotifierProvider);
    _deviceNameController = TextEditingController(text: state.deviceName);
    _downloadRootController = TextEditingController(
      text: state.identity.downloadRoot,
    );
    _serverUrlController = TextEditingController(text: 'http://127.0.0.1:8787');
    _discoverable = state.discoverableEnabled;
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _downloadRootController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  child: TextField(
                    controller: _downloadRootController,
                    decoration: const InputDecoration(
                      hintText: '/Users/you/Downloads',
                    ),
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
                      hintText: 'http://127.0.0.1:8787',
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
              FilledButton(onPressed: null, child: const Text('Save Changes')),
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
            activeThumbColor: kAccentCyanStrong,
          ),
        ),
      ],
    );
  }
}
