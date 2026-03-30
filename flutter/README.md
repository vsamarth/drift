# Drift Flutter App

This Flutter app is wired to Rust with `flutter_rust_bridge`.

## What Is Set Up

- Rust crate: `flutter/rust`
- Generated Dart bindings: `flutter/lib/src/rust`
- FRB config: `flutter/flutter_rust_bridge.yaml`
- Native build glue: `flutter/rust_builder`

The current hello-world path is:

- Rust function: `flutter/rust/src/api/simple.rs`
- Dart wrapper: `flutter/lib/src/rust/api/simple.dart`
- App entrypoint: `flutter/lib/main.dart`

On startup, Flutter initializes the Rust library and calls `greet(name: 'Drift')`.
The returned string is shown in the idle identity area so you can confirm the bridge is working.

## Regenerate Bindings

From `flutter/`:

```bash
flutter_rust_bridge_codegen generate
```

## Run The App

From `flutter/`:

```bash
flutter run -d macos
```

## LAN discovery (nearby receivers)

The send screen browses mDNS for `_drift._udp` (same as the CLI `--nearby` path). Receivers also answer a **UDP presence ping** on port **47474** (the SRV port in the advertisement); browsers only list peers that respond, so mDNS-only ghosts are dropped. **Dev builds** on desktop often work without extra setup. **Store / hardened** builds may need platform permissions:

- **macOS**: Enable the Local Network capability where required; add a usage string if the system prompts for local network access.
- **iOS**: Set `NSLocalNetworkUsageDescription` in `Info.plist`; declare the Bonjour service type `_drift._udp` (and related) per Apple’s Bonjour browsing rules.
- **Android**: Multicast/Wi‑Fi may require `CHANGE_WIFI_MULTICAST_STATE` and holding a multicast lock where the OS requires it.

Simulators, VPNs, and split tunnels can hide LAN peers; the UI falls back to manual code entry.

## Edit The Rust API

1. Update Rust functions under `flutter/rust/src/api/`
2. Regenerate bindings with `flutter_rust_bridge_codegen generate`
3. Re-run the Flutter app
