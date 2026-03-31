# Drift

Drift is a cross-platform file transfer application that leverages **Flutter** for a modern user interface and **Rust** for high-performance networking and file-handling logic. It enables seamless file sharing across local networks with automatic device discovery.

## Architecture

Drift is built with a clear separation between the UI and the core logic:

-   **Frontend (Flutter):** Uses **Riverpod** for state management. The UI is a state-driven "Shell" that adapts based on whether the app is idle, preparing a transfer, or actively sending/receiving.
-   **Backend (Rust):** Handles the heavy lifting, including LAN discovery (mDNS and UDP), secure networking, and high-performance file I/O. This ensures consistent behavior and speed across all supported platforms.
-   **Bridge (`flutter_rust_bridge`):** Facilitates communication between Dart and Rust. It allows the Flutter UI to trigger Rust functions and receive asynchronous updates (like transfer progress) via Dart streams.

## How It Works

1.  **Initialization:** On startup, the Flutter app initializes the Rust library (`RustLib.init()`).
2.  **Discovery:** The app automatically scans the local network using mDNS (`_drift._udp`) and UDP pings (on port 47474) to find other Drift-enabled devices.
3.  **State Management:** The `DriftAppNotifier` manages the application's lifecycle, transitioning between session states (e.g., `Idle`, `SendDraft`, `Transferring`) based on user actions and network events.
4.  **Transfer:** When a transfer starts, the Rust backend manages the data stream, providing real-time progress updates back to the Flutter UI for display.

## Project Structure

-   `lib/state/`: Business logic and state management (Riverpod).
-   `lib/shell/`: Main UI components and navigation.
-   `rust/src/api/`: Rust implementation of discovery, sending, and receiving logic.
-   `rust_builder/`: Native build glue for compiling Rust code for each platform.

## What Is Set Up

- Rust crate: `rust/`
- Generated Dart bindings: `lib/src/rust`
- FRB config: `flutter_rust_bridge.yaml`
- Native build glue: `rust_builder/`

The current hello-world path is:

- Rust function: `rust/src/api/simple.rs`
- Dart wrapper: `lib/src/rust/api/simple.dart`
- App entrypoint: `lib/main.dart`

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

For Android testing, connect a device or start an emulator and run:

```bash
flutter run -d android
```

On Android, the app skips desktop window management and keeps file picking through the native chooser.

## LAN discovery (nearby receivers)

The send screen browses mDNS for `_drift._udp` (same as the CLI `--nearby` path). Receivers also answer a **UDP presence ping** on port **47474** (the SRV port in the advertisement); browsers only list peers that respond, so mDNS-only ghosts are dropped. **Dev builds** on desktop often work without extra setup. **Store / hardened** builds may need platform permissions:

- **macOS**: Enable the Local Network capability where required; add a usage string if the system prompts for local network access.
- **iOS**: Set `NSLocalNetworkUsageDescription` in `Info.plist`; declare the Bonjour service type `_drift._udp` (and related) per Apple’s Bonjour browsing rules.
- **Android**: Multicast/Wi‑Fi may require `CHANGE_WIFI_MULTICAST_STATE` and holding a multicast lock where the OS requires it.

Simulators, VPNs, and split tunnels can hide LAN peers; the UI falls back to the passive receive state until a transfer arrives.

## Edit The Rust API

1. Update Rust functions under `flutter/rust/src/api/`
2. Regenerate bindings with `flutter_rust_bridge_codegen generate`
3. Re-run the Flutter app
