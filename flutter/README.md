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

## Edit The Rust API

1. Update Rust functions under `flutter/rust/src/api/`
2. Regenerate bindings with `flutter_rust_bridge_codegen generate`
3. Re-run the Flutter app
