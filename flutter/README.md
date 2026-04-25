# Drift Mobile & Desktop App

The Flutter-based graphical interface for Drift, powered by the core Drift Rust engine.

## About

This application provides a modern, cross-platform UI for sending and receiving files. It leverages `flutter_rust_bridge` to integrate the high-performance `iroh` networking and transfer logic written in Rust with a beautiful, responsive Flutter shell.

### Key Features in the App
- **Visual Manifests:** Browse file trees before accepting a transfer.
- **Drag & Drop:** Drop files onto the app to start a send draft.
- **Nearby Discovery:** Auto-detect other Drift devices on your local network.
- **Cross-Platform:** Shared logic across iOS, Android, macOS, Linux, and Windows.

---

## Setup & Installation

To build and run the Flutter app from source, you'll need both Flutter and Rust environments configured.

### Prerequisites

1.  **Flutter SDK:** [Install Flutter](https://docs.flutter.dev/get-started/install) (Stable channel).
2.  **Rust Toolchain:** [Install Rust](https://www.rust-lang.org/tools/install).
3.  **flutter_rust_bridge_codegen:** The bridge requires a specific code generation tool.
    ```bash
    cargo install flutter_rust_bridge_codegen --version 2.12.0
    ```
4.  **Platform-specific toolchains:**
    - **macOS/iOS:** Xcode.
    - **Windows:** Visual Studio with "Desktop development with C++".
    - **Linux:** `build-essential`, `pkg-config`, `libnm-dev`, and other Flutter requirements.
    - **Android:** Android Studio and NDK.

### Getting Started

1.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

2.  **Generate the Rust-Bridge bindings:**
    The project uses `flutter_rust_bridge` v2. You must generate the bridge code before the app will compile.
    ```bash
    flutter_rust_bridge_codegen generate
    ```

3.  **Run the app:**
    ```bash
    flutter run
    ```

---

## Development Workflow

### Code Generation

We use `riverpod_generator` and `flutter_rust_bridge`. If you modify any bridge APIs (in `flutter/rust/src/api`) or Riverpod providers (using `@riverpod` annotations), you need to run code generation:

```bash
# Generate both Bridge and Riverpod code
flutter_rust_bridge_codegen generate
flutter pub run build_runner build --delete-conflicting-outputs
```

### Project Structure

- `lib/features/`: UI and logic separated by feature (send, receive, settings, transfers).
- `lib/platform/`: Platform-specific abstractions and the Rust bridge bridge integration.
- `lib/src/rust/`: Generated Dart bindings for the Rust core.
- `rust/`: The Rust bridge crate that wraps `drift-core` and `drift-app`.
- `rust_builder/`: Native build glue using [Cargokit](https://github.com/n0-computer/cargokit).

### Testing

- **Widget & Unit Tests:** `flutter test`
- **Integration Tests:** `flutter test integration_test/transfer_test.dart`

---

## Useful Resources

- [flutter_rust_bridge documentation](https://cjycode.com/flutter_rust_bridge/)
- [Riverpod documentation](https://riverpod.dev/)
- [Drift Testing Strategy](../docs/testing-strategy.md)
