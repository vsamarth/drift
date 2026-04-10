# Drift

Drift is a cross-platform file transfer application that leverages **Flutter** for a modern user interface and **Rust** for high-performance networking and file-handling logic. It enables seamless file sharing across local networks with automatic device discovery.

## Architecture

Drift is built with a clear separation between the UI and the core logic:

> Architecture note: the Flutter app now uses feature-owned controllers and state slices for send, receive, and settings, with a small shell composition layer tying them together. The legacy notifier still exists as a compatibility bridge for a few behaviors, but it is no longer the primary architecture.

-   **Frontend (Flutter):** Uses **Riverpod** for state management. The UI is a state-driven shell that composes send, receive, and settings feature state into the active screen.
-   **Backend (Rust):** Handles the heavy lifting, including LAN discovery (mDNS and UDP), secure networking, and high-performance file I/O. This ensures consistent behavior and speed across all supported platforms.
-   **Bridge (`flutter_rust_bridge`):** Facilitates communication between Dart and Rust. It allows the Flutter UI to trigger Rust functions and receive asynchronous updates (like transfer progress) via Dart streams.

## How It Works

1.  **Initialization:** On startup, the Flutter app initializes the Rust library (`RustLib.init()` in `lib/main.dart`).
2.  **Discovery:** The app automatically scans the local network using mDNS (`_drift._udp`) and UDP pings (on port 47474) to find other Drift-enabled devices.
3.  **State Management:** Feature controllers own send, receive, and settings behavior, while the shell composition layer derives the active screen from those feature states. `DriftAppNotifier` still handles some compatibility-side effects and transfer orchestration.
4.  **Transfer:** When a transfer starts, the Rust backend manages the data stream, providing real-time progress updates back to the Flutter UI for display.

## Project structure

-   `lib/state/`: Business logic and state management (Riverpod).
-   `lib/shell/`: Main UI components and navigation.
-   `rust/src/api/`: Rust implementation of discovery, sending, and receiving logic.
-   `rust_builder/`: Native build glue (Cargokit) for compiling the bridge for each platform.
-   Generated Dart bindings: `lib/src/rust/` (do not edit by hand; regenerate from Rust).
-   FRB config: `flutter_rust_bridge.yaml` (`rust_root: rust/`, `dart_output: lib/src/rust`).

### Why the repo root matters

The Flutter bridge crate (`rust/Cargo.toml`) depends on the workspace crates `drift-app` and `drift-core` via `../../crates/`. Your checkout must include at least:

- `flutter/` (this app)
- `crates/` (shared Rust libraries)
- Root `Cargo.toml` and `Cargo.lock` (workspace metadata used by the Rust toolchain)

If those paths are missing, `cargo` will fail while building the native bridge.

## Prerequisites

Install the following on the machine that will run the build (desktop targets are usually built on their own OS).

1. **Flutter (stable)** — [Install Flutter](https://docs.flutter.dev/get-started/install). Use a version that satisfies `pubspec.yaml` (`environment.sdk`). Run `flutter doctor` and fix any reported issues for the platforms you need.

2. **Rust (stable)** — [Install Rust](https://www.rust-lang.org/tools/install). The workspace uses edition 2021.

3. **cargo-expand** — Required by `flutter_rust_bridge_codegen` when expanding macros:

    ```bash
    cargo install cargo-expand
    ```

4. **flutter_rust_bridge_codegen** — Install a version compatible with the `flutter_rust_bridge` / `flutter_rust_bridge` crate versions pinned in `pubspec.yaml` and `rust/Cargo.toml` (they should stay in lockstep). Example:

    ```bash
    cargo install flutter_rust_bridge_codegen --version 2.12.0
    ```

5. **Enable desktop platforms** (as needed):

    ```bash
    flutter config --enable-macos-desktop
    flutter config --enable-linux-desktop
    flutter config --enable-windows-desktop
    ```

6. **Platform SDKs**
    - **macOS:** Xcode and command-line tools (for `flutter build macos` / iOS).
    - **Linux:** GTK and build tools; install whatever `flutter doctor` lists (commonly `cmake`, `ninja-build`, GTK 3 dev packages—names vary by distribution).
    - **Windows:** [Visual Studio](https://docs.flutter.dev/get-started/install/windows) with the **Desktop development with C++** workload.
    - **Android:** Android Studio / SDK, accepted licenses (`flutter doctor --android-licenses`).
    - **iOS:** Xcode on macOS; Apple Developer account for device distribution and App Store builds.

## Build the app

All commands below are run from the **`flutter/`** directory unless noted.

### 1. Dependencies and code generation

```bash
cd flutter
flutter pub get
flutter_rust_bridge_codegen generate
```

Regenerate whenever you change Rust API types or `flutter_rust_bridge.yaml`. The first native build after a clean checkout will compile the bridge and workspace crates and can take several minutes.

### 2. Debug run (quick iteration)

```bash
flutter run -d macos    # or linux, windows, chrome, android, ios
```

### 3. Release builds by platform

Use `--release` for optimized binaries.

| Platform | Command | Typical output |
| --- | --- | --- |
| **macOS** | `flutter build macos --release` | `build/macos/Build/Products/Release/Drift.app` |
| **Linux** | `flutter build linux --release` | `build/linux/x64/release/bundle/` (executable and bundled libs) |
| **Windows** | `flutter build windows --release` | `build/windows/x64/runner/Release/` |
| **Android (APK)** | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| **Android (Play)** | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` |
| **iOS** | `flutter build ipa --release` | Requires signing/provisioning; see Flutter iOS release docs |

Optional: override version labels at build time, for example:

```bash
flutter build macos --release --build-name=1.0.1 --build-number=2
```

**iOS note:** Release/IPA builds need a configured Xcode team, bundle identifier, and provisioning. Use Xcode or `flutter build ipa` with the appropriate signing settings; this is environment-specific.

**Linux distribution:** Ship the entire `bundle/` directory (or repackage it as AppImage, `.deb`, etc.). Users need compatible system libraries for GTK; the bundle includes most Flutter and app-specific libs.

**Windows distribution:** Ship the contents of `Release/` (`.exe` plus DLLs and data). An installer (MSIX, Inno Setup, etc.) is optional but common for end users.

### 4. CI / headless alignment

The repository’s GitHub Actions workflow (`.github/workflows/flutter-release.yml`) builds **macOS**, **iOS** (unsigned), **Linux**, **Windows**, and **Android** (APK) on each push/PR to `main` (and via `workflow_dispatch`). Each job uses the same core steps: Rust stable, `cargo-expand`, pinned `flutter_rust_bridge_codegen` (see the workflow `env`), `flutter pub get`, `flutter_rust_bridge_codegen generate`, then the platform-specific `flutter build … --release`. The **macOS** and **iOS** builds run on one macOS runner so the native Rust bridge is compiled once for both targets.

## LAN discovery (nearby receivers)

The send screen browses mDNS for `_drift._udp` (same as the CLI `--nearby` path). Receivers also answer a **UDP presence ping** on port **47474** (the SRV port in the advertisement); browsers only list peers that respond, so mDNS-only ghosts are dropped. **Dev builds** on desktop often work without extra setup. **Store / hardened** builds may need platform permissions:

- **macOS**: Enable the Local Network capability where required; add a usage string if the system prompts for local network access.
- **iOS**: Set `NSLocalNetworkUsageDescription` in `Info.plist`; declare the Bonjour service type `_drift._udp` (and related) per Apple’s Bonjour browsing rules.
- **Android**: Multicast/Wi‑Fi may require `CHANGE_WIFI_MULTICAST_STATE` and holding a multicast lock where the OS requires it.

Nearby receive advertising does **not** require a rendezvous server. If no server URL is configured, the app can still appear in nearby scans and receive LAN transfers, but the short pairing code remains unavailable until a reachable rendezvous server is configured.

Simulators, VPNs, and split tunnels can hide LAN peers; the UI falls back to the passive receive state until a transfer arrives.

## Edit the Rust API

1. Update Rust under `rust/src/api/` (and any supporting modules).
2. From `flutter/`, run `flutter_rust_bridge_codegen generate`.
3. Rebuild or hot-restart the Flutter app (`flutter run`).

If you add new dependencies to `rust/Cargo.toml`, run `flutter pub get` if the builder package needs updates, then rebuild so Cargokit picks up the native changes.
